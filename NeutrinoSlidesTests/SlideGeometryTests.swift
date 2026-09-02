import XCTest
@testable import NeutrinoSlides

/// The arithmetic behind every gesture on the canvas.
///
/// Tested without a view because that is the point of keeping it in ``SlideGeometry``: "a drag of
/// 32 points on a 320-point canvas moves the element 10%" is a question about numbers, and the
/// numbers are what a gesture gets wrong.
final class SlideGeometryTests: XCTestCase {

    private let canvas = CGSize(width: 320, height: 180)

    // MARK: - Canvas

    func testTheCanvasIsAlwaysSixteenByNine() {
        let wide = SlideGeometry.canvasSize(fitting: CGSize(width: 1000, height: 200))
        XCTAssertEqual(wide.width / wide.height, SlideGeometry.aspectRatio, accuracy: 0.001)
        XCTAssertLessThanOrEqual(wide.height, 200)

        let tall = SlideGeometry.canvasSize(fitting: CGSize(width: 320, height: 800))
        XCTAssertEqual(tall.width, 320, accuracy: 0.001)
        XCTAssertEqual(tall.height, 180, accuracy: 0.001)
    }

    func testAnEmptyAreaHasNoCanvas() {
        XCTAssertEqual(SlideGeometry.canvasSize(fitting: .zero), .zero)
    }

    // MARK: - Conversion

    func testPointsConvertToCanvasPercent() {
        let delta = SlideGeometry.percentDelta(CGSize(width: 32, height: 18), in: canvas)

        XCTAssertEqual(delta.dx, 10, accuracy: 0.001)
        XCTAssertEqual(delta.dy, 10, accuracy: 0.001)
    }

    func testFontSizesScaleWithTheCanvas() {
        // The web app lays out on a 960-point canvas; a third of that is a third of the type.
        XCTAssertEqual(SlideGeometry.fontSize(40, canvasWidth: 320), 40 / 3, accuracy: 0.001)
        XCTAssertEqual(SlideGeometry.fontSize(40, canvasWidth: 960), 40, accuracy: 0.001)
    }

    func testStrokesNeverVanishOnAThumbnail() {
        XCTAssertEqual(SlideGeometry.strokeWidth(0, canvasWidth: 100), 0)
        XCTAssertGreaterThanOrEqual(SlideGeometry.strokeWidth(1, canvasWidth: 100), 0.5)
    }

    // MARK: - Snapping

    func testSnapRoundsToTheNearestStep() {
        XCTAssertEqual(SlideGeometry.snap(12.4, step: 5), 10)
        XCTAssertEqual(SlideGeometry.snap(12.6, step: 5), 15)
        XCTAssertEqual(SlideGeometry.snap(12.6, step: 0), 12.6, "a zero step snaps nothing")
    }

    // MARK: - Dragging

    func testDraggingMovesTheBoxAndKeepsItsSize() {
        let frame = SlideFrame(x: 10, y: 10, w: 20, h: 20)

        let moved = SlideGeometry.drag(frame, by: CGSize(width: 32, height: 18), in: canvas,
                                       snapStep: 0)

        XCTAssertEqual(moved.x, 20, accuracy: 0.001)
        XCTAssertEqual(moved.y, 20, accuracy: 0.001)
        XCTAssertEqual(moved.w, 20, accuracy: 0.001)
        XCTAssertEqual(moved.h, 20, accuracy: 0.001)
    }

    func testDraggingSnapsThePositionButNotTheSize() {
        let frame = SlideFrame(x: 10, y: 10, w: 21, h: 21)

        let moved = SlideGeometry.drag(frame, by: CGSize(width: 5, height: 5), in: canvas,
                                       snapStep: 5)

        XCTAssertEqual(moved.x.truncatingRemainder(dividingBy: 5), 0, accuracy: 0.001)
        XCTAssertEqual(moved.w, 21, accuracy: 0.001, "a drag must never resize")
    }

    func testDraggingStopsAtTheEdgeOfTheSlide() {
        let frame = SlideFrame(x: 80, y: 80, w: 20, h: 20)

        let moved = SlideGeometry.drag(frame, by: CGSize(width: 1000, height: 1000), in: canvas,
                                       snapStep: 0)

        XCTAssertEqual(moved.x, 80, accuracy: 0.001)
        XCTAssertEqual(moved.y, 80, accuracy: 0.001)
    }

    func testAnOversizedElementIsNotShrunkByClamping() {
        // A full-bleed shape drawn slightly oversize is legitimate; opening the deck must not
        // silently rewrite it.
        let frame = SlideFrame(x: -5, y: -5, w: 110, h: 110)

        XCTAssertEqual(frame.clampedToCanvas().w, 110, accuracy: 0.001)
        XCTAssertEqual(frame.clampedToCanvas().h, 110, accuracy: 0.001)
    }

    // MARK: - Resizing

    func testACornerHandleMovesTwoEdgesAndLeavesTheOppositeCorner() {
        let frame = SlideFrame(x: 20, y: 20, w: 40, h: 40)

        let resized = SlideGeometry.resize(frame, handle: .topLeft,
                                           by: CGSize(width: 32, height: 18), in: canvas,
                                           snapStep: 0)

        XCTAssertEqual(resized.x, 30, accuracy: 0.001)
        XCTAssertEqual(resized.y, 30, accuracy: 0.001)
        XCTAssertEqual(resized.maxX, 60, accuracy: 0.001, "the far edge must not move")
        XCTAssertEqual(resized.maxY, 60, accuracy: 0.001)
    }

    func testASideHandleMovesOneEdgeOnly() {
        let frame = SlideFrame(x: 20, y: 20, w: 40, h: 40)

        let resized = SlideGeometry.resize(frame, handle: .right,
                                           by: CGSize(width: 32, height: 18), in: canvas,
                                           snapStep: 0)

        XCTAssertEqual(resized.x, 20, accuracy: 0.001)
        XCTAssertEqual(resized.y, 20, accuracy: 0.001)
        XCTAssertEqual(resized.h, 40, accuracy: 0.001)
        XCTAssertEqual(resized.w, 50, accuracy: 0.001)
    }

    func testAHandleDraggedPastTheOppositeEdgeStopsAtTheMinimumSize() {
        let frame = SlideFrame(x: 20, y: 20, w: 40, h: 40)

        let resized = SlideGeometry.resize(frame, handle: .topLeft,
                                           by: CGSize(width: 1000, height: 1000), in: canvas,
                                           snapStep: 0)

        XCTAssertEqual(resized.w, SlideFrame.minimumSize, accuracy: 0.001)
        XCTAssertEqual(resized.h, SlideFrame.minimumSize, accuracy: 0.001)
        XCTAssertEqual(resized.maxX, 60, accuracy: 0.001, "the fixed corner stays fixed")
        XCTAssertEqual(resized.maxY, 60, accuracy: 0.001)
    }

    func testResizingSnapsTheDraggedEdgeAndNotTheOtherOne() {
        let frame = SlideFrame(x: 21, y: 20, w: 40, h: 40)

        let resized = SlideGeometry.resize(frame, handle: .right,
                                           by: CGSize(width: 10, height: 0), in: canvas,
                                           snapStep: 5)

        XCTAssertEqual(resized.x, 21, accuracy: 0.001, "the untouched edge keeps its position")
        XCTAssertEqual(resized.maxX.truncatingRemainder(dividingBy: 5), 0, accuracy: 0.001)
    }

    // MARK: - Hit testing

    func testTheTopmostElementWins() {
        let below = Fixture.shapeElement(id: "below", frame: SlideFrame(x: 0, y: 0, w: 50, h: 50))
        let above = Fixture.shapeElement(id: "above", frame: SlideFrame(x: 10, y: 10, w: 50, h: 50))

        let hit = SlideGeometry.element(at: CGPoint(x: 20, y: 20), in: [below, above])

        XCTAssertEqual(hit?.id, "above")
    }

    func testATapOnEmptyCanvasHitsNothing() {
        let element = Fixture.shapeElement(frame: SlideFrame(x: 0, y: 0, w: 10, h: 10))

        XCTAssertNil(SlideGeometry.element(at: CGPoint(x: 90, y: 90), in: [element]))
    }

    func testAnElementWithNoBoxIsNeverHit() {
        let element = SlideElement.opaque(OpaqueElement(["id": .string("x"),
                                                         "type": .string("mystery")]))

        XCTAssertNil(SlideGeometry.element(at: CGPoint(x: 50, y: 50), in: [element]))
    }

    // MARK: - Guides

    func testCentringAnElementProducesBothCentreGuides() {
        let frame = SlideFrame(x: 40, y: 45, w: 20, h: 10)

        let guides = SlideGeometry.guides(for: frame, others: [])

        XCTAssertEqual(guides.vertical, [50])
        XCTAssertEqual(guides.horizontal, [50])
    }

    func testAligningWithAnotherElementProducesAGuideAtItsEdge() {
        let other = SlideFrame(x: 10, y: 70, w: 20, h: 10)
        let frame = SlideFrame(x: 10, y: 20, w: 30, h: 10)

        let guides = SlideGeometry.guides(for: frame, others: [other])

        XCTAssertTrue(guides.vertical.contains(10))
    }

    func testNothingAlignedProducesNoGuides() {
        let guides = SlideGeometry.guides(for: SlideFrame(x: 3, y: 7, w: 11, h: 13), others: [])

        XCTAssertTrue(guides.isEmpty)
    }

    // MARK: - Placement

    func testANewElementLandsInTheMiddleAndThenBesideItself() {
        let first = SlideGeometry.placement(size: SlideFrame(x: 0, y: 0, w: 50, h: 20),
                                            existingCount: 0)
        XCTAssertEqual(first.x, 25, accuracy: 0.001)
        XCTAssertEqual(first.y, 40, accuracy: 0.001)

        let second = SlideGeometry.placement(size: SlideFrame(x: 0, y: 0, w: 50, h: 20),
                                             existingCount: 1)
        XCTAssertNotEqual(second.x, first.x, "a second element must not hide under the first")
    }

    func testPlacementNeverLeavesTheSlide() {
        for count in 0..<12 {
            let frame = SlideGeometry.placement(size: SlideFrame(x: 0, y: 0, w: 50, h: 20),
                                                existingCount: count)
            XCTAssertGreaterThanOrEqual(frame.minX, 0)
            XCTAssertLessThanOrEqual(frame.maxX, 100.001)
            XCTAssertGreaterThanOrEqual(frame.minY, 0)
            XCTAssertLessThanOrEqual(frame.maxY, 100.001)
        }
    }

    // MARK: - Rects

    func testAFrameBecomesPointsInsideACanvas() {
        let rect = SlideFrame(x: 25, y: 50, w: 50, h: 25).rect(in: canvas)

        XCTAssertEqual(rect.minX, 80, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 90, accuracy: 0.001)
        XCTAssertEqual(rect.width, 160, accuracy: 0.001)
        XCTAssertEqual(rect.height, 45, accuracy: 0.001)
    }
}
