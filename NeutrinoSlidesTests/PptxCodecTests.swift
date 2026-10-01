import XCTest
import NeutrinoOOXML
@testable import NeutrinoSlides

/// The `.pptx` a presentation is stored as: the lossless model round trip, the digest that keeps a
/// stale model from overwriting an outside edit, the PresentationML half PowerPoint reads, and the
/// reader a deck from anywhere else is opened with.
final class PptxCodecTests: XCTestCase {

    // MARK: - Fixtures

    /// A deck carrying one of most things: run formatting, every element kind including one this
    /// app does not model, three kinds of background, notes and transitions.
    private func richDeck() -> SlideDeck {
        let title = SlideElement.text(TextElement(
            id: "t1", frame: SlideFrame(x: 10, y: 20, w: 80, h: 20),
            content: "Quarterly <review> & plan\nSecond line",
            style: TextStyle(fontSize: 40, bold: true, italic: true, underline: true,
                             color: "#1e40af", align: "center", fontFamily: "Georgia",
                             strikethrough: true, backgroundColor: "#fef3c7", lineHeight: 1.4,
                             listType: "bullet")))
        let shape = SlideElement.shape(ShapeElement(
            id: "s1", shape: "hexagon", frame: SlideFrame(x: 5, y: 60, w: 20, h: 25),
            fill: "rgba(16, 185, 129, 0.5)", stroke: "#065f46", strokeWidth: 3, strokeDash: "8 4"))
        let chevron = SlideElement.shape(ShapeElement(
            id: "s2", shape: "chevron-l", frame: SlideFrame(x: 30, y: 60, w: 10, h: 10),
            fill: "#ef4444"))
        let line = SlideElement.line(LineElement(
            id: "l1", x1: 80, y1: 90, x2: 40, y2: 70, stroke: "#111827", strokeWidth: 2,
            startArrow: "none", endArrow: "triangle"))
        let image = SlideElement.image(ImageElement(
            id: "i1", frame: SlideFrame(x: 60, y: 5, w: 30, h: 30), src: Self.pngDataURL,
            opacity: 0.5))
        let driveImage = SlideElement.image(ImageElement(
            id: "i2", frame: SlideFrame(x: 0, y: 0, w: 10, h: 10), src: "neutrino-drive:file-9"))
        let embed = SlideElement.opaque(OpaqueElement([
            "id": .string("o1"), "type": .string("sheetEmbed"),
            "x": .number(1), "y": .number(2), "w": .number(3), "h": .number(4),
            "spreadsheetId": .string("sheet-9"),
        ]))

        return SlideDeck(
            slides: [
                Slide(id: "a", background: .color("#f8fafc"),
                      elements: [title, shape, chevron, line, image, driveImage, embed],
                      notes: "Open with the numbers.\nThen the plan & ask.",
                      transition: SlideTransition.dissolve.rawValue),
                Slide(id: "b", background: .gradient(SlideGradients.presets[12]),
                      elements: [], notes: "", transition: SlideTransition.slideLeft.rawValue),
                // The web's `applyTheme` stores a gradient under `type: "color"`.
                Slide(id: "c", background: .color("linear-gradient(90deg, #000000 0%, #ffffff 100%)"),
                      elements: [], notes: "", transition: SlideTransition.cube.rawValue),
            ],
            theme: .default,
            master: .default)
    }

    /// A 1×1 red PNG.
    private static let pngDataURL = "data:image/png;base64,"
        + "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="

    // MARK: - The model round trip

    func testADeckSurvivesASaveExactly() throws {
        let deck = richDeck()

        let decoded = try PptxCodec.decode(PptxCodec.encode(deck))

        // Everything — the opaque embed, the Drive picture this codec cannot embed, the cube
        // transition PresentationML has no plain name for — because the model is what is read back.
        XCTAssertEqual(decoded, deck)
    }

    func testEncodingIsDeterministic() throws {
        // The offline cache compares stored ciphertext to decide whether a deck changed; a package
        // whose bytes moved on every save would make each no-op save look like an edit.
        XCTAssertEqual(try PptxCodec.encode(richDeck()), try PptxCodec.encode(richDeck()))
    }

    func testTheModelEnvelopeIsTheShapeTheWebReads() throws {
        let zip = try ZipArchive(data: PptxCodec.encode(richDeck()))
        let raw = try XCTUnwrap(zip.data(for: "neutrino/model.json"))
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])

        XCTAssertEqual(envelope["version"] as? Int, 1)
        XCTAssertEqual(envelope["app"] as? String, "slides")
        XCTAssertEqual((envelope["digest"] as? String)?.count, 16)
        // A string of JSON, which the web hands to `JSON.parse`.
        let model = try XCTUnwrap(envelope["model"] as? String)
        XCTAssertEqual(SlideDeck.decode(from: Data(model.utf8)), richDeck())
        // `.json` has to be declared, or the package is malformed.
        XCTAssertTrue(zip.text(for: "[Content_Types].xml")?.contains("Extension=\"json\"") == true)
    }

    func testTheDigestMatchesTheWebImplementation() throws {
        // FNV-1a 64 over name bytes then content bytes, parts sorted by name, model excluded —
        // `digestParts` in `web/apps/web/src/lib/ooxmlContainer.ts`, restated independently below.
        var zip = ZipArchive()
        zip.set("b.xml", text: "<b/>")
        zip.set("a.xml", text: "<a/>")
        zip.set("neutrino/model.json", text: "ignored")

        XCTAssertEqual(PptxCodec.digest(of: zip), Self.fnv1a(["a.xml", "<a/>", "b.xml", "<b/>"]))
    }

    /// An independent FNV-1a 64, so the digest test is not the implementation checking itself.
    private static func fnv1a(_ chunks: [String]) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for chunk in chunks {
            for byte in chunk.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        }
        return String(hash, radix: 16).leftPadded(to: 16)
    }

    // MARK: - When the model is not trusted

    func testAModelWhosePackageWasEditedElsewhereIsIgnored() throws {
        var zip = try ZipArchive(data: PptxCodec.encode(richDeck()))
        // What PowerPoint keeping the part while rewriting a slide would look like.
        let slide = try XCTUnwrap(zip.text(for: "ppt/slides/slide1.xml"))
        zip.set("ppt/slides/slide1.xml",
                text: slide.replacingOccurrences(of: "Quarterly", with: "Annual"))

        let decoded = try PptxCodec.decode(zip.serialized())

        XCTAssertEqual(decoded.slides.first?.elements.first?.text?.content.hasPrefix("Annual"), true,
                       "the outside edit wins over the stale model")
    }

    func testAnotherEditorsModelIsIgnored() throws {
        var zip = try ZipArchive(data: PptxCodec.encode(richDeck()))
        let raw = try XCTUnwrap(zip.text(for: "neutrino/model.json"))
        zip.set("neutrino/model.json", text: raw.replacingOccurrences(of: "\"slides\"", with: "\"docs\""))

        XCTAssertNil(PptxCodec.model(in: zip))
    }

    func testPackingTwiceReplacesTheModelRatherThanAddingOne() throws {
        var zip = PptxWriter.write(richDeck())
        try PptxCodec.pack(richDeck(), into: &zip)
        try PptxCodec.pack(richDeck(), into: &zip)

        XCTAssertEqual(zip.names.filter { $0 == "neutrino/model.json" }.count, 1)
        XCTAssertEqual(zip.text(for: "[Content_Types].xml")?
            .components(separatedBy: "Extension=\"json\"").count, 2)
        XCTAssertNotNil(PptxCodec.model(in: zip))
    }

    // MARK: - The PresentationML half

    func testThePackageIsAWellFormedPresentation() throws {
        let zip = try ZipArchive(data: PptxCodec.encode(richDeck()))

        XCTAssertEqual(zip.names.first, "[Content_Types].xml", "OPC requires it to come first")
        for name in zip.names where name.hasSuffix(".xml") || name.hasSuffix(".rels") {
            XCTAssertNotNil(XMLElement.parse(try XCTUnwrap(zip.data(for: name))), "\(name) must parse")
        }

        let presentation = try XCTUnwrap(zip.data(for: "ppt/presentation.xml").flatMap(XMLElement.parse))
        XCTAssertEqual(presentation.descendant("sldIdLst")?.elements("sldId").count, 3)

        // Every part a relationship names exists, and every part has a content type.
        let types = try XCTUnwrap(zip.text(for: "[Content_Types].xml"))
        for name in zip.names where name.hasSuffix(".rels") {
            let rels = try XCTUnwrap(zip.data(for: name).flatMap(XMLElement.parse))
            let directory = name.replacingOccurrences(of: "_rels/", with: "")
                .split(separator: "/").dropLast().joined(separator: "/")
            for rel in rels.elements("Relationship") {
                let target = OOXMLPackage.resolve(target: rel.attribute("Target") ?? "", from: directory)
                XCTAssertTrue(zip.contains(target), "\(name) points at missing \(target)")
            }
        }
        for name in zip.names where !name.hasSuffix(".rels") && name != "[Content_Types].xml" {
            let ext = String(name.split(separator: ".").last ?? "")
            XCTAssertTrue(types.contains("PartName=\"/\(name)\"") || types.contains("Extension=\"\(ext)\""),
                          "\(name) has no content type")
        }
    }

    func testOnlyBytesThisAppHoldsAreEmbedded() throws {
        let zip = try ZipArchive(data: PptxCodec.encode(richDeck()))

        // The `data:` picture is embedded; the `neutrino-drive:` one cannot be until this app can
        // fetch it, and rides in the model instead.
        XCTAssertEqual(zip.names.filter { $0.hasPrefix("ppt/media/") }, ["ppt/media/image1.png"])
        XCTAssertEqual(try XCTUnwrap(zip.text(for: "ppt/slides/slide1.xml"))
            .components(separatedBy: "<p:pic>").count - 1, 1)
    }

    func testTextIsEscapedAndCarriesItsFormatting() throws {
        let zip = try ZipArchive(data: PptxCodec.encode(richDeck()))
        let slide = try XCTUnwrap(zip.text(for: "ppt/slides/slide1.xml"))

        XCTAssertTrue(slide.contains("<a:t>Quarterly &lt;review&gt; &amp; plan</a:t>"))
        // 40px is 30pt, which PresentationML stores in hundredths.
        XCTAssertTrue(slide.contains("sz=\"3000\""))
        XCTAssertTrue(slide.contains("b=\"1\" i=\"1\" u=\"sng\" strike=\"sngStrike\""))
        XCTAssertTrue(slide.contains("algn=\"ctr\""))
        XCTAssertTrue(slide.contains("<a:latin typeface=\"Georgia\"/>"))
        // A translucent fill keeps its alpha.
        XCTAssertTrue(slide.contains("<a:srgbClr val=\"10B981\"><a:alpha val=\"50000\"/></a:srgbClr>"))
    }

    // MARK: - Reading a deck with no model

    /// The writer's own output, stripped of the model — what a Neutrino deck looks like after a trip
    /// through PowerPoint.
    private func modelLess(_ deck: SlideDeck) throws -> SlideDeck {
        var zip = PptxWriter.write(deck)
        zip.remove("neutrino/model.json")
        return try PptxCodec.decode(zip.serialized())
    }

    func testWithoutItsModelADeckReadsBackFromItsSlides() throws {
        let read = try modelLess(richDeck())

        XCTAssertEqual(read.slides.count, 3)
        let first = try XCTUnwrap(read.slides.first)
        XCTAssertEqual(first.background, .color("#f8fafc"))
        XCTAssertEqual(first.notes, "Open with the numbers.\nThen the plan & ask.")
        XCTAssertEqual(first.transition, SlideTransition.dissolve.rawValue)

        let text = try XCTUnwrap(first.elements.compactMap(\.text).first)
        XCTAssertEqual(text.content, "Quarterly <review> & plan\nSecond line")
        XCTAssertEqual(text.style.fontSize, 40)
        XCTAssertTrue(text.style.bold && text.style.italic && text.style.underline)
        XCTAssertEqual(text.style.isStrikethrough, true)
        XCTAssertEqual(text.style.color, "#1e40af")
        XCTAssertEqual(text.style.align, "center")
        XCTAssertEqual(text.style.fontFamily, "Georgia")
        XCTAssertEqual(text.style.backgroundColor, "#fef3c7")
        XCTAssertEqual(text.style.listType, "bullet")
        XCTAssertEqual(text.frame.x, 10, accuracy: 0.01)
        XCTAssertEqual(text.frame.w, 80, accuracy: 0.01)

        let shapes = first.elements.compactMap(\.shape)
        XCTAssertEqual(shapes.map(\.shape), ["hexagon", "chevron-l"])
        XCTAssertEqual(shapes.first?.stroke, "#065f46")
        XCTAssertEqual(shapes.first?.strokeWidth, 3)

        let line = try XCTUnwrap(first.elements.compactMap(\.line).first)
        XCTAssertEqual(line.x1, 80, accuracy: 0.01)
        XCTAssertEqual(line.y1, 90, accuracy: 0.01)
        XCTAssertEqual(line.x2, 40, accuracy: 0.01)
        XCTAssertEqual(line.y2, 70, accuracy: 0.01)
        XCTAssertEqual(line.endArrow, "triangle")

        let image = try XCTUnwrap(first.elements.compactMap(\.image).first)
        XCTAssertEqual(image.src, Self.pngDataURL)
        XCTAssertEqual(image.opacity, 0.5, accuracy: 0.001)

        XCTAssertEqual(read.slides[1].transition, SlideTransition.slideLeft.rawValue)
        XCTAssertTrue(read.slides[1].background.isGradient)
        XCTAssertTrue(read.slides[2].background.value.hasPrefix("linear-gradient(90deg"))
    }

    func testAGradientSurvivesTheTripThroughDrawingML() throws {
        let read = try modelLess(SlideDeck(slides: [
            Slide(background: .gradient("linear-gradient(135deg, #667eea 0%, #764ba2 100%)")),
        ]))

        XCTAssertEqual(read.slides.first?.background.value,
                       "linear-gradient(135deg, #667eea 0%, #764ba2 100%)")
    }

    // MARK: - A deck from somewhere else

    func testAForeignDeckIsReadInPresentationOrderWithItsGroupsAndNotes() throws {
        let deck = try XCTUnwrap(PptxReader.read(Self.foreignDeck()))

        // `sldIdLst` names slide2 first. The web reader sorts by file name and would not.
        XCTAssertEqual(deck.slides.count, 2)
        let first = deck.slides[0]
        let text = try XCTUnwrap(first.elements.compactMap(\.text).first)
        XCTAssertEqual(text.content, "Agenda")
        // `tx1` through the colour map to `dk1`, then darkened by half.
        XCTAssertEqual(text.style.color, "#404040")
        XCTAssertEqual(text.style.fontFamily, "Calibri", "the theme's minor font when the run names none")
        XCTAssertEqual(text.style.fontSize, 24, "1800 hundredths of a point is 24px")

        // Notes are found through the slide's relationships, not by matching numbers.
        XCTAssertEqual(first.notes, "Notes for the agenda")
        XCTAssertEqual(deck.slides[1].notes, "")

        // The grouped shape is placed through its group's transform: child space 0…1000 mapped onto
        // the right half of the slide.
        let shape = try XCTUnwrap(first.elements.compactMap(\.shape).first)
        XCTAssertEqual(shape.shape, "circle")
        XCTAssertEqual(shape.fill, "#4472c4")
        XCTAssertEqual(shape.frame.x, 50, accuracy: 0.01)
        XCTAssertEqual(shape.frame.w, 25, accuracy: 0.01)
        XCTAssertEqual(shape.stroke, "transparent", "an outline's colour is not the shape's fill")

        XCTAssertEqual(deck.slides[1].background, .color("#ffffff"))
    }

    func testBytesThatAreNotADeckOpenAsTheDefaultDeck() {
        XCTAssertEqual(SlideDeck.decodePackage(from: Data()).slides.count, 1)
        XCTAssertEqual(SlideDeck.decodePackage(from: Data("not a zip".utf8)).slides.count, 1)
        XCTAssertEqual(SlideDeck.decodePackage(from: Data(repeating: 9, count: 300)).slides.count, 1)
    }

    /// A small deck written the way PowerPoint writes one: slides out of file-name order, a theme
    /// colour through the colour map, a grouped shape, and notes whose number does not match.
    private static func foreignDeck() throws -> ZipArchive {
        let a = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""
        let p = "xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\""
        let r = "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\""
        let rels = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        func relationships(_ entries: [(String, String, String)]) -> String {
            "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
                + entries.map { "<Relationship Id=\"\($0.0)\" Type=\"\(rels)/\($0.1)\" Target=\"\($0.2)\"/>" }
                    .joined()
                + "</Relationships>"
        }

        var zip = ZipArchive()
        zip.set("[Content_Types].xml", text: "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"/>")
        zip.set("ppt/presentation.xml", text: """
            <p:presentation \(a) \(p) \(r)><p:sldIdLst>\
            <p:sldId id="256" r:id="rId3"/><p:sldId id="257" r:id="rId2"/></p:sldIdLst>\
            <p:sldSz cx="12192000" cy="6858000"/></p:presentation>
            """)
        zip.set("ppt/_rels/presentation.xml.rels", text: relationships([
            ("rId2", "slide", "slides/slide1.xml"), ("rId3", "slide", "slides/slide2.xml"),
        ]))
        zip.set("ppt/slides/slide2.xml", text: """
            <p:sld \(a) \(p) \(r)><p:cSld><p:spTree>\
            <p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>\
            <p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="6096000" cy="1000000"/></a:xfrm></p:spPr>\
            <p:txBody><a:bodyPr/><a:p><a:r><a:rPr sz="1800"><a:solidFill><a:schemeClr val="tx1">\
            <a:lumMod val="50000"/></a:schemeClr></a:solidFill></a:rPr><a:t>Agenda</a:t></a:r></a:p></p:txBody></p:sp>\
            <p:grpSp><p:nvGrpSpPr><p:cNvPr id="3" name="Group"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>\
            <p:grpSpPr><a:xfrm><a:off x="6096000" y="0"/><a:ext cx="6096000" cy="6858000"/>\
            <a:chOff x="0" y="0"/><a:chExt cx="1000" cy="1000"/></a:xfrm></p:grpSpPr>\
            <p:sp><p:nvSpPr><p:cNvPr id="4" name="Oval"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>\
            <p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="500" cy="500"/></a:xfrm>\
            <a:prstGeom prst="ellipse"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val="4472C4"/></a:solidFill>\
            <a:ln><a:noFill/></a:ln></p:spPr></p:sp></p:grpSp>\
            </p:spTree></p:cSld></p:sld>
            """)
        zip.set("ppt/slides/_rels/slide2.xml.rels", text: relationships([
            ("rId1", "slideLayout", "../slideLayouts/slideLayout1.xml"),
            ("rId2", "notesSlide", "../notesSlides/notesSlide1.xml"),
        ]))
        zip.set("ppt/slides/slide1.xml", text: """
            <p:sld \(a) \(p) \(r)><p:cSld><p:spTree/></p:cSld></p:sld>
            """)
        zip.set("ppt/slides/_rels/slide1.xml.rels", text: relationships([
            ("rId1", "slideLayout", "../slideLayouts/slideLayout1.xml"),
        ]))
        zip.set("ppt/notesSlides/notesSlide1.xml", text: """
            <p:notes \(a) \(p)><p:cSld><p:spTree>\
            <p:sp><p:nvSpPr><p:cNvPr id="2" name="Slide Image"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr/></p:sp>\
            <p:sp><p:nvSpPr><p:cNvPr id="3" name="Notes"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr/>\
            <p:txBody><a:bodyPr/><a:p><a:r><a:t>Notes for the agenda</a:t></a:r></a:p></p:txBody></p:sp>\
            </p:spTree></p:cSld></p:notes>
            """)
        zip.set("ppt/slideLayouts/slideLayout1.xml", text: "<p:sldLayout \(a) \(p)><p:cSld><p:spTree/></p:cSld></p:sldLayout>")
        zip.set("ppt/slideLayouts/_rels/slideLayout1.xml.rels", text: relationships([
            ("rId1", "slideMaster", "../slideMasters/slideMaster1.xml"),
        ]))
        zip.set("ppt/slideMasters/slideMaster1.xml", text: """
            <p:sldMaster \(a) \(p)><p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg>\
            <p:spTree/></p:cSld></p:sldMaster>
            """)
        zip.set("ppt/slideMasters/_rels/slideMaster1.xml.rels", text: relationships([
            ("rId1", "theme", "../theme/theme1.xml"),
        ]))
        zip.set("ppt/theme/theme1.xml", text: """
            <a:theme \(a) name="Office"><a:themeElements><a:clrScheme name="Office">\
            <a:dk1><a:srgbClr val="808080"/></a:dk1><a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>\
            </a:clrScheme><a:fontScheme name="Office"><a:majorFont><a:latin typeface="Calibri Light"/></a:majorFont>\
            <a:minorFont><a:latin typeface="Calibri"/></a:minorFont></a:fontScheme></a:themeElements></a:theme>
            """)
        return zip
    }

    // MARK: - Names and colours

    func testTheExtensionIsAddedOnceAndStrippedForTheTitle() {
        XCTAssertEqual(PptxCodec.withExtension("Kickoff"), "Kickoff.pptx")
        XCTAssertEqual(PptxCodec.withExtension("Kickoff.pptx"), "Kickoff.pptx")
        XCTAssertEqual(PptxCodec.withExtension("Kickoff.PPTX"), "Kickoff.PPTX")
        XCTAssertEqual(PptxCodec.strippingExtension("Kickoff.pptx"), "Kickoff")
        XCTAssertEqual(PptxCodec.strippingExtension("Kickoff.ppt"), "Kickoff.ppt")
    }

    func testCSSColoursAreReadTheWayTheDeckStoresThem() {
        XCTAssertEqual(CSSPaint.color("#fff"), .init(hex: "FFFFFF", alpha: 1))
        XCTAssertEqual(CSSPaint.color("#1e40af"), .init(hex: "1E40AF", alpha: 1))
        XCTAssertEqual(CSSPaint.color("#00000080")?.hex, "000000")
        XCTAssertEqual(CSSPaint.color("#00000080")?.alpha ?? 0, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(CSSPaint.color("rgb(30 64 175)"), .init(hex: "1E40AF", alpha: 1))
        XCTAssertEqual(CSSPaint.color("rgba(16, 185, 129, 0.5)"), .init(hex: "10B981", alpha: 0.5))
        XCTAssertEqual(CSSPaint.color("steelblue")?.hex, "4682B4")
        XCTAssertNil(CSSPaint.color("transparent"))
        XCTAssertNil(CSSPaint.color("#ggg"))
    }

    func testCSSGradientsAreReadWithTheirAngleAndStops() throws {
        let gradient = try XCTUnwrap(CSSPaint.gradient(
            "linear-gradient(135deg, #0f0c29 0%, rgb(48 43 99) 50%, #24243e 100%)"))
        XCTAssertEqual(gradient.angle, 135)
        XCTAssertEqual(gradient.stops.map(\.color.hex), ["0F0C29", "302B63", "24243E"])
        XCTAssertEqual(gradient.stops.map(\.position), [0, 50, 100])

        let unpositioned = try XCTUnwrap(CSSPaint.gradient("linear-gradient(to right, red, blue, white)"))
        XCTAssertEqual(unpositioned.angle, 90)
        XCTAssertEqual(unpositioned.stops.map(\.position), [0, 50, 100])

        XCTAssertNil(CSSPaint.gradient("#ffffff"))
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        String(repeating: "0", count: max(0, length - count)) + self
    }
}
