import XCTest
import SwiftUI
@testable import NeutrinoSlides

/// Reading the CSS a deck stores.
///
/// The values here are the ones the web app actually writes — its pickers' hex, its preset
/// gradients, the `rgb()` a paste can leave behind — because the point of the parser is to read
/// what the *other* client wrote, not what this one would.
@MainActor
final class CSSColorTests: XCTestCase {

    // MARK: - Colours

    func testSixDigitHexIsRead() throws {
        let color = try XCTUnwrap(CSSColor.uiColor("#4f46e5"))

        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(red, 0x4f / 255, accuracy: 0.01)
        XCTAssertEqual(green, 0x46 / 255, accuracy: 0.01)
        XCTAssertEqual(blue, 0xe5 / 255, accuracy: 0.01)
        XCTAssertEqual(alpha, 1, accuracy: 0.01)
    }

    func testShorthandAndAlphaHexAreRead() throws {
        XCTAssertEqual(CSSColor.uiColor("#fff"), CSSColor.uiColor("#ffffff"))

        let translucent = try XCTUnwrap(CSSColor.uiColor("#00000080"))
        var alpha: CGFloat = 0
        translucent.getRed(nil, green: nil, blue: nil, alpha: &alpha)
        XCTAssertEqual(alpha, 0.5, accuracy: 0.01)
    }

    func testTheEightDigitHexALayoutWritesIsRead() throws {
        // `theme.accentColor + "33"` is what the Comparison layout stores, verbatim from the web
        // app — so it has to parse here or that layout's panels are invisible.
        let color = try XCTUnwrap(CSSColor.uiColor("#818cf833"))

        var alpha: CGFloat = 0
        color.getRed(nil, green: nil, blue: nil, alpha: &alpha)
        XCTAssertEqual(alpha, 0x33 / 255, accuracy: 0.01)
    }

    func testFunctionalAndNamedColoursAreRead() {
        XCTAssertNotNil(CSSColor.uiColor("rgb(30, 64, 175)"))
        XCTAssertNotNil(CSSColor.uiColor("rgb(30 64 175)"))
        XCTAssertNotNil(CSSColor.uiColor("rgba(30, 64, 175, 0.5)"))
        XCTAssertNotNil(CSSColor.uiColor("black"))
    }

    func testAbsentAndUnpaintableValuesReadAsNothing() {
        XCTAssertNil(CSSColor.uiColor(nil))
        XCTAssertNil(CSSColor.uiColor(""))
        XCTAssertNil(CSSColor.uiColor("transparent"))
        XCTAssertNil(CSSColor.uiColor("none"))
        XCTAssertNil(CSSColor.uiColor("#12345"))
        XCTAssertNil(CSSColor.uiColor("chartreuse-ish"))
    }

    func testHexIsWrittenBackInTheFormTheWebAppCanRead() {
        XCTAssertEqual(CSSColor.hex(from: .black), "#000000")
        XCTAssertEqual(CSSColor.hex(from: .white), "#ffffff")
        XCTAssertEqual(CSSColor.hex(from: Color(red: 1, green: 0, blue: 0)), "#ff0000")
    }

    func testAColourRoundTripsThroughHex() throws {
        let color = try XCTUnwrap(CSSColor.color("#4f46e5"))

        XCTAssertEqual(CSSColor.hex(from: color), "#4f46e5")
    }

    // MARK: - Gradients

    func testEveryPresetGradientParses() {
        for preset in SlideGradients.presets {
            XCTAssertTrue(CSSColor.isGradient(preset))
            let gradient = CSSColor.gradient(preset)
            XCTAssertNotNil(gradient, "did not parse: \(preset)")
            XCTAssertGreaterThanOrEqual(gradient?.stops.count ?? 0, 2)
        }
    }

    func testAGradientsAngleAndStopsAreRead() throws {
        let gradient = try XCTUnwrap(
            CSSColor.gradient("linear-gradient(135deg, #667eea 0%, #764ba2 100%)")
        )

        XCTAssertEqual(gradient.angle, 135)
        XCTAssertEqual(gradient.stops.count, 2)
        XCTAssertEqual(gradient.stops[0].location, 0)
        XCTAssertEqual(gradient.stops[1].location, 1)
    }

    func testStopsWithNoPositionAreSpacedEvenly() throws {
        let gradient = try XCTUnwrap(CSSColor.gradient("linear-gradient(#000, #888, #fff)"))

        XCTAssertEqual(gradient.stops.map(\.location), [0, 0.5, 1])
        XCTAssertEqual(gradient.angle, 180, "no direction means top to bottom, as in CSS")
    }

    func testKeywordDirectionsAreRead() throws {
        XCTAssertEqual(try XCTUnwrap(CSSColor.gradient("linear-gradient(to right, #000, #fff)")).angle,
                       90)
        XCTAssertEqual(try XCTUnwrap(CSSColor.gradient("linear-gradient(to top, #000, #fff)")).angle,
                       0)
    }

    func testACommaInsideAColourFunctionDoesNotSplitAStop() throws {
        let gradient = try XCTUnwrap(
            CSSColor.gradient("linear-gradient(90deg, rgb(1, 2, 3) 0%, rgb(4, 5, 6) 100%)")
        )

        XCTAssertEqual(gradient.stops.count, 2)
    }

    func testAGradientThisBuildCannotPaintIsRefusedRatherThanGuessedAt() {
        XCTAssertNil(CSSColor.gradient("radial-gradient(#000, #fff)"))
        XCTAssertNil(CSSColor.gradient("linear-gradient(90deg, #000)"), "one stop is not a gradient")
        XCTAssertNil(CSSColor.gradient("#ffffff"))
        XCTAssertFalse(CSSColor.isGradient("#ffffff"))
    }

    // MARK: - Fonts

    func testAWebFontStackFallsBackToTheSystemFace() {
        let system = CSSColor.font(family: "Inter", size: 20, bold: false, italic: false)
        let missing = CSSColor.font(family: "Not A Font", size: 20, bold: false, italic: false)

        XCTAssertEqual(system.pointSize, 20)
        XCTAssertEqual(missing.pointSize, 20)
    }

    func testBoldAndItalicAreApplied() {
        let plain = CSSColor.font(family: "Inter", size: 20, bold: false, italic: false)
        let italic = CSSColor.font(family: "Inter", size: 20, bold: false, italic: true)

        XCTAssertNotEqual(plain.fontName, italic.fontName)
    }

    func testTheCachesCanBeDroppedWithoutChangingAnAnswer() {
        let before = CSSColor.uiColor("#123456")

        CSSColor.flushCaches()

        XCTAssertEqual(CSSColor.uiColor("#123456"), before)
    }
}
