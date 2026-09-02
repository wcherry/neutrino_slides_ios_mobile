import XCTest
@testable import NeutrinoSlides

/// What an element is, and what moving one does to it.
final class SlideElementTests: XCTestCase {

    // MARK: - Identity

    func testKindMatchesTheStoredType() {
        XCTAssertEqual(Fixture.textElement().kind, "text")
        XCTAssertEqual(Fixture.shapeElement().kind, "shape")
        XCTAssertEqual(Fixture.opaqueElement(kind: "video").kind, "video")
    }

    func testWithNewIDChangesOnlyTheID() {
        let original = Fixture.textElement(id: "t1", content: "Hello")

        let copy = original.withNewID("t2")

        XCTAssertEqual(copy.id, "t2")
        XCTAssertEqual(copy.text?.content, "Hello")
        XCTAssertEqual(copy.frame, original.frame)
    }

    func testAnUnmodelledElementKeepsItsPayloadWhenDuplicated() throws {
        let element = Fixture.opaqueElement(id: "o1")

        guard case .opaque(let copy) = element.withNewID("o2") else {
            return XCTFail("expected an opaque element")
        }

        XCTAssertEqual(copy.id, "o2")
        XCTAssertEqual(copy.values["spreadsheetId"]?.stringValue, "sheet-9")
        XCTAssertEqual(copy.values["cachedData"]?.stringValue, "[[1,2],[3,4]]")
    }

    // MARK: - Geometry

    func testMovingABoxKeepsItsSize() {
        let element = Fixture.shapeElement(frame: SlideFrame(x: 10, y: 10, w: 20, h: 30))

        let moved = element.withFrame(SlideFrame(x: 40, y: 50, w: 20, h: 30))

        XCTAssertEqual(moved.frame, SlideFrame(x: 40, y: 50, w: 20, h: 30))
    }

    func testALinesFrameIsTheBoundingBoxOfItsEndpoints() {
        let line = LineElement(x1: 80, y1: 10, x2: 20, y2: 60)

        XCTAssertEqual(line.frame, SlideFrame(x: 20, y: 10, w: 60, h: 50))
    }

    func testResizingALineKeepsWhichCornerEachEndpointSitsIn() {
        // Runs bottom-left to top-right; after a resize it still must.
        var line = LineElement(x1: 10, y1: 60, x2: 50, y2: 20)

        line.setFrame(SlideFrame(x: 0, y: 0, w: 100, h: 100))

        XCTAssertEqual(line.x1, 0, accuracy: 0.001)
        XCTAssertEqual(line.y1, 100, accuracy: 0.001)
        XCTAssertEqual(line.x2, 100, accuracy: 0.001)
        XCTAssertEqual(line.y2, 0, accuracy: 0.001)
    }

    func testResizingAHorizontalLineDoesNotDivideByZero() {
        var line = LineElement(x1: 10, y1: 50, x2: 90, y2: 50)

        line.setFrame(SlideFrame(x: 20, y: 30, w: 40, h: 0))

        XCTAssertEqual(line.y1, 30, accuracy: 0.001)
        XCTAssertEqual(line.y2, 30, accuracy: 0.001)
        XCTAssertEqual(line.x1, 20, accuracy: 0.001)
        XCTAssertEqual(line.x2, 60, accuracy: 0.001)
    }

    func testAnUnmodelledElementCanBeMovedButNothingElseAboutItChanges() throws {
        let element = Fixture.opaqueElement(frame: SlideFrame(x: 5, y: 5, w: 30, h: 30))

        guard case .opaque(let moved) = element.withFrame(SlideFrame(x: 40, y: 45, w: 30, h: 30))
        else { return XCTFail("expected an opaque element") }

        XCTAssertEqual(moved.frame, SlideFrame(x: 40, y: 45, w: 30, h: 30))
        XCTAssertEqual(moved.values["spreadsheetId"]?.stringValue, "sheet-9")
        XCTAssertEqual(moved.kind, "sheetEmbed")
    }

    func testAnUnmodelledElementWithNoBoxHasNoFrameAndIsLeftAlone() throws {
        let element = SlideElement.opaque(OpaqueElement([
            "id": .string("x"), "type": .string("mystery"), "payload": .string("keep me"),
        ]))

        XCTAssertNil(element.frame)

        guard case .opaque(let after) = element.withFrame(SlideFrame(x: 1, y: 2, w: 3, h: 4)) else {
            return XCTFail("expected an opaque element")
        }
        XCTAssertNil(after.frame)
        XCTAssertEqual(after.values["payload"]?.stringValue, "keep me")
    }

    // MARK: - Slides

    func testTheTitleIsTheLargestTextOnTheSlide() {
        let slide = Fixture.slide(elements: [
            Fixture.textElement(id: "body", content: "Body", style: TextStyle(fontSize: 18)),
            Fixture.textElement(id: "title", content: "Title", style: TextStyle(fontSize: 44)),
        ])

        XCTAssertEqual(slide.title, "Title")
    }

    func testASlideWithNoTextHasNoTitle() {
        XCTAssertNil(Fixture.slide(elements: [Fixture.shapeElement()]).title)
        XCTAssertNil(Fixture.slide(elements: [
            Fixture.textElement(content: "   \n  "),
        ]).title)
    }

    func testPlainTextFlattensEveryTextBoxAndTheNotes() {
        let slide = Fixture.slide(elements: [
            Fixture.textElement(id: "a", content: "First   line"),
            Fixture.shapeElement(),
            Fixture.textElement(id: "b", content: "Second\nline"),
        ], notes: "And the notes")

        XCTAssertEqual(slide.plainText, "First line Second line And the notes")
    }

    func testDuplicatingASlideReIdentifiesItsElementsToo() {
        let slide = Fixture.slide(id: "sl1", elements: [
            Fixture.textElement(id: "t1"),
            Fixture.shapeElement(id: "s1"),
        ])

        let copy = slide.duplicated()

        XCTAssertNotEqual(copy.id, slide.id)
        XCTAssertEqual(copy.elements.count, 2)
        XCTAssertNotEqual(copy.elements[0].id, "t1")
        XCTAssertNotEqual(copy.elements[1].id, "s1")
        XCTAssertEqual(Set(copy.elements.map(\.id)).count, 2, "the copies must not collide either")
        XCTAssertEqual(copy.elements[0].text?.content, slide.elements[0].text?.content)
    }

    // MARK: - Ids

    func testGeneratedIdsLookLikeTheWebApps() {
        let id = SlideID.make()

        XCTAssertEqual(id.count, 8)
        XCTAssertTrue(id.allSatisfy { $0.isNumber || ($0.isLowercase && $0.isLetter) },
                      "expected base-36, got \(id)")
    }
}
