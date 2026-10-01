import XCTest
import NeutrinoCore
@testable import NeutrinoSlides

/// Browsing and organising: what each section asks the server for, and what an optimistic mutation
/// does when the server refuses.
@MainActor
final class SlidesDriveServiceTests: XCTestCase {

    private var service: SlidesDriveService!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        TestServer.use()
        TestTokens.install()
        service = SlidesDriveService(session: MockURLProtocol.makeSession())
    }

    override func tearDown() {
        MockURLProtocol.reset()
        TestTokens.remove()
        TestServer.reset()
        super.tearDown()
    }

    // MARK: - Listings

    func testHomeListsTheDriveRootFilteredToPresentations() async {
        MockURLProtocol.respond(json: String(decoding: Fixture.listing(
            files: [Fixture.fileJSON()], folders: [Fixture.folderJSON()]
        ), as: UTF8.self))

        await service.load(.home)

        let url = MockURLProtocol.requests.first?.url
        XCTAssertEqual(url?.path, "/api/v1/drive/folders/\(TestTokens.userId)")
        XCTAssertTrue(url?.query?.contains("type=slide") ?? false,
                      "every listing has to be filtered server-side")
        XCTAssertEqual(service.items(in: .home).count, 2)
    }

    func testEachSectionAsksItsOwnEndpoint() async {
        let expectations: [(SlidesSection, String)] = [
            (.recent, "/api/v1/drive/recent"),
            (.favorites, "/api/v1/drive/starred"),
            (.shared, "/api/v1/drive/shared-with-me"),
            (.trash, "/api/v1/drive/trash"),
        ]

        for (section, path) in expectations {
            MockURLProtocol.reset()
            MockURLProtocol.respond(json: String(decoding: Fixture.listing(), as: UTF8.self))

            await service.load(section)

            XCTAssertEqual(MockURLProtocol.requests.first?.url?.path, path)
            XCTAssertTrue(MockURLProtocol.requests.first?.url?.query?.contains("type=slide") ?? false)
        }
    }

    func testAFailedLoadIsReportedRatherThanLeavingAnEmptyList() async {
        MockURLProtocol.respond(json: "{}", statusCode: 500)

        await service.load(.recent)

        XCTAssertNotNil(service.error)
        XCTAssertFalse(service.isLoading)
    }

    func testReloadingAFolderReplacesItsRowsRatherThanDuplicatingThem() async {
        MockURLProtocol.respond(json: String(decoding: Fixture.listing(
            files: [Fixture.fileJSON()]
        ), as: UTF8.self))

        await service.load(.home)
        await service.load(.home)

        XCTAssertEqual(service.items(in: .home).count, 1)
    }

    func testASharedItemIsMarkedAndKeepsNoOwnersStar() async {
        MockURLProtocol.respond(json: String(decoding: Fixture.listing(
            files: [Fixture.fileJSON(isStarred: true)]
        ), as: UTF8.self))

        await service.load(.shared)

        let item = service.items(in: .shared).first
        XCTAssertEqual(item?.isShared, true)
        XCTAssertEqual(item?.isStarred, false, "the star on a shared row is the owner's, not ours")
    }

    // MARK: - Single item

    func testFetchingAnItemRefusesAFileThatIsNotAPresentation() async {
        MockURLProtocol.respond(json: Fixture.fileJSON(mimeType: Fixture.spreadsheetMIME))

        do {
            _ = try await service.fetchItem(id: "deck-1")
            XCTFail("expected notFound")
        } catch SlidesDriveError.notFound {
            // Expected: an `/open/slide/…` link that names a spreadsheet is a malformed link.
        } catch {
            XCTFail("expected notFound, got \(error)")
        }
    }

    func testFetchingAnItemResolvesAPptx() async throws {
        MockURLProtocol.respond(json: Fixture.fileJSON(name: "Kickoff.pptx"))

        let item = try await service.fetchItem(id: "deck-1")

        XCTAssertTrue(item.isNativeDeck)
        XCTAssertEqual(item.displayName, "Kickoff")
    }

    // MARK: - Mutations

    func testRenamingKeepsExactlyOnePptxExtension() async {
        let item = Fixture.deck(id: "d1", name: "Old.pptx")
        service = SlidesDriveService(home: [item], session: MockURLProtocol.makeSession())
        MockURLProtocol.respond(json: Fixture.fileJSON(id: "d1", name: "New.pptx"))

        service.rename(itemID: "d1", to: "New.pptx")
        XCTAssertEqual(service.item(id: "d1")?.name, "New.pptx")

        service.rename(itemID: "d1", to: "  ")
        XCTAssertEqual(service.item(id: "d1")?.name, "Untitled presentation.pptx")
    }

    func testRenameIsOptimisticAndRolledBackWhenTheServerRefuses() async {
        let item = Fixture.deck(id: "d1", name: "Old")
        service = SlidesDriveService(home: [item], session: MockURLProtocol.makeSession())
        MockURLProtocol.respond(json: "{}", statusCode: 500)

        service.rename(itemID: "d1", to: "New")
        XCTAssertEqual(service.item(id: "d1")?.name, "New.pptx", "the row changes before the request")

        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(service.item(id: "d1")?.name, "Old")
        XCTAssertNotNil(service.error)
    }

    func testStarringMovesTheRowIntoFavoritesWithoutARefetch() async {
        let item = Fixture.deck(id: "d1")
        service = SlidesDriveService(home: [item], session: MockURLProtocol.makeSession())
        MockURLProtocol.respond(json: Fixture.fileJSON(isStarred: true))

        service.setStarred(itemID: "d1", isStarred: true)

        XCTAssertEqual(service.items(in: .favorites).map(\.id), ["d1"])
        XCTAssertEqual(service.item(id: "d1")?.isStarred, true)
    }

    func testTrashingRemovesTheRowFromEveryViewItAppearedIn() async {
        var item = Fixture.deck(id: "d1")
        item.isStarred = true
        service = SlidesDriveService(home: [item], recents: [item], starred: [item],
                                     session: MockURLProtocol.makeSession())
        MockURLProtocol.respond(json: "{\"affected\":1}")

        service.delete(itemID: "d1")

        XCTAssertTrue(service.items(in: .home).isEmpty)
        XCTAssertTrue(service.items(in: .favorites).isEmpty)
        XCTAssertTrue(service.items(in: .recent).isEmpty)
        XCTAssertEqual(service.items(in: .trash).map(\.id), ["d1"])
    }

    func testAFolderCannotBeMovedInsideItself() async {
        let parent = Fixture.folder(id: "f1")
        let child = Fixture.folder(id: "f2", parentID: "f1")
        service = SlidesDriveService(home: [parent, child], session: MockURLProtocol.makeSession())

        service.move(itemID: "f1", to: "f2")

        XCTAssertNil(service.item(id: "f1")?.parentID)
        XCTAssertEqual(MockURLProtocol.requestCount, 0, "a move that cannot land is not attempted")
    }

    func testBreadcrumbWalksUpTheFolderChain() {
        let root = Fixture.folder(id: "f1", name: "Decks")
        let child = Fixture.folder(id: "f2", name: "2026", parentID: "f1")
        service = SlidesDriveService(home: [root, child])

        XCTAssertEqual(service.breadcrumb(to: "f2").map(\.name), ["Decks", "2026"])
        XCTAssertTrue(service.breadcrumb(to: nil).isEmpty)
    }

    func testASavedDeckUpdatesItsRowInEveryListing() {
        let item = Fixture.deck(id: "d1", size: 10)
        service = SlidesDriveService(home: [item], recents: [item])

        service.presentationWasSaved(itemID: "d1", size: 4096,
                                     modifiedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                     contentVersion: 9)

        XCTAssertEqual(service.items(in: .home).first?.size, 4096)
        XCTAssertEqual(service.items(in: .recent).first?.contentVersion, 9)
    }

    // MARK: - Offline

    func testAMutationIsRefusedRatherThanQueuedWhenOffline() async {
        let item = Fixture.deck(id: "d1", name: "Old")
        service = SlidesDriveService(home: [item], session: MockURLProtocol.makeSession())
        // `autoStart: false` keeps a live path monitor out of the test process, and the test hook
        // drives the value — otherwise this test would pass or fail depending on whether the
        // machine running it happened to be online.
        let monitor = NetworkMonitor(autoStart: false)
        monitor.setPathForTesting(isOnline: false, isExpensive: false)
        service.networkMonitor = monitor

        service.rename(itemID: "d1", to: "New")

        XCTAssertEqual(service.item(id: "d1")?.name, "Old")
        XCTAssertNotNil(service.error)
        XCTAssertEqual(MockURLProtocol.requestCount, 0)
    }
}
