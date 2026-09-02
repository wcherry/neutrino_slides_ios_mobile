import XCTest
@testable import NeutrinoSlides

/// The shape catalog and the path parser under it.
///
/// The parser is a subset by design, so the test that matters most is the sweep: *every* entry in
/// the catalog has to parse, because an entry that does not silently draws as a rectangle and
/// nothing anywhere reports it.
final class ShapeCatalogTests: XCTestCase {

    private let box = CGRect(x: 0, y: 0, width: 100, height: 100)

    // MARK: - Catalog

    func testEveryCatalogEntryParsesIntoAPath() {
        for entry in ShapeCatalog.entries {
            let path = SVGPath.parse(entry.path)
            XCTAssertNotNil(path, "\(entry.key) did not parse")
        }
    }

    func testEveryShapeDrawsInsideItsBox() {
        for entry in ShapeCatalog.entries {
            let path = ShapeCatalog.cgPath(for: entry.key, in: CGRect(x: 10, y: 20,
                                                                     width: 40, height: 30))
            // `boundingBoxOfPath`, not `boundingBox`: the latter includes off-curve control
            // points, which for the callouts sit well outside the shape they bend.
            let bounds = path.boundingBoxOfPath
            // A couple of the catalog's own outlines poke a hair outside the 100×100 box (the
            // cloud callout does), so the assertion is "in the right place at the right size",
            // not "to the pixel".
            XCTAssertEqual(bounds.midX, 30, accuracy: 3, "\(entry.key) is off-centre")
            XCTAssertEqual(bounds.midY, 35, accuracy: 3, "\(entry.key) is off-centre")
            XCTAssertLessThanOrEqual(bounds.width, 44, "\(entry.key) is too wide")
            XCTAssertLessThanOrEqual(bounds.height, 34, "\(entry.key) is too tall")
        }
    }

    func testKeysAreUniqueAndGroupedAsTheWebAppGroupsThem() {
        let keys = ShapeCatalog.entries.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count)

        XCTAssertFalse(ShapeCatalog.entries(in: .general).isEmpty)
        XCTAssertFalse(ShapeCatalog.entries(in: .arrows).isEmpty)
        XCTAssertFalse(ShapeCatalog.entries(in: .callouts).isEmpty)
        XCTAssertEqual(
            ShapeCatalog.Group.allCases.map { ShapeCatalog.entries(in: $0).count }.reduce(0, +),
            ShapeCatalog.entries.count
        )
    }

    func testAnUnknownShapeDrawsAsARectangleRatherThanNothing() {
        let path = ShapeCatalog.cgPath(for: "not-a-shape", in: box)

        XCTAssertFalse(path.isEmpty)
        XCTAssertEqual(path.boundingBoxOfPath, box)
        XCTAssertEqual(ShapeCatalog.label(for: "not-a-shape"), "Shape")
    }

    func testTheDefaultShapeIsInTheCatalog() {
        XCTAssertNotNil(ShapeCatalog.entry(for: ShapeCatalog.defaultKey))
    }

    // MARK: - Scaling

    func testAShapeIsStretchedIntoItsBoxRatherThanKeptSquare() {
        let path = ShapeCatalog.cgPath(for: "circle", in: CGRect(x: 0, y: 0, width: 200, height: 50))

        XCTAssertEqual(path.boundingBoxOfPath.width, 200, accuracy: 1)
        XCTAssertEqual(path.boundingBoxOfPath.height, 50, accuracy: 1)
    }

    // MARK: - Parser

    func testAbsoluteCommandsBuildTheExpectedOutline() throws {
        let path = try XCTUnwrap(SVGPath.parse("M 10,10 H 90 V 90 H 10 Z"))

        XCTAssertEqual(path.boundingBoxOfPath, CGRect(x: 10, y: 10, width: 80, height: 80))
    }

    func testRelativeCommandsAreSupported() throws {
        let path = try XCTUnwrap(SVGPath.parse("m 10,10 l 40,0 l 0,40 z"))

        XCTAssertEqual(path.boundingBoxOfPath, CGRect(x: 10, y: 10, width: 40, height: 40))
    }

    func testASecondCoordinatePairAfterAMoveIsALine() throws {
        // Per the SVG spec — and the reason a shape drawn `M 0,0 10,10` is a line, not two moves.
        let path = try XCTUnwrap(SVGPath.parse("M 0,0 50,50"))

        XCTAssertEqual(path.boundingBoxOfPath, CGRect(x: 0, y: 0, width: 50, height: 50))
    }

    func testCurvesAreParsed() throws {
        XCTAssertNotNil(SVGPath.parse("M 0,0 C 20,0 40,20 40,40 Z"))
        XCTAssertNotNil(SVGPath.parse("M 0,0 Q 20,0 40,40 Z"))
    }

    func testAnUnsupportedCommandIsRefusedRatherThanGuessedAt() {
        // An elliptical arc. The catalog contains none, and a partial parse would draw an outline
        // that is subtly not the shape the user picked.
        XCTAssertNil(SVGPath.parse("M 0,0 A 10,10 0 0 1 20,20 Z"))
    }

    func testEmptyOrMalformedDataParsesToNothing() {
        XCTAssertNil(SVGPath.parse(""))
        XCTAssertNil(SVGPath.parse("L 10,10"), "a path has to start with a move")
        XCTAssertNil(SVGPath.parse("M"))
    }
}
