import Foundation

// MARK: - SlideTransition

/// How a slide arrives, mirroring `Slide['transition']` on the web.
///
/// A slide stores this as a plain string (``Slide/transition``) rather than as this type, so a
/// transition a later web release adds is carried through a mobile save untouched. This enum is the
/// *vocabulary this build understands*: `SlideTransition(stored:)` maps a string onto it, and
/// anything unrecognised plays as ``fade`` — a transition that is merely different is a better
/// outcome than a slide that does not appear.
enum SlideTransition: String, CaseIterable, Identifiable {
    case none
    case fade
    case dissolve
    /// The web app's `'slide'`: the incoming slide enters from the right.
    case slideRight = "slide"
    case slideLeft  = "slide-left"
    case flip
    case cube
    case gallery
    case pixelate
    case cover
    case wipe
    case zoom

    var id: String { rawValue }

    // MARK: - Reading

    /// Maps a stored value, falling back to ``fade`` for anything this build does not know.
    init(stored: String) {
        self = SlideTransition(rawValue: stored) ?? .fade
    }

    // MARK: - Display

    var displayName: String {
        switch self {
        case .none:       return "None"
        case .fade:       return "Fade"
        case .dissolve:   return "Dissolve"
        case .slideRight: return "Slide Right"
        case .slideLeft:  return "Slide Left"
        case .flip:       return "Flip"
        case .cube:       return "Cube"
        case .gallery:    return "Gallery"
        case .pixelate:   return "Pixelate"
        case .cover:      return "Cover"
        case .wipe:       return "Wipe"
        case .zoom:       return "Zoom"
        }
    }

    var iconName: String {
        switch self {
        case .none:       return "rectangle"
        case .fade:       return "circle.lefthalf.filled"
        case .dissolve:   return "sparkles"
        case .slideRight: return "arrow.right.to.line"
        case .slideLeft:  return "arrow.left.to.line"
        case .flip:       return "arrow.triangle.2.circlepath"
        case .cube:       return "cube"
        case .gallery:    return "rectangle.stack"
        case .pixelate:   return "square.grid.3x3"
        case .cover:      return "rectangle.on.rectangle"
        case .wipe:       return "arrow.right.square"
        case .zoom:       return "plus.magnifyingglass"
        }
    }

    /// How long the arrival takes. The web app runs everything at 500ms except `none`, and matching
    /// it keeps a deck rehearsed on a laptop the same length on a phone.
    var duration: TimeInterval {
        self == .none ? 0 : 0.5
    }
}
