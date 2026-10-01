import XCTest
@testable import NeutrinoSlides

/// What the presenter tells the external display, and what the display is told to show.
@MainActor
final class ExternalDisplayServiceTests: XCTestCase {

    private func deck(slides count: Int) -> SlideDeck {
        SlideDeck(slides: (0..<count).map { Slide(id: "s\($0)") })
    }

    func testStartsIdleAndDisconnected() {
        let service = ExternalDisplayService()
        XCTAssertFalse(service.isConnected)
        XCTAssertNil(service.deck)
    }

    func testConnectionFollowsTheScene() {
        let service = ExternalDisplayService()
        service.displayDidConnect()
        XCTAssertTrue(service.isConnected)
        service.displayDidDisconnect()
        XCTAssertFalse(service.isConnected)
    }

    func testBeginShowsTheStartSlide() {
        let service = ExternalDisplayService()
        service.begin(deck: deck(slides: 3), at: 2)
        XCTAssertEqual(service.deck?.slides.count, 3)
        XCTAssertEqual(service.index, 2)
    }

    func testBeginClampsAnOutOfRangeStartToTheFirstSlide() {
        let service = ExternalDisplayService()
        service.begin(deck: deck(slides: 2), at: 9)
        XCTAssertEqual(service.index, 0)
    }

    func testEachBeginIsANewSession() {
        let service = ExternalDisplayService()
        service.begin(deck: deck(slides: 2), at: 0)
        let first = service.sessionID
        service.begin(deck: deck(slides: 2), at: 0)
        XCTAssertNotEqual(service.sessionID, first)
    }

    func testShowRecordsDirection() {
        let service = ExternalDisplayService()
        service.begin(deck: deck(slides: 3), at: 1)

        service.show(index: 2)
        XCTAssertEqual(service.index, 2)
        XCTAssertTrue(service.isAdvancing)

        service.show(index: 0)
        XCTAssertEqual(service.index, 0)
        XCTAssertFalse(service.isAdvancing)
    }

    func testShowIgnoresSlidesThatDoNotExist() {
        let service = ExternalDisplayService()
        service.begin(deck: deck(slides: 2), at: 1)
        service.show(index: 5)
        service.show(index: -1)
        XCTAssertEqual(service.index, 1)
    }

    func testShowIsIgnoredOutsideAPresentation() {
        let service = ExternalDisplayService()
        service.show(index: 1)
        XCTAssertEqual(service.index, 0)
        XCTAssertNil(service.deck)
    }

    func testEndReturnsToStandbyButKeepsTheConnection() {
        let service = ExternalDisplayService()
        service.displayDidConnect()
        service.begin(deck: deck(slides: 2), at: 1)
        service.end()
        XCTAssertNil(service.deck)
        XCTAssertTrue(service.isConnected)
    }
}
