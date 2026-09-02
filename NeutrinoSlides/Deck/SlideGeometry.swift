import CoreGraphics
import Foundation

// MARK: - SlideFrame

/// Where an element sits on a slide, in **canvas percent**: `x` and `w` are percentages of the
/// canvas width, `y` and `h` of its height.
///
/// Percent rather than points because that is what the format stores, and the format stores it
/// because a deck is drawn at a different size on every surface it appears on — a phone canvas, an
/// iPad canvas, a 40-point thumbnail, a projector. A layout expressed in points would be a layout
/// that is only correct at one of them.
struct SlideFrame: Hashable {

    var x: Double
    var y: Double
    var w: Double
    var h: Double

    init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    // MARK: - Edges

    var minX: Double { x }
    var minY: Double { y }
    var maxX: Double { x + w }
    var maxY: Double { y + h }
    var midX: Double { x + w / 2 }
    var midY: Double { y + h / 2 }

    // MARK: - Limits

    /// The smallest an element may be dragged down to, in percent. Below this a shape is a few
    /// points across on a phone and there is nothing left to grab to make it bigger again.
    static let minimumSize: Double = 2

    /// Moves the frame by a delta in percent.
    func offset(by dx: Double, _ dy: Double) -> SlideFrame {
        SlideFrame(x: x + dx, y: y + dy, w: w, h: h)
    }

    /// Keeps the box inside the canvas without changing its size.
    ///
    /// Position is clamped, size is not: an element wider than the canvas is something the web app
    /// can legitimately hold (a full-bleed background shape drawn slightly oversize), and shrinking
    /// it here would silently rewrite a deck on open.
    func clampedToCanvas() -> SlideFrame {
        SlideFrame(x: x.clamped(to: min(0, 100 - w)...max(0, 100 - w)),
                   y: y.clamped(to: min(0, 100 - h)...max(0, 100 - h)),
                   w: w, h: h)
    }

    /// Rounds the box to `step` percent, for the snap grid. `step <= 0` snaps nothing.
    func snapped(to step: Double) -> SlideFrame {
        guard step > 0 else { return self }
        return SlideFrame(x: SlideGeometry.snap(x, step: step), y: SlideGeometry.snap(y, step: step),
                          w: SlideGeometry.snap(w, step: step), h: SlideGeometry.snap(h, step: step))
    }

    /// Rounds the *position* only — what a drag needs, since a drag must not resize.
    func snappedOrigin(to step: Double) -> SlideFrame {
        guard step > 0 else { return self }
        return SlideFrame(x: SlideGeometry.snap(x, step: step), y: SlideGeometry.snap(y, step: step),
                          w: w, h: h)
    }

    /// The frame in points, within a canvas of `size`.
    func rect(in size: CGSize) -> CGRect {
        CGRect(x: CGFloat(x / 100) * size.width,
               y: CGFloat(y / 100) * size.height,
               width: CGFloat(w / 100) * size.width,
               height: CGFloat(h / 100) * size.height)
    }
}

// MARK: - ResizeHandle

/// One of the eight handles around a selected element, in the order the web app lists them
/// (`RESIZE_HANDLES` in `slideEditorConstants.ts`).
enum ResizeHandle: String, CaseIterable, Identifiable {
    case topLeft = "nw", top = "n", topRight = "ne", right = "e"
    case bottomRight = "se", bottom = "s", bottomLeft = "sw", left = "w"

    var id: String { rawValue }

    /// The handle's position within the element, 0…1 on each axis.
    var anchor: CGPoint {
        switch self {
        case .topLeft:     return CGPoint(x: 0,   y: 0)
        case .top:         return CGPoint(x: 0.5, y: 0)
        case .topRight:    return CGPoint(x: 1,   y: 0)
        case .right:       return CGPoint(x: 1,   y: 0.5)
        case .bottomRight: return CGPoint(x: 1,   y: 1)
        case .bottom:      return CGPoint(x: 0.5, y: 1)
        case .bottomLeft:  return CGPoint(x: 0,   y: 1)
        case .left:        return CGPoint(x: 0,   y: 0.5)
        }
    }

    var movesLeftEdge: Bool   { anchor.x == 0 }
    var movesRightEdge: Bool  { anchor.x == 1 }
    var movesTopEdge: Bool    { anchor.y == 0 }
    var movesBottomEdge: Bool { anchor.y == 1 }

    var accessibilityLabel: String {
        switch self {
        case .topLeft:     return "Resize from top left"
        case .top:         return "Resize from top"
        case .topRight:    return "Resize from top right"
        case .right:       return "Resize from right"
        case .bottomRight: return "Resize from bottom right"
        case .bottom:      return "Resize from bottom"
        case .bottomLeft:  return "Resize from bottom left"
        case .left:        return "Resize from left"
        }
    }
}

// MARK: - SlideGeometry

/// The canvas, and the arithmetic every surface that draws or edits a slide shares.
///
/// Pure functions on plain numbers, kept out of the views so a drag can be tested without a
/// gesture: "does dragging 10 points right on a 320-point canvas move the element 3.125%?" is a
/// question about arithmetic, and it is the arithmetic that is easy to get wrong.
enum SlideGeometry {

    // MARK: - Canvas

    /// A slide is 16:9 everywhere: the web canvas, the thumbnails, the PPTX export, and presenter
    /// mode. It is not configurable, and the format has no field for it.
    static let aspectRatio: CGFloat = 16.0 / 9.0

    /// The largest 16:9 rectangle that fits `available`.
    ///
    /// A slide is letterboxed rather than cropped or stretched. Cropping loses the edges of a
    /// full-bleed background, and stretching would show the presenter something other than what the
    /// projector will.
    static func canvasSize(fitting available: CGSize) -> CGSize {
        guard available.width > 0, available.height > 0 else { return .zero }
        let width = min(available.width, available.height * aspectRatio)
        return CGSize(width: width, height: width / aspectRatio)
    }

    // MARK: - Conversion

    /// A delta in points as a delta in canvas percent.
    static func percentDelta(_ translation: CGSize, in canvas: CGSize) -> (dx: Double, dy: Double) {
        guard canvas.width > 0, canvas.height > 0 else { return (0, 0) }
        return (Double(translation.width / canvas.width) * 100,
                Double(translation.height / canvas.height) * 100)
    }

    /// A point in the canvas as a position in canvas percent.
    static func percentPoint(_ point: CGPoint, in canvas: CGSize) -> CGPoint {
        guard canvas.width > 0, canvas.height > 0 else { return .zero }
        return CGPoint(x: point.x / canvas.width * 100, y: point.y / canvas.height * 100)
    }

    /// A font size stored in points, scaled for a canvas of `width`.
    ///
    /// The web app lays a deck out on a 960-point-wide canvas and stores type sizes against it, so
    /// a 40-point title is 40 points *there*. Drawing it at 40 points on a 320-point phone canvas
    /// would make it three times too big for the box it was written into.
    static let referenceCanvasWidth: CGFloat = 960

    static func fontSize(_ stored: Double, canvasWidth: CGFloat) -> CGFloat {
        guard canvasWidth > 0 else { return CGFloat(stored) }
        return CGFloat(stored) * canvasWidth / referenceCanvasWidth
    }

    /// A stroke width scaled the same way, floored at a hairline so a 1-point rule on a thumbnail
    /// does not vanish entirely.
    static func strokeWidth(_ stored: Double, canvasWidth: CGFloat) -> CGFloat {
        guard stored > 0 else { return 0 }
        return max(0.5, CGFloat(stored) * canvasWidth / referenceCanvasWidth)
    }

    // MARK: - Snapping

    /// Rounds `value` to the nearest multiple of `step`.
    static func snap(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }

    // MARK: - Dragging

    /// The frame an element ends a drag at.
    static func drag(_ frame: SlideFrame, by translation: CGSize, in canvas: CGSize,
                     snapStep: Double) -> SlideFrame {
        let delta = percentDelta(translation, in: canvas)
        return frame.offset(by: delta.dx, delta.dy)
            .snappedOrigin(to: snapStep)
            .clampedToCanvas()
    }

    // MARK: - Resizing

    /// The frame an element ends a resize at.
    ///
    /// The two rules that make this feel right on a touch screen, rather than merely correct:
    ///
    /// - **Only the dragged edges move.** A corner handle moves two, a side handle one; the
    ///   opposite edge stays exactly where it was, so an element being made wider does not creep
    ///   sideways.
    /// - **The minimum is enforced against the *fixed* edge**, not by clamping the size afterwards.
    ///   Clamping the size alone lets a top-left handle dragged past the bottom-right corner flip
    ///   the element inside out and then snap it back at the wrong position.
    static func resize(_ frame: SlideFrame, handle: ResizeHandle, by translation: CGSize,
                       in canvas: CGSize, snapStep: Double) -> SlideFrame {
        let delta = percentDelta(translation, in: canvas)
        var minX = frame.minX, maxX = frame.maxX
        var minY = frame.minY, maxY = frame.maxY

        if handle.movesLeftEdge   { minX = min(frame.minX + delta.dx, maxX - SlideFrame.minimumSize) }
        if handle.movesRightEdge  { maxX = max(frame.maxX + delta.dx, minX + SlideFrame.minimumSize) }
        if handle.movesTopEdge    { minY = min(frame.minY + delta.dy, maxY - SlideFrame.minimumSize) }
        if handle.movesBottomEdge { maxY = max(frame.maxY + delta.dy, minY + SlideFrame.minimumSize) }

        if snapStep > 0 {
            // The *edges* are snapped, not the origin and the size. Snapping a size would let a
            // dragged edge land off the grid whenever the opposite one already was.
            if handle.movesLeftEdge   { minX = min(snap(minX, step: snapStep), maxX - SlideFrame.minimumSize) }
            if handle.movesRightEdge  { maxX = max(snap(maxX, step: snapStep), minX + SlideFrame.minimumSize) }
            if handle.movesTopEdge    { minY = min(snap(minY, step: snapStep), maxY - SlideFrame.minimumSize) }
            if handle.movesBottomEdge { maxY = max(snap(maxY, step: snapStep), minY + SlideFrame.minimumSize) }
        }

        return SlideFrame(x: minX, y: minY, w: maxX - minX, h: maxY - minY)
    }

    // MARK: - Hit testing

    /// The topmost element at `point` (in canvas percent), or nil for a tap on the background.
    ///
    /// Last first, because later elements are drawn over earlier ones: tapping where two overlap
    /// has to select the one the user can see.
    static func element(at point: CGPoint, in elements: [SlideElement]) -> SlideElement? {
        for element in elements.reversed() {
            guard let frame = element.frame else { continue }
            if point.x >= frame.minX, point.x <= frame.maxX,
               point.y >= frame.minY, point.y <= frame.maxY {
                return element
            }
        }
        return nil
    }

    // MARK: - Alignment guides

    /// The guides to draw while `frame` is being dragged: the canvas centre lines it is aligned
    /// with, and the edges it shares with another element.
    ///
    /// Reported as percentages so the caller can draw them at whatever size it is rendering.
    static func guides(for frame: SlideFrame, others: [SlideFrame],
                       tolerance: Double = 0.75) -> Guides {
        var vertical: Set<Double> = []
        var horizontal: Set<Double> = []

        func matches(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= tolerance }

        if matches(frame.midX, 50) { vertical.insert(50) }
        if matches(frame.midY, 50) { horizontal.insert(50) }

        for other in others {
            for value in [other.minX, other.midX, other.maxX] {
                if matches(frame.minX, value) || matches(frame.midX, value)
                    || matches(frame.maxX, value) {
                    vertical.insert(value)
                }
            }
            for value in [other.minY, other.midY, other.maxY] {
                if matches(frame.minY, value) || matches(frame.midY, value)
                    || matches(frame.maxY, value) {
                    horizontal.insert(value)
                }
            }
        }
        return Guides(vertical: vertical.sorted(), horizontal: horizontal.sorted())
    }

    struct Guides: Equatable {
        /// Percent positions of vertical guides, i.e. x values.
        var vertical: [Double]
        /// Percent positions of horizontal guides, i.e. y values.
        var horizontal: [Double]

        var isEmpty: Bool { vertical.isEmpty && horizontal.isEmpty }
    }

    // MARK: - Placement

    /// Where a newly inserted element goes: the middle of the canvas at `size`, nudged by
    /// `existingCount` so a second insert does not land exactly on the first.
    ///
    /// The web app drops new elements at a fixed spot for the same reason — there is no cursor on a
    /// canvas to insert "at" — but stacking them invisibly is a way to lose one, so each is offset
    /// by a couple of percent and the offset wraps rather than marching off the slide.
    static func placement(size: SlideFrame, existingCount: Int) -> SlideFrame {
        let step = 2.5
        let nudge = Double(existingCount % 6) * step
        return SlideFrame(x: (100 - size.w) / 2 + nudge,
                          y: (100 - size.h) / 2 + nudge,
                          w: size.w, h: size.h)
            .clampedToCanvas()
    }
}
