import XCTest
import NeutrinoCore
@testable import NeutrinoSlides

/// The small models: what a Drive row means, what the router accepts, what Settings remembers, and
/// what the history stack does.
///
/// Main-actor isolated because two of the types under test are: `DeepLinkRouter` and `AppSettings`
/// are both observable objects the view tree reads.
@MainActor
final class ModelTests: XCTestCase {

    // MARK: - SlideItem

    func testAPptxIsAPresentation() {
        XCTAssertEqual(SlideItem.slideMIME,
                       "application/vnd.openxmlformats-officedocument.presentationml.presentation")
        XCTAssertTrue(Fixture.deck().isNativeDeck)
        XCTAssertFalse(Fixture.deck(mimeType: Fixture.spreadsheetMIME).isNativeDeck)
        // The bespoke JSON type is gone from the server and the web; nothing here reads it either.
        XCTAssertFalse(Fixture.deck(mimeType: "application/x-neutrino-slide").isNativeDeck)
        XCTAssertFalse(Fixture.folder().isNativeDeck)
    }

    func testThePptxExtensionIsHiddenFromTheTitle() {
        XCTAssertEqual(Fixture.deck(name: "Q3 Review.pptx").displayName, "Q3 Review")
        XCTAssertEqual(Fixture.deck(name: "Q3 Review.PPTX").displayName, "Q3 Review")
        XCTAssertEqual(Fixture.deck(name: "Q3 Review").displayName, "Q3 Review")
        // Only the modern extension is file plumbing; anything else is part of the name.
        XCTAssertEqual(Fixture.deck(name: "Old.ppt").displayName, "Old.ppt")
        XCTAssertEqual(Fixture.deck(name: ".hidden").displayName, ".hidden")
        XCTAssertEqual(Fixture.folder(name: "Decks.pptx").displayName, "Decks.pptx")
    }

    func testDuplicateNamesKeepTheExtensionWhereThereIsOne() {
        XCTAssertEqual(Fixture.deck(name: "Kickoff").duplicateName, "Kickoff copy")
        XCTAssertEqual(Fixture.deck(name: "Kickoff.pptx").duplicateName, "Kickoff copy.pptx")
        XCTAssertEqual(Fixture.deck(name: ".env").duplicateName, ".env copy")
    }

    // MARK: - Sections

    func testOnlyHomeNavigatesIntoFolders() {
        XCTAssertTrue(SlidesSection.home.supportsFolderNavigation)
        for section in SlidesSection.allCases where section != .home {
            XCTAssertFalse(section.supportsFolderNavigation,
                           "\(section.rawValue) has no folder tree to walk")
        }
    }

    func testEverySectionHasAnEmptyState() {
        for section in SlidesSection.allCases {
            XCTAssertFalse(section.emptyMessage.isEmpty)
            XCTAssertFalse(section.emptyIcon.isEmpty)
            XCTAssertFalse(section.iconName.isEmpty)
        }
    }

    // MARK: - Roles

    func testAnUnknownRoleIsTreatedAsTheLeastPrivilegedOne() {
        XCTAssertEqual(ShareRole(serverValue: "administrator"), .viewer)
        XCTAssertEqual(ShareRole(serverValue: "EDITOR"), .editor)
        XCTAssertTrue(ShareRole.editor.canEdit)
        XCTAssertFalse(ShareRole.commenter.canEdit)
        XCTAssertTrue(ShareRole.owner.canManage)
        XCTAssertFalse(ShareRole.editor.canManage)
    }

    // MARK: - Deep links

    func testTheRouterAcceptsSlideLinksOnly() {
        let router = DeepLinkRouter()

        XCTAssertTrue(router.handle(URL(string: "https://www.getneutrino.app/open/slide/abc")!))
        XCTAssertEqual(router.pending?.fileID, "abc")

        XCTAssertFalse(router.handle(URL(string: "https://www.getneutrino.app/open/sheet/abc")!))
        XCTAssertFalse(router.handle(URL(string: "https://example.com/open/slide/abc")!))
        XCTAssertFalse(router.handle(URL(string: "http://www.getneutrino.app/open/slide/abc")!))
    }

    func testTheWwwLessHostResolvesToo() {
        let router = DeepLinkRouter()

        XCTAssertTrue(router.handle(URL(string: "https://getneutrino.app/open/slide/abc")!))
    }

    func testConsumingALinkClearsItSoItIsNotOpenedTwice() {
        let router = DeepLinkRouter()
        router.handle(URL(string: "https://www.getneutrino.app/open/slide/abc?v=4")!)

        let destination = router.consume()

        XCTAssertEqual(destination?.fileID, "abc")
        XCTAssertEqual(destination?.contentVersion, 4)
        XCTAssertNil(router.pending)
        XCTAssertNil(router.consume())
    }

    func testTheAppLinkVocabularyStillRoutesADeckToThisApp() {
        // The shared package decides this, and a change to it reaches this app only when this app
        // ships a build against the new version — which is why it is asserted here too.
        XCTAssertEqual(NeutrinoAppLink.kind(forMIME: SlideItem.slideMIME), .slide)
        XCTAssertEqual(NeutrinoAppLink.url(kind: .slide, fileID: "abc")?.absoluteString,
                       "https://www.getneutrino.app/open/slide/abc")
    }

    // MARK: - Settings

    func testSettingsPersistAndReloadFromTheirOwnSuite() throws {
        let name = "NeutrinoSlidesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(defaults: defaults)
        settings.theme = .dark
        settings.autoSaveInterval = 10
        settings.snapStep = 5
        settings.showNotes = true
        settings.advanceSeconds = 30

        let reloaded = AppSettings(defaults: defaults)

        XCTAssertEqual(reloaded.theme, .dark)
        XCTAssertEqual(reloaded.autoSaveInterval, 10)
        XCTAssertEqual(reloaded.snapStep, 5)
        XCTAssertTrue(reloaded.showNotes)
        XCTAssertEqual(reloaded.advanceSeconds, 30)
    }

    func testAnOutOfRangeSnapStepIsClampedRatherThanTrusted() throws {
        let name = "NeutrinoSlidesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        // What a stale build or a synced preference could have left behind.
        defaults.set(-4.0, forKey: AppSettings.Keys.snapStep)

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.snapStep, 0)

        settings.snapStep = 1_000
        XCTAssertEqual(settings.snapStep, 25)
    }

    func testResetPutsEverythingBack() throws {
        let name = "NeutrinoSlidesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        settings.theme = .light
        settings.showThumbnails = false
        settings.advanceSeconds = 15

        settings.resetToDefaults()

        XCTAssertEqual(settings.theme, .system)
        XCTAssertTrue(settings.showThumbnails)
        XCTAssertEqual(settings.advanceSeconds, 0)
        XCTAssertEqual(settings.autoSaveInterval, AppSettings.defaultAutoSaveInterval)
    }

    func testSettingLabelsReadAsSentences() {
        XCTAssertEqual(AppSettings.autoSaveLabel(for: 3), "Every 3 seconds")
        XCTAssertEqual(AppSettings.snapLabel(for: 0), "Off")
        XCTAssertEqual(AppSettings.snapLabel(for: 2.5), "2.5%")
        XCTAssertEqual(AppSettings.advanceLabel(for: 0), "Manual")
    }

    // MARK: - History

    func testTheHistoryStacksBehaveLikeEveryEditorsDo() {
        var history = EditHistory()
        let first = DeckEdit(before: [], after: [Fixture.slide(id: "a")],
                             selectionBefore: nil, selectionAfter: nil, name: "Add Slide")
        let second = DeckEdit(before: [Fixture.slide(id: "a")],
                              after: [Fixture.slide(id: "a"), Fixture.slide(id: "b")],
                              selectionBefore: nil, selectionAfter: nil, name: "Add Slide")

        history.record(first)
        history.record(second)
        XCTAssertTrue(history.canUndo)
        XCTAssertFalse(history.canRedo)
        XCTAssertEqual(history.undoName, "Add Slide")

        XCTAssertNotNil(history.undo())
        XCTAssertTrue(history.canRedo)

        // Recording after an undo throws the redo stack away: the old future is not reachable.
        history.record(second)
        XCTAssertFalse(history.canRedo)

        history.clear()
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
    }

    func testTheHistoryForgetsAtItsLimitRatherThanGrowingForever() {
        var history = EditHistory()

        for _ in 0..<(EditHistory.limit + 20) {
            history.record(DeckEdit(before: [], after: [], selectionBefore: nil,
                                    selectionAfter: nil, name: "Edit"))
        }

        XCTAssertEqual(history.undoStack.count, EditHistory.limit)
    }

    func testAnEditKnowsWhetherItCarriesAThemeOrMasterChange() {
        let plain = DeckEdit(before: [], after: [], selectionBefore: nil, selectionAfter: nil,
                             name: "Edit")
        XCTAssertFalse(plain.changesTheme)
        XCTAssertFalse(plain.changesMaster)

        let themed = DeckEdit(before: [], after: [], themeBefore: .default, themeAfter: .default,
                              selectionBefore: nil, selectionAfter: nil, name: "Apply Theme")
        XCTAssertTrue(themed.changesTheme)

        // A deck written before the master existed has none, so "absent to present" has to count
        // as a change.
        let mastered = DeckEdit(before: [], after: [], masterBefore: nil, masterAfter: .default,
                                selectionBefore: nil, selectionAfter: nil, name: "Apply Master")
        XCTAssertTrue(mastered.changesMaster)
    }

    // MARK: - Style patches

    func testAPatchOnlyWritesTheFieldsItNames() {
        let style = TextStyle(fontSize: 20, bold: true, color: "#111111", align: "center",
                              fontFamily: "Georgia", lineHeight: 1.4)

        let patched = TextStylePatch(italic: true).applied(to: style)

        XCTAssertTrue(patched.italic)
        XCTAssertEqual(patched.fontSize, 20)
        XCTAssertTrue(patched.bold)
        XCTAssertEqual(patched.color, "#111111")
        XCTAssertEqual(patched.align, "center")
        XCTAssertEqual(patched.lineHeight, 1.4)
    }

    func testAPatchCanClearAnOptionalFieldAsWellAsSetIt() {
        var style = TextStyle()
        style.backgroundColor = "#ffff00"

        XCTAssertNil(TextStylePatch.highlight(nil).applied(to: style).backgroundColor)
        XCTAssertEqual(TextStylePatch.highlight("#00ff00").applied(to: style).backgroundColor,
                       "#00ff00")
        // A patch that does not mention the field leaves it alone, which is the difference the
        // nested optional exists for.
        XCTAssertEqual(TextStylePatch(bold: true).applied(to: style).backgroundColor, "#ffff00")
    }

    func testFontSizesAreClampedWhenApplied() {
        let style = TextStyle(fontSize: 20)

        XCTAssertEqual(TextStylePatch.size(2).applied(to: style).fontSize,
                       TextStylePatch.fontSizeRange.lowerBound)
        XCTAssertEqual(TextStylePatch.size(9_000).applied(to: style).fontSize,
                       TextStylePatch.fontSizeRange.upperBound)
    }
}
