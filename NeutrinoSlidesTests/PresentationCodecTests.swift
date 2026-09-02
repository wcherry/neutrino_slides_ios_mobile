import XCTest
@testable import NeutrinoSlides

/// The contract with the web app: what a stored deck decodes to, and what a save writes back.
///
/// The rule every test here is about is preservation. A phone understands less of the format than
/// the browser does, and the failure this suite exists to prevent is the quiet one — a deck that
/// opens correctly, saves without error, and comes back on the web with the videos missing.
final class PresentationCodecTests: XCTestCase {

    // MARK: - Round trips

    func testSeededDefaultContentDecodesAsAOneSlideDeck() {
        let deck = SlideDeck.decode(from: Data(Fixture.seededDeckJSON.utf8))

        XCTAssertEqual(deck.slides.count, 1)
        XCTAssertEqual(deck.slides[0].elements.count, 2)
        XCTAssertEqual(deck.slides[0].elements.first?.text?.content, "Click to add title")
        XCTAssertEqual(deck.slides[0].elements.first?.text?.style.fontSize, 40)
        XCTAssertEqual(deck.slides[0].transition, "fade")
        XCTAssertEqual(deck.theme.primaryColor, "#4f46e5")
    }

    func testUnreadableBodyOpensAnEmptyDeckRatherThanThrowing() {
        XCTAssertEqual(SlideDeck.decode(from: Data("not json".utf8)).slides.count, 1)
        XCTAssertEqual(SlideDeck.decode(from: Data()).slides.count, 1)
        // `{"slides":[]}` is readable but has nothing to show, which the web editor also replaces
        // with its default deck.
        XCTAssertEqual(SlideDeck.decode(from: Data(#"{"slides":[]}"#.utf8)).slides.count, 1)
    }

    func testEncodeIsStableAcrossTwoSaves() throws {
        let deck = SlideDeck.decode(from: Data(Fixture.seededDeckJSON.utf8))

        let first = try deck.encoded()
        let second = try SlideDeck.decode(from: first).encoded()

        XCTAssertEqual(first, second, "a deck saved twice must produce identical bytes")
    }

    func testRoundTripKeepsEveryModelledField() throws {
        let original = SlideDeck(
            slides: [
                Slide(id: "sl1",
                      background: .gradient("linear-gradient(135deg, #000 0%, #fff 100%)"),
                      elements: [
                        .text(TextElement(id: "t1",
                                          frame: SlideFrame(x: 1, y: 2, w: 3, h: 4),
                                          content: "Title\nSecond line",
                                          style: TextStyle(fontSize: 33, bold: true, italic: true,
                                                           underline: true, color: "#111111",
                                                           align: "center", fontFamily: "Georgia",
                                                           strikethrough: true,
                                                           backgroundColor: "#eeeeee",
                                                           lineHeight: 1.5, spaceBefore: 6,
                                                           spaceAfter: 8, listType: "bullet",
                                                           shadow: true, shadowColor: "#333333"))),
                        .shape(ShapeElement(id: "s1", shape: "hexagon",
                                            frame: SlideFrame(x: 5, y: 6, w: 7, h: 8),
                                            fill: "#ff0000", stroke: "#00ff00", strokeWidth: 3,
                                            strokeDash: "8 4")),
                        .line(LineElement(id: "l1", x1: 10, y1: 20, x2: 30, y2: 40,
                                          stroke: "#0000ff", strokeWidth: 2, strokeDash: "4 2",
                                          startArrow: "triangle", endArrow: "arrow")),
                        .image(ImageElement(id: "i1", frame: SlideFrame(x: 9, y: 9, w: 9, h: 9),
                                            src: "neutrino-drive:file-7", driveFileID: "file-7",
                                            opacity: 0.5, tintColor: "#123456", tintStrength: 0.3,
                                            brightness: 10, contrast: -5, saturation: 20,
                                            warmth: -30, objectFit: "contain")),
                      ],
                      notes: "Say hello",
                      transition: "cube"),
            ],
            theme: SlideTheme(name: "Custom", primaryColor: "#010101", backgroundColor: "#020202",
                              textColor: "#030303", accentColor: "#040404", fontFamily: "Georgia",
                              backgroundImage: "https://example.com/bg.png",
                              gradient: "linear-gradient(90deg, #000, #fff)",
                              defaultTransition: "zoom"),
            master: SlideMaster(background: "#0a0a0a", titleFontSize: 44, titleBold: false,
                                titleColor: "#0b0b0b", bodyFontSize: 22, bodyBold: true,
                                bodyColor: "#0c0c0c")
        )

        let decoded = SlideDeck.decode(from: try original.encoded())

        XCTAssertEqual(decoded, original)
    }

    // MARK: - Preservation

    func testAnUnmodelledElementSurvivesARoundTripWhole() throws {
        let json = """
        {"slides":[{"id":"s1","background":{"type":"color","value":"#fff"},"elements":[
          {"id":"v1","type":"video","x":10,"y":10,"w":50,"h":30,
           "url":"https://youtu.be/abc","autoplay":true,"loop":false,"muted":true,
           "startSeconds":12}
        ],"notes":"","transition":"fade"}],"theme":{"name":"Default","primaryColor":"#4f46e5",
        "backgroundColor":"#ffffff","textColor":"#1f2937","accentColor":"#818cf8",
        "fontFamily":"Inter","defaultTransition":"fade"}}
        """

        let deck = SlideDeck.decode(from: Data(json.utf8))
        let element = try XCTUnwrap(deck.slides.first?.elements.first)
        XCTAssertEqual(element.kind, "video")
        XCTAssertFalse(element.isModelled)

        let written = jsonObject(try deck.encoded())
        let slides = try XCTUnwrap(written["slides"] as? [[String: Any]])
        let elements = try XCTUnwrap(slides[0]["elements"] as? [[String: Any]])
        XCTAssertEqual(elements[0]["url"] as? String, "https://youtu.be/abc")
        XCTAssertEqual(elements[0]["autoplay"] as? Bool, true)
        XCTAssertEqual(elements[0]["startSeconds"] as? Int, 12)
    }

    func testUnknownFieldsOnAModelledElementSurvive() throws {
        let json = """
        {"slides":[{"id":"s1","background":{"type":"color","value":"#fff","blur":4},
          "elements":[{"id":"t1","type":"text","x":0,"y":0,"w":10,"h":10,"content":"Hi",
            "style":{"fontSize":20,"letterSpacing":2},"rotation":45}],
          "notes":"","transition":"fade","hidden":true}],
         "theme":{"name":"T","primaryColor":"#000","backgroundColor":"#fff","textColor":"#111",
          "accentColor":"#222","fontFamily":"Inter","defaultTransition":"fade","mood":"dark"},
         "revision":7}
        """

        let written = jsonObject(try SlideDeck.decode(from: Data(json.utf8)).encoded())

        XCTAssertEqual(written["revision"] as? Int, 7)
        let theme = try XCTUnwrap(written["theme"] as? [String: Any])
        XCTAssertEqual(theme["mood"] as? String, "dark")
        let slides = try XCTUnwrap(written["slides"] as? [[String: Any]])
        XCTAssertEqual(slides[0]["hidden"] as? Bool, true)
        let background = try XCTUnwrap(slides[0]["background"] as? [String: Any])
        XCTAssertEqual(background["blur"] as? Int, 4)
        let elements = try XCTUnwrap(slides[0]["elements"] as? [[String: Any]])
        XCTAssertEqual(elements[0]["rotation"] as? Int, 45)
        let style = try XCTUnwrap(elements[0]["style"] as? [String: Any])
        XCTAssertEqual(style["letterSpacing"] as? Int, 2)
    }

    func testEditingASlideDoesNotDisturbThePreservedElementsBesideIt() throws {
        let json = """
        {"slides":[{"id":"s1","background":{"type":"color","value":"#fff"},"elements":[
          {"id":"d1","type":"diagram","x":0,"y":0,"w":50,"h":50,"diagramId":"dg-1","pageIndex":2},
          {"id":"t1","type":"text","x":0,"y":60,"w":50,"h":10,"content":"Before",
           "style":{"fontSize":20}}
        ],"notes":"","transition":"fade"}],"theme":{"name":"T","primaryColor":"#000",
        "backgroundColor":"#fff","textColor":"#111","accentColor":"#222","fontFamily":"Inter",
        "defaultTransition":"fade"}}
        """
        var deck = SlideDeck.decode(from: Data(json.utf8))

        // The edit a user makes: retype the text box beside the diagram.
        guard case .text(var text) = deck.slides[0].elements[1] else {
            return XCTFail("expected a text element")
        }
        text.content = "After"
        deck.slides[0].elements[1] = .text(text)

        let written = jsonObject(try deck.encoded())
        let slides = try XCTUnwrap(written["slides"] as? [[String: Any]])
        let elements = try XCTUnwrap(slides[0]["elements"] as? [[String: Any]])
        XCTAssertEqual(elements[0]["diagramId"] as? String, "dg-1")
        XCTAssertEqual(elements[0]["pageIndex"] as? Int, 2)
        XCTAssertEqual(elements[1]["content"] as? String, "After")
    }

    // MARK: - Sparse output

    func testOptionalStyleFieldsAreOmittedRatherThanWrittenAsNull() throws {
        let deck = SlideDeck(slides: [Fixture.slide(elements: [Fixture.textElement()])])

        let written = jsonObject(try deck.encoded())
        let slides = try XCTUnwrap(written["slides"] as? [[String: Any]])
        let style = try XCTUnwrap(
            (slides[0]["elements"] as? [[String: Any]])?[0]["style"] as? [String: Any]
        )

        XCTAssertNil(style["lineHeight"])
        XCTAssertNil(style["listType"])
        XCTAssertNil(style["backgroundColor"])
        // The seven the web app always writes are always written.
        XCTAssertNotNil(style["fontSize"])
        XCTAssertNotNil(style["bold"])
        XCTAssertNotNil(style["align"])
        XCTAssertNotNil(style["fontFamily"])
    }

    func testADeckWithNoMasterDoesNotGainOne() throws {
        let json = """
        {"slides":[{"id":"s1","background":{"type":"color","value":"#fff"},"elements":[],
        "notes":"","transition":"none"}],"theme":{"name":"T","primaryColor":"#000",
        "backgroundColor":"#fff","textColor":"#111","accentColor":"#222","fontFamily":"Inter",
        "defaultTransition":"fade"}}
        """

        let deck = SlideDeck.decode(from: Data(json.utf8))
        XCTAssertNil(deck.master)
        // …and reading one is still possible, because every caller needs a master to build from.
        XCTAssertEqual(deck.effectiveMaster, .default)

        XCTAssertNil(jsonObject(try deck.encoded())["master"])
    }

    func testWholeNumbersAreWrittenAsIntegers() throws {
        let deck = SlideDeck(slides: [Fixture.slide(elements: [
            Fixture.textElement(frame: SlideFrame(x: 10, y: 20, w: 30, h: 40)),
        ])])

        let text = String(decoding: try deck.encoded(), as: UTF8.self)

        XCTAssertTrue(text.contains("\"x\":10"), "expected an integer, got: \(text)")
        XCTAssertFalse(text.contains("10.0"))
    }

    // MARK: - Leniency

    func testAStyleMissingEveryFieldStillDecodes() throws {
        let json = """
        {"slides":[{"id":"s1","elements":[{"id":"t1","type":"text","content":"x","style":{}}]}],
         "theme":{}}
        """

        let deck = SlideDeck.decode(from: Data(json.utf8))
        let style = try XCTUnwrap(deck.slides.first?.elements.first?.text?.style)

        XCTAssertEqual(style.fontSize, 24)
        XCTAssertEqual(style.align, "left")
        XCTAssertEqual(style.fontFamily, "Inter")
        XCTAssertEqual(deck.theme, .default)
    }

    func testAnUnrecognisedAlignmentOrTransitionSurvives() throws {
        let json = """
        {"slides":[{"id":"s1","elements":[{"id":"t1","type":"text","content":"x",
          "style":{"align":"justify"}}],"transition":"morph"}],"theme":{}}
        """

        let deck = SlideDeck.decode(from: Data(json.utf8))
        XCTAssertEqual(deck.slides[0].elements[0].text?.style.align, "justify")
        XCTAssertEqual(deck.slides[0].transition, "morph")
        // The renderer maps what it does not know onto something it can draw, without rewriting it.
        XCTAssertEqual(SlideTransition(stored: "morph"), .fade)

        let written = jsonObject(try deck.encoded())
        let slides = try XCTUnwrap(written["slides"] as? [[String: Any]])
        XCTAssertEqual(slides[0]["transition"] as? String, "morph")
    }

    func testAnElementWithNoTypeIsKeptRatherThanDropped() throws {
        let json = """
        {"slides":[{"id":"s1","elements":[{"id":"x1","x":1,"y":2,"w":3,"h":4}]}],"theme":{}}
        """

        let deck = SlideDeck.decode(from: Data(json.utf8))
        XCTAssertEqual(deck.slides[0].elements.count, 1)
        XCTAssertFalse(deck.slides[0].elements[0].isModelled)

        let written = jsonObject(try deck.encoded())
        let slides = try XCTUnwrap(written["slides"] as? [[String: Any]])
        let elements = try XCTUnwrap(slides[0]["elements"] as? [[String: Any]])
        XCTAssertEqual(elements[0]["id"] as? String, "x1")
    }
}
