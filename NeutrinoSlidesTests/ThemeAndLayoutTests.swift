import XCTest
@testable import NeutrinoSlides

/// Themes, masters and layouts — the three things that restyle a deck without being asked what the
/// words are.
final class ThemeAndLayoutTests: XCTestCase {

    // MARK: - Theme backgrounds

    func testAThemesBackgroundPrefersImageThenGradientThenColour() {
        let flat = SlideTheme(name: "F", primaryColor: "#1", backgroundColor: "#fff",
                              textColor: "#2", accentColor: "#3")
        XCTAssertEqual(flat.slideBackground, .color("#fff"))

        var gradient = flat
        gradient.gradient = "linear-gradient(90deg, #000, #fff)"
        // Stored under `type: "color"` with a gradient value, exactly as the web app writes it.
        XCTAssertEqual(gradient.slideBackground.type, "color")
        XCTAssertEqual(gradient.slideBackground.value, "linear-gradient(90deg, #000, #fff)")

        var image = gradient
        image.backgroundImage = "https://example.com/bg.png"
        XCTAssertEqual(image.slideBackground.type, "image")
        XCTAssertEqual(image.slideBackground.objectFit, "cover")
    }

    // MARK: - Applying a theme

    func testApplyingAThemeRestylesBackgroundsTransitionsTextAndShapes() {
        let deck = SlideDeck(slides: [
            Fixture.slide(id: "a", background: .color("#000000"), elements: [
                Fixture.textElement(id: "t", style: TextStyle(fontSize: 30, color: "#111111",
                                                              fontFamily: "Courier New")),
                Fixture.shapeElement(id: "s", fill: "#222222"),
            ], transition: SlideTransition.none.rawValue),
        ])
        let theme = SlideTheme(name: "Ink", primaryColor: "#aa0000", backgroundColor: "#ffffff",
                               textColor: "#00aa00", accentColor: "#0000aa", fontFamily: "Georgia",
                               defaultTransition: SlideTransition.zoom.rawValue)

        let result = ThemeApplication.apply(theme, to: deck)

        let slide = result.slides[0]
        XCTAssertEqual(slide.background, .color("#ffffff"))
        XCTAssertEqual(slide.transition, SlideTransition.zoom.rawValue)
        XCTAssertEqual(slide.elements[0].text?.style.color, "#00aa00")
        XCTAssertEqual(slide.elements[0].text?.style.fontFamily, "Georgia")
        XCTAssertEqual(slide.elements[1].shape?.fill, "#aa0000")
        XCTAssertEqual(result.theme, theme)
    }

    func testApplyingAThemeLeavesContentAndGeometryAlone() {
        let deck = SlideDeck(slides: [
            Fixture.slide(elements: [
                Fixture.textElement(id: "t", frame: SlideFrame(x: 12, y: 34, w: 56, h: 7),
                                    content: "Hand written",
                                    style: TextStyle(fontSize: 31, bold: true, align: "right")),
            ], notes: "Keep me"),
        ])

        let result = ThemeApplication.apply(.default, to: deck)

        let text = result.slides[0].elements[0].text
        XCTAssertEqual(text?.content, "Hand written")
        XCTAssertEqual(text?.frame, SlideFrame(x: 12, y: 34, w: 56, h: 7))
        XCTAssertEqual(text?.style.fontSize, 31)
        XCTAssertEqual(text?.style.bold, true)
        XCTAssertEqual(text?.style.align, "right")
        XCTAssertEqual(result.slides[0].notes, "Keep me")
    }

    func testApplyingAThemeDoesNotTouchImagesOrUnmodelledElements() throws {
        let deck = SlideDeck(slides: [
            Fixture.slide(elements: [
                .image(ImageElement(id: "i", frame: SlideFrame(x: 0, y: 0, w: 10, h: 10),
                                    src: "https://example.com/a.png")),
                Fixture.opaqueElement(id: "o"),
            ]),
        ])

        let result = ThemeApplication.apply(.default, to: deck)

        XCTAssertEqual(result.slides[0].elements[0], deck.slides[0].elements[0])
        XCTAssertEqual(result.slides[0].elements[1], deck.slides[0].elements[1])
    }

    // MARK: - Applying a master

    func testApplyingAMasterSizesTheLargestTextAsTheTitleAndTheRestAsBody() {
        let deck = SlideDeck(slides: [
            Fixture.slide(elements: [
                Fixture.textElement(id: "body", style: TextStyle(fontSize: 20)),
                Fixture.textElement(id: "title", style: TextStyle(fontSize: 48)),
            ]),
        ])
        let master = SlideMaster(background: "#101010", titleFontSize: 60, titleBold: true,
                                 titleColor: "#ff0000", bodyFontSize: 18, bodyBold: false,
                                 bodyColor: "#00ff00")

        let result = ThemeApplication.applyMaster(master, to: deck)

        let body = result.slides[0].elements[0].text
        let title = result.slides[0].elements[1].text
        XCTAssertEqual(title?.style.fontSize, 60)
        XCTAssertEqual(title?.style.color, "#ff0000")
        XCTAssertEqual(body?.style.fontSize, 18)
        XCTAssertEqual(body?.style.color, "#00ff00")
        XCTAssertEqual(result.slides[0].background, .color("#101010"))
        XCTAssertEqual(result.master, master)
    }

    // MARK: - Stored themes

    func testAStoredThemeMapsOntoTheShapeADeckKeeps() throws {
        let json = """
        {"id":"th-1","name":"Server","primaryColor":"#111111","backgroundColor":"#222222",
         "textColor":"#333333","accentColor":"#444444","fontFamily":"Georgia",
         "backgroundImage":null,"gradientBackground":"linear-gradient(90deg, #000, #fff)",
         "defaultTransition":"cube","isSystem":true,"createdAt":"2026-01-01T00:00:00",
         "updatedAt":"2026-01-01T00:00:00"}
        """

        let stored = try JSONDecoder().decode(StoredSlideTheme.self, from: Data(json.utf8))
        let theme = stored.asDeckTheme

        XCTAssertEqual(theme.name, "Server")
        XCTAssertEqual(theme.fontFamily, "Georgia")
        // The one field whose name differs between the row and the deck.
        XCTAssertEqual(theme.gradient, "linear-gradient(90deg, #000, #fff)")
        XCTAssertNil(theme.backgroundImage)
        XCTAssertEqual(theme.defaultTransition, "cube")
    }

    func testBuiltInThemesAreDistinctAndUsable() {
        let names = SlideTheme.builtIns.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(names.contains(SlideTheme.default.name))

        for theme in SlideTheme.builtIns {
            XCTAssertFalse(theme.slideBackground.value.isEmpty, "\(theme.name) has no background")
            XCTAssertNotNil(SlideTransition(rawValue: theme.defaultTransition),
                            "\(theme.name) names a transition that does not exist")
        }
    }

    // MARK: - Layouts

    func testEveryLayoutProducesElementsWithUniqueIds() {
        for layout in SlideLayouts.all where layout.id != "blank" {
            let elements = layout.makeElements(.default, .default)
            XCTAssertFalse(elements.isEmpty, "\(layout.id) produced nothing")
            let ids = elements.map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, "\(layout.id) reused an element id")
        }
    }

    func testTwoApplicationsOfALayoutProduceDifferentIds() {
        let layout = try! XCTUnwrap(SlideLayouts.layout(id: "title-slide"))

        let first = layout.makeElements(.default, .default).map(\.id)
        let second = layout.makeElements(.default, .default).map(\.id)

        XCTAssertTrue(Set(first).isDisjoint(with: Set(second)),
                      "applying a layout twice must not produce colliding ids")
    }

    func testBlankIsBlank() throws {
        let layout = try XCTUnwrap(SlideLayouts.layout(id: "blank"))

        XCTAssertTrue(layout.makeElements(.default, .default).isEmpty)
        XCTAssertTrue(layout.preview.isEmpty)
    }

    func testALayoutBuildsItsTitleFromTheMasterAndItsRuleFromTheTheme() throws {
        let layout = try XCTUnwrap(SlideLayouts.layout(id: "title-content"))
        let master = SlideMaster(background: "#fff", titleFontSize: 52, titleBold: true,
                                 titleColor: "#abcdef", bodyFontSize: 19, bodyBold: true,
                                 bodyColor: "#fedcba")
        var theme = SlideTheme.default
        theme.primaryColor = "#00ff00"

        let elements = layout.makeElements(theme, master)

        XCTAssertEqual(elements.first?.text?.style.fontSize, 52)
        XCTAssertEqual(elements.first?.text?.style.color, "#abcdef")
        XCTAssertEqual(elements.first(where: { $0.shape != nil })?.shape?.fill, "#00ff00")
        XCTAssertEqual(elements.last?.text?.style.fontSize, 19)
        XCTAssertEqual(elements.last?.text?.style.bold, true)
    }

    func testEveryLayoutStaysOnTheSlide() {
        for layout in SlideLayouts.all {
            for element in layout.makeElements(.default, .default) {
                guard let frame = element.frame else { continue }
                XCTAssertGreaterThanOrEqual(frame.minX, 0, "\(layout.id) starts off the left edge")
                XCTAssertGreaterThanOrEqual(frame.minY, 0, "\(layout.id) starts above the slide")
                XCTAssertLessThanOrEqual(frame.maxX, 100, "\(layout.id) runs off the right edge")
                XCTAssertLessThanOrEqual(frame.maxY, 100, "\(layout.id) runs off the bottom")
            }
        }
    }

    func testLayoutPreviewsStayInsideThePreviewBox() {
        for layout in SlideLayouts.all {
            for rect in layout.preview {
                XCTAssertLessThanOrEqual(rect.x + rect.w, SlideLayout.previewSize.width,
                                         "\(layout.id) preview is too wide")
                XCTAssertLessThanOrEqual(rect.y + rect.h, SlideLayout.previewSize.height,
                                         "\(layout.id) preview is too tall")
            }
        }
    }

    // MARK: - Transitions

    func testAnUnknownTransitionPlaysAsFadeWithoutBeingRewritten() {
        XCTAssertEqual(SlideTransition(stored: "morph"), .fade)
        XCTAssertEqual(SlideTransition(stored: "slide"), .slideRight)
        XCTAssertEqual(SlideTransition(stored: "none"), SlideTransition.none)
        XCTAssertEqual(SlideTransition.none.duration, 0)
        XCTAssertGreaterThan(SlideTransition.cube.duration, 0)
    }
}
