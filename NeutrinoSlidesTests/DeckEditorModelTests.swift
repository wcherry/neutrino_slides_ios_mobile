import XCTest
import Sodium
@testable import NeutrinoSlides

/// The editor's behaviour: what an edit does to the deck, what undo puts back, and what a save
/// does about a conflict.
@MainActor
final class DeckEditorModelTests: XCTestCase {

    private var service: SlideContentService!
    private var model: DeckEditorModel!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        TestServer.use()
        TestKeys.install()
        TestTokens.install()
        service = SlideContentService(session: MockURLProtocol.makeSession())
        model = DeckEditorModel(item: Fixture.deck(id: "d1", contentVersion: 4),
                                contentService: service, driveService: nil)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        TestKeys.remove()
        TestTokens.remove()
        TestServer.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    /// Answers the four requests a load makes, and any save that follows.
    @discardableResult
    private func stubLoad(deck: String = Fixture.seededDeckJSON,
                          role: String = "owner",
                          saveStatus: Int = 200,
                          saveBody: String? = nil) throws -> Bytes {
        let dek = Sodium().secretStream.xchacha20poly1305.key()
        let sealed = try service.sealDEK(dek)
        let ciphertext = try service.encrypt(text: deck, dek: dek,
                                             xcss: Sodium().secretStream.xchacha20poly1305)
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let respond = { (status: Int, data: Data) in
                (HTTPURLResponse(url: request.url!, statusCode: status,
                                 httpVersion: nil, headerFields: nil)!, data)
            }
            if path.hasSuffix("/info") {
                return respond(200, Data("""
                {"id":"d1","name":"Kickoff","sizeBytes":10,"folderId":null,
                 "mimeType":"\(SlideItem.slideMIME)","updatedAt":"2026-08-10T12:00:00",
                 "yourRole":"\(role)","contentVersion":4}
                """.utf8))
            }
            if path.hasSuffix("/key") {
                return respond(200, Data("""
                {"encrypted_file_key":"\(sealed.sealed)","key_version":\(sealed.keyVersion)}
                """.utf8))
            }
            if request.httpMethod == "PUT" {
                let body = saveBody ?? """
                {"id":"d1","name":"Kickoff","folderId":null,"sizeBytes":42,
                 "mimeType":"\(SlideItem.slideMIME)","updatedAt":"2026-08-10T12:05:00",
                 "contentVersion":5}
                """
                return respond(saveStatus, Data(body.utf8))
            }
            return respond(200, ciphertext)
        }
        return dek
    }

    /// The decks every save actually uploaded, decrypted out of their multipart bodies.
    ///
    /// The boundary is read from the request's own `Content-Type` rather than searched for, because
    /// the part being extracted is ciphertext: any byte sequence can appear in it, `\r\n--`
    /// included, and a delimiter search would eventually cut a body in the wrong place.
    private func savedDecks(dek: Bytes) throws -> [SlideDeck] {
        try MockURLProtocol.bodies.indices.compactMap { index -> SlideDeck? in
            let request = MockURLProtocol.requests[index]
            guard request.httpMethod == "PUT",
                  let contentType = request.value(forHTTPHeaderField: "Content-Type"),
                  let boundary = contentType.components(separatedBy: "boundary=").last
            else { return nil }

            let body = MockURLProtocol.bodies[index]
            guard let headerEnd = body.range(of: Data("\r\n\r\n".utf8)) else { return nil }
            let trailing = body[headerEnd.upperBound...]
            guard let end = trailing.range(of: Data("\r\n--\(boundary)".utf8)) else { return nil }
            let ciphertext = Data(trailing[..<end.lowerBound])
            return SlideDeck.decode(from: try service.decrypt(data: ciphertext, dek: dek))
        }
    }

    // MARK: - Loading

    func testLoadOpensTheDeckOnTheFirstSlide() async throws {
        try stubLoad()

        await model.load()

        XCTAssertEqual(model.slides.count, 1)
        XCTAssertEqual(model.selectedSlideIndex, 0)
        XCTAssertNil(model.selectedElementID)
        XCTAssertEqual(model.currentSlide?.elements.count, 2)
        XCTAssertTrue(model.isEditable)
        XCTAssertNil(model.loadError)
    }

    func testASharedReadOnlyDeckOpensAsAViewer() async throws {
        try stubLoad(role: "viewer")

        await model.load()

        XCTAssertFalse(model.isEditable)
        model.addSlide()
        XCTAssertEqual(model.slides.count, 1, "a viewer must not be able to change the deck")
    }

    func testAFileThatIsNotAPresentationIsRefused() async throws {
        MockURLProtocol.handler = { request in
            let data = Data("""
            {"id":"d1","name":"Deck.pptx","sizeBytes":10,"folderId":null,
             "mimeType":"\(SlideItem.pptxMIME)","updatedAt":"2026-08-10T12:00:00",
             "yourRole":"owner"}
            """.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!, data)
        }

        await model.load()

        XCTAssertNil(model.deck)
        XCTAssertNotNil(model.loadError)
    }

    // MARK: - Slides

    func testAddingASlideInsertsAfterTheCurrentOneAndSelectsIt() async throws {
        try stubLoad()
        await model.load()

        model.addSlide()

        XCTAssertEqual(model.slides.count, 2)
        XCTAssertEqual(model.selectedSlideIndex, 1)
        XCTAssertTrue(model.currentSlide?.elements.isEmpty ?? false)
        // The new slide takes the theme's background and transition, as it does on the web.
        XCTAssertEqual(model.currentSlide?.background, model.theme.slideBackground)
        XCTAssertEqual(model.currentSlide?.transition, model.theme.defaultTransition)
    }

    func testDuplicatingASlideCopiesItsElementsUnderNewIds() async throws {
        try stubLoad()
        await model.load()
        let original = try XCTUnwrap(model.currentSlide)

        model.duplicateSlide()

        XCTAssertEqual(model.slides.count, 2)
        let copy = try XCTUnwrap(model.currentSlide)
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.elements.map(\.displayName), original.elements.map(\.displayName))
        XCTAssertTrue(Set(copy.elements.map(\.id))
            .isDisjoint(with: Set(original.elements.map(\.id))))
    }

    func testTheLastSlideCannotBeDeleted() async throws {
        try stubLoad()
        await model.load()

        XCTAssertFalse(model.canDeleteSlide)
        model.deleteSlide()

        XCTAssertEqual(model.slides.count, 1)
    }

    func testDeletingASlideSelectsTheOneBefore() async throws {
        try stubLoad()
        await model.load()
        model.addSlide()
        model.addSlide()
        XCTAssertEqual(model.selectedSlideIndex, 2)

        model.deleteSlide()

        XCTAssertEqual(model.slides.count, 2)
        XCTAssertEqual(model.selectedSlideIndex, 1)
    }

    func testReorderingMovesTheSlideAndFollowsItWithTheSelection() async throws {
        try stubLoad()
        await model.load()
        model.addSlide()
        let moved = try XCTUnwrap(model.currentSlide?.id)

        model.moveSlide(from: 1, to: 0)

        XCTAssertEqual(model.slides.first?.id, moved)
        XCTAssertEqual(model.selectedSlideIndex, 0)
    }

    func testMovingASlideOntoItselfChangesNothing() async throws {
        try stubLoad()
        await model.load()
        model.addSlide()
        let before = model.slides
        let token = model.historyToken

        model.moveSlide(from: 1, to: 1)
        model.moveSlide(from: 1, to: 2)

        XCTAssertEqual(model.slides, before)
        XCTAssertEqual(model.historyToken, token, "a no-op must not land in the history")
    }

    // MARK: - Elements

    func testAddingATextBoxSelectsItAndStylesItFromTheMaster() async throws {
        try stubLoad()
        await model.load()

        model.addTextBox()

        let element = try XCTUnwrap(model.selectedElement)
        XCTAssertEqual(element.kind, "text")
        XCTAssertEqual(element.text?.style.fontSize, model.master.bodyFontSize)
        XCTAssertEqual(element.text?.style.fontFamily, model.theme.fontFamily)
    }

    func testAddingAShapeUsesTheThemesPrimaryColour() async throws {
        try stubLoad()
        await model.load()

        model.addShape("hexagon")

        XCTAssertEqual(model.selectedElement?.shape?.shape, "hexagon")
        XCTAssertEqual(model.selectedElement?.shape?.fill, model.theme.primaryColor)
    }

    func testDeletingTheSelectedElementClearsTheSelection() async throws {
        try stubLoad()
        await model.load()
        model.addTextBox()
        let count = model.currentSlide?.elements.count ?? 0

        model.deleteSelectedElement()

        XCTAssertEqual(model.currentSlide?.elements.count, count - 1)
        XCTAssertNil(model.selectedElementID)
    }

    func testDuplicatingAnElementOffsetsTheCopySoItIsVisible() async throws {
        try stubLoad()
        await model.load()
        model.select(elementID: model.currentSlide?.elements.first?.id)
        let original = try XCTUnwrap(model.selectedElement?.frame)

        model.duplicateSelectedElement()

        let copy = try XCTUnwrap(model.selectedElement?.frame)
        XCTAssertNotEqual(copy, original)
        XCTAssertEqual(copy.w, original.w, accuracy: 0.001)
    }

    func testZOrderCommandsMoveTheElementThroughTheStack() async throws {
        try stubLoad()
        await model.load()
        let first = try XCTUnwrap(model.currentSlide?.elements.first?.id)
        model.select(elementID: first)

        model.reorderSelectedElement(by: 1)
        XCTAssertEqual(model.currentSlide?.elements.last?.id, first)

        model.sendSelectedElement(toFront: false)
        XCTAssertEqual(model.currentSlide?.elements.first?.id, first)
    }

    func testEditingTextIsRecordedOnceAndDroppedWhenNothingChanged() async throws {
        try stubLoad()
        await model.load()
        let id = try XCTUnwrap(model.currentSlide?.elements.first?.id)

        model.setText("New title", forElement: id)
        XCTAssertEqual(model.currentSlide?.elements.first?.text?.content, "New title")

        let token = model.historyToken
        model.setText("New title", forElement: id)
        XCTAssertEqual(model.historyToken, token, "an edit that changes nothing is not an edit")
    }

    func testStylePatchesOnlyTouchTheFieldsTheyName() async throws {
        try stubLoad()
        await model.load()
        let id = try XCTUnwrap(model.currentSlide?.elements.first?.id)
        model.select(elementID: id)
        let before = try XCTUnwrap(model.selectedElement?.text?.style)

        model.applyTextStyle(TextStylePatch(italic: true), name: "Italic")

        let after = try XCTUnwrap(model.selectedElement?.text?.style)
        XCTAssertTrue(after.italic)
        XCTAssertEqual(after.fontSize, before.fontSize)
        XCTAssertEqual(after.color, before.color)
        XCTAssertEqual(after.align, before.align)
    }

    func testFontSizeStepsAreClampedToTheAllowedRange() async throws {
        try stubLoad()
        await model.load()
        let id = try XCTUnwrap(model.currentSlide?.elements.first?.id)
        model.select(elementID: id)

        for _ in 0..<100 { model.stepFontSize(by: -TextStylePatch.fontSizeStep) }
        XCTAssertEqual(model.selectedElement?.text?.style.fontSize,
                       TextStylePatch.fontSizeRange.lowerBound)

        for _ in 0..<200 { model.stepFontSize(by: TextStylePatch.fontSizeStep) }
        XCTAssertEqual(model.selectedElement?.text?.style.fontSize,
                       TextStylePatch.fontSizeRange.upperBound)
    }

    func testMovingAnElementIsOneEditRatherThanOnePerGestureStep() async throws {
        try stubLoad()
        await model.load()
        let id = try XCTUnwrap(model.currentSlide?.elements.first?.id)
        let token = model.historyToken

        model.setFrame(SlideFrame(x: 30, y: 30, w: 40, h: 20), forElement: id)

        XCTAssertEqual(model.historyToken, token + 1)
        XCTAssertEqual(model.currentSlide?.elements.first?.frame,
                       SlideFrame(x: 30, y: 30, w: 40, h: 20))
    }

    // MARK: - Layout and theme

    func testApplyingALayoutReplacesTheSlideAndClearsTheSelection() async throws {
        try stubLoad()
        await model.load()
        model.select(elementID: model.currentSlide?.elements.first?.id)
        let layout = try XCTUnwrap(SlideLayouts.layout(id: "quote"))

        model.applyLayout(layout)

        XCTAssertEqual(model.currentSlide?.elements.count, 3)
        XCTAssertNil(model.selectedElementID)
    }

    func testApplyingAThemeIsUndoableInOneStep() async throws {
        try stubLoad()
        await model.load()
        let before = try XCTUnwrap(model.deck)
        let theme = SlideTheme(name: "Ink", primaryColor: "#000000", backgroundColor: "#111111",
                               textColor: "#eeeeee", accentColor: "#888888")

        model.applyTheme(theme)
        XCTAssertEqual(model.theme.name, "Ink")

        model.undo()

        XCTAssertEqual(model.deck, before)
    }

    // MARK: - Undo

    func testUndoAndRedoWalkTheHistory() async throws {
        try stubLoad()
        await model.load()

        model.addSlide()
        model.addTextBox()
        XCTAssertEqual(model.slides.count, 2)

        model.undo()
        XCTAssertTrue(model.currentSlide?.elements.isEmpty ?? false)

        model.undo()
        XCTAssertEqual(model.slides.count, 1)

        model.redo()
        XCTAssertEqual(model.slides.count, 2)
        XCTAssertTrue(model.canUndo)
    }

    func testUndoingASlideDeletionPutsTheSelectionBackOnIt() async throws {
        try stubLoad()
        await model.load()
        model.addSlide()
        let deleted = try XCTUnwrap(model.currentSlide?.id)

        model.deleteSlide()
        XCTAssertEqual(model.selectedSlideIndex, 0)

        model.undo()

        XCTAssertEqual(model.slides.count, 2)
        XCTAssertEqual(model.currentSlide?.id, deleted)
    }

    func testUndoNamesTheEditItWouldReverse() async throws {
        try stubLoad()
        await model.load()

        model.addSlide()

        XCTAssertEqual(model.undoName, "Add Slide")
    }

    // MARK: - Saving

    func testSaveUploadsTheEditedDeckEncrypted() async throws {
        let dek = try stubLoad()
        await model.load()
        model.addSlide()

        await model.flush()

        let decks = try savedDecks(dek: dek)
        XCTAssertEqual(decks.last?.slides.count, 2)
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testSavesAreSerialisedRatherThanOverlapping() async throws {
        try stubLoad()
        await model.load()

        model.addSlide()
        model.queueSave()
        model.queueSave()
        model.addTextBox()
        model.queueSave()
        await model.flush()

        let puts = MockURLProtocol.requests.filter { $0.httpMethod == "PUT" }
        XCTAssertLessThanOrEqual(puts.count, 3, "queued saves must coalesce, not stack up")
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testTheFirstSaveSendsTheVersionTheDeckWasReadAt() async throws {
        try stubLoad()
        await model.load()
        model.addSlide()

        await model.flush()

        let put = try XCTUnwrap(MockURLProtocol.requests.first { $0.httpMethod == "PUT" })
        XCTAssertEqual(put.url?.query, "expectedContentVersion=4")
    }

    func testAConflictIsSurfacedAndStopsFurtherSaves() async throws {
        try stubLoad(saveStatus: 409, saveBody: """
        {"error":{"code":"CONTENT_VERSION_CONFLICT","message":"expected 4, found 9"}}
        """)
        await model.load()
        model.addSlide()

        await model.flush()

        XCTAssertNotNil(model.conflict)
        XCTAssertEqual(model.conflict?.serverVersion, 9)
        XCTAssertTrue(model.hasUnsavedChanges)

        let before = MockURLProtocol.requests.filter { $0.httpMethod == "PUT" }.count
        model.saveIfNeeded()
        await model.flush()
        XCTAssertEqual(MockURLProtocol.requests.filter { $0.httpMethod == "PUT" }.count, before,
                       "an unresolved conflict must not be saved over")
    }

    func testKeepingTheLocalCopySavesAgainstTheServersVersion() async throws {
        try stubLoad(saveStatus: 409, saveBody: """
        {"error":{"code":"CONTENT_VERSION_CONFLICT","message":"expected 4, found 9"}}
        """)
        await model.load()
        model.addSlide()
        await model.flush()
        XCTAssertNotNil(model.conflict)

        // The other device's write has landed; ours is the one the user chose to keep.
        try stubLoad(saveStatus: 200)
        model.keepLocalCopyAfterConflict()
        await model.flush()

        let put = try XCTUnwrap(MockURLProtocol.requests.last { $0.httpMethod == "PUT" })
        XCTAssertEqual(put.url?.query, "expectedContentVersion=9")
        XCTAssertNil(model.conflict)
    }

    func testReloadingAfterAConflictDiscardsTheLocalEditsAndTheHistory() async throws {
        try stubLoad(saveStatus: 409, saveBody: """
        {"error":{"code":"CONTENT_VERSION_CONFLICT","message":"expected 4, found 9"}}
        """)
        await model.load()
        model.addSlide()
        await model.flush()

        await model.reloadAfterConflict()

        XCTAssertEqual(model.slides.count, 1)
        XCTAssertFalse(model.canUndo, "undo into discarded edits would put them back")
        XCTAssertNil(model.conflict)
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testANewDecksPlaintextSeedIsEncryptedOnOpen() async throws {
        let dek = Sodium().secretStream.xchacha20poly1305.key()
        let sealed = try service.sealDEK(dek)
        MockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let ok = { (data: Data) in
                (HTTPURLResponse(url: request.url!, statusCode: 200,
                                 httpVersion: nil, headerFields: nil)!, data)
            }
            if path.hasSuffix("/info") {
                return ok(Data("""
                {"id":"d1","name":"Kickoff","sizeBytes":10,"folderId":null,
                 "mimeType":"\(SlideItem.slideMIME)","updatedAt":"2026-08-10T12:00:00",
                 "yourRole":"owner","contentVersion":1}
                """.utf8))
            }
            // No key ref yet: the file was created by the server and nobody has opened it.
            if path.hasSuffix("/key"), request.httpMethod == "GET" {
                return (HTTPURLResponse(url: request.url!, statusCode: 404,
                                        httpVersion: nil, headerFields: nil)!, Data())
            }
            if request.httpMethod == "PUT", path.hasSuffix("/autosave") {
                return ok(Data("""
                {"id":"d1","name":"Kickoff","folderId":null,"sizeBytes":42,
                 "mimeType":"\(SlideItem.slideMIME)","updatedAt":"2026-08-10T12:05:00",
                 "contentVersion":2}
                """.utf8))
            }
            if path.hasSuffix("/key") { return ok(Data("{\"encryptedFileKey\":\"\(sealed.sealed)\"}".utf8)) }
            // The plaintext the server seeded at create time.
            return ok(Data(Fixture.seededDeckJSON.utf8))
        }

        await model.load()
        await model.flush()

        XCTAssertEqual(model.slides.count, 1)
        XCTAssertTrue(MockURLProtocol.requests.contains {
            $0.httpMethod == "PUT" && $0.url?.path.hasSuffix("/autosave") == true
        }, "the plaintext seed has to be replaced with ciphertext on open")
    }
}
