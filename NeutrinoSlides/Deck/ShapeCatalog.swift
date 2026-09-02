import CoreGraphics
import Foundation

// MARK: - ShapeCatalog

/// The shapes a deck can hold, and the outlines they draw.
///
/// The keys and the path data are copied verbatim from `SHAPE_CATALOG` in the web app's
/// `slideEditorConstants.ts`, in the same 100×100 coordinate space. That is the contract: a
/// `"hexagon"` written on a phone has to be the same hexagon on the web, and the only way to be
/// sure of that is to draw from the same numbers rather than from a second author's idea of a
/// hexagon.
///
/// A key this build does not know draws as a rectangle. Not as nothing: an unknown shape is still
/// an element with a fill and a position, and leaving a hole where the user put something is worse
/// than drawing it plainly.
enum ShapeCatalog {

    // MARK: - Group

    enum Group: String, CaseIterable, Identifiable {
        case general, arrows, callouts

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .general:  return "General"
            case .arrows:   return "Arrows"
            case .callouts: return "Callouts"
            }
        }
    }

    // MARK: - Entry

    struct Entry: Identifiable, Hashable {
        let key: String
        let label: String
        let group: Group
        /// SVG path data in a 100×100 box.
        let path: String

        var id: String { key }
    }

    // MARK: - Catalog

    /// Ordered as the web app's shape panel orders them, so the two galleries read the same.
    static let entries: [Entry] = [
        // General
        Entry(key: "rect", label: "Rectangle", group: .general,
              path: "M 0,0 H 100 V 100 H 0 Z"),
        Entry(key: "rounded-rect", label: "Rounded Rect", group: .general,
              path: "M 15,0 H 85 Q 100,0 100,15 V 85 Q 100,100 85,100 H 15 Q 0,100 0,85 V 15 Q 0,0 15,0 Z"),
        Entry(key: "circle", label: "Circle", group: .general,
              path: "M 50,0 C 77.6,0 100,22.4 100,50 C 100,77.6 77.6,100 50,100 C 22.4,100 0,77.6 0,50 C 0,22.4 22.4,0 50,0 Z"),
        Entry(key: "triangle", label: "Triangle", group: .general,
              path: "M 50,0 L 100,100 L 0,100 Z"),
        Entry(key: "right-triangle", label: "Right Triangle", group: .general,
              path: "M 0,0 L 100,100 L 0,100 Z"),
        Entry(key: "parallelogram", label: "Parallelogram", group: .general,
              path: "M 20,0 L 100,0 L 80,100 L 0,100 Z"),
        Entry(key: "trapezoid", label: "Trapezoid", group: .general,
              path: "M 20,0 L 80,0 L 100,100 L 0,100 Z"),
        Entry(key: "diamond", label: "Diamond", group: .general,
              path: "M 50,0 L 100,50 L 50,100 L 0,50 Z"),
        Entry(key: "pentagon", label: "Pentagon", group: .general,
              path: "M 50,0 L 97.6,34.5 L 79.4,90.5 L 20.6,90.5 L 2.4,34.5 Z"),
        Entry(key: "hexagon", label: "Hexagon", group: .general,
              path: "M 50,0 L 93.3,25 L 93.3,75 L 50,100 L 6.7,75 L 6.7,25 Z"),
        Entry(key: "octagon", label: "Octagon", group: .general,
              path: "M 30,0 L 70,0 L 100,30 L 100,70 L 70,100 L 30,100 L 0,70 L 0,30 Z"),
        Entry(key: "cross", label: "Cross", group: .general,
              path: "M 35,0 H 65 V 35 H 100 V 65 H 65 V 100 H 35 V 65 H 0 V 35 H 35 Z"),
        Entry(key: "star4", label: "4-Point Star", group: .general,
              path: "M 50,0 L 64,36 L 100,50 L 64,64 L 50,100 L 36,64 L 0,50 L 36,36 Z"),
        Entry(key: "star5", label: "5-Point Star", group: .general,
              path: "M 50,0 L 62,34 L 98,35 L 69,56 L 79,91 L 50,70 L 21,91 L 31,56 L 2,35 L 38,34 Z"),
        Entry(key: "star6", label: "6-Point Star", group: .general,
              path: "M 50,0 L 62.5,28 L 93.3,25 L 75,50 L 93.3,75 L 62.5,72 L 50,100 L 37.5,72 L 6.7,75 L 25,50 L 6.7,25 L 37.5,28 Z"),
        Entry(key: "heart", label: "Heart", group: .general,
              path: "M 50,85 C 10,65 0,40 15,25 C 25,15 38,18 50,32 C 62,18 75,15 85,25 C 100,40 90,65 50,85 Z"),

        // Arrows
        Entry(key: "arrow-right", label: "Right Arrow", group: .arrows,
              path: "M 0,30 H 60 V 10 L 100,50 L 60,90 V 70 H 0 Z"),
        Entry(key: "arrow-left", label: "Left Arrow", group: .arrows,
              path: "M 100,30 H 40 V 10 L 0,50 L 40,90 V 70 H 100 Z"),
        Entry(key: "arrow-up", label: "Up Arrow", group: .arrows,
              path: "M 30,100 V 45 H 10 L 50,0 L 90,45 H 70 V 100 Z"),
        Entry(key: "arrow-down", label: "Down Arrow", group: .arrows,
              path: "M 30,0 V 55 H 10 L 50,100 L 90,55 H 70 V 0 Z"),
        Entry(key: "arrow-lr", label: "Left-Right Arrow", group: .arrows,
              path: "M 0,50 L 25,10 V 35 H 75 V 10 L 100,50 L 75,90 V 65 H 25 V 90 Z"),
        Entry(key: "arrow-ud", label: "Up-Down Arrow", group: .arrows,
              path: "M 50,0 L 90,25 H 65 V 75 H 90 L 50,100 L 10,75 H 35 V 25 H 10 Z"),
        Entry(key: "chevron-r", label: "Chevron Right", group: .arrows,
              path: "M 0,0 H 65 L 100,50 L 65,100 H 0 L 35,50 Z"),
        Entry(key: "chevron-l", label: "Chevron Left", group: .arrows,
              path: "M 100,0 H 35 L 0,50 L 35,100 H 100 L 65,50 Z"),
        Entry(key: "arrow-pentagon", label: "Pentagon Arrow", group: .arrows,
              path: "M 0,0 H 70 L 100,50 L 70,100 H 0 Z"),
        Entry(key: "arrow-notched", label: "Notched Arrow", group: .arrows,
              path: "M 0,25 H 60 V 0 L 100,50 L 60,100 V 75 H 0 L 20,50 Z"),
        Entry(key: "arrow-quad", label: "Four Arrows", group: .arrows,
              path: "M 50,0 L 65,20 L 57,20 L 57,43 L 80,43 L 80,35 L 100,50 L 80,65 L 80,57 L 57,57 L 57,80 L 65,80 L 50,100 L 35,80 L 43,80 L 43,57 L 20,57 L 20,65 L 0,50 L 20,35 L 20,43 L 43,43 L 43,20 L 35,20 Z"),

        // Callouts
        Entry(key: "callout-rect", label: "Rect Callout", group: .callouts,
              path: "M 0,0 H 100 V 70 H 35 L 15,100 L 25,70 H 0 Z"),
        Entry(key: "callout-rounded", label: "Rounded Callout", group: .callouts,
              path: "M 12,0 H 88 Q 100,0 100,12 V 58 Q 100,70 88,70 H 35 L 15,100 L 25,70 H 12 Q 0,70 0,58 V 12 Q 0,0 12,0 Z"),
        Entry(key: "callout-oval", label: "Oval Callout", group: .callouts,
              path: "M 50,0 C 80,0 100,17 100,45 C 100,65 85,78 65,80 L 30,100 L 55,78 C 25,74 0,62 0,45 C 0,17 20,0 50,0 Z"),
        Entry(key: "callout-cloud", label: "Cloud Callout", group: .callouts,
              path: "M 48,8 C 58,2 72,6 76,16 C 85,14 95,22 93,33 C 100,36 103,46 97,52 C 102,58 100,70 90,72 C 90,82 80,88 70,84 C 65,92 53,95 46,88 C 38,94 26,91 24,82 C 14,82 6,74 8,64 C 0,60 -2,48 5,42 C 0,35 4,24 13,22 C 12,11 22,4 32,8 C 36,2 45,2 48,8 Z M 28,88 C 24,93 20,97 17,100 C 20,96 22,90 24,82 Z"),
    ]

    /// The default when a shape is added from the toolbar rather than the gallery.
    static let defaultKey = "rect"

    private static let byKey: [String: Entry] = Dictionary(
        uniqueKeysWithValues: entries.map { ($0.key, $0) }
    )

    static func entry(for key: String) -> Entry? { byKey[key] }

    static func label(for key: String) -> String { byKey[key]?.label ?? "Shape" }

    static func entries(in group: Group) -> [Entry] { entries.filter { $0.group == group } }

    // MARK: - Drawing

    /// The shape's outline, scaled into `rect`.
    ///
    /// An unknown key returns the rectangle `rect` itself — see the type's note on why that is not
    /// an empty path.
    static func cgPath(for key: String, in rect: CGRect) -> CGPath {
        guard let entry = byKey[key], let path = SVGPath.parse(entry.path) else {
            return CGPath(rect: rect, transform: nil)
        }
        // The catalog is authored in a 100×100 box; scaling into the element's rect is the whole
        // conversion, and it is deliberately non-uniform — a "circle" stretched into a wide box is
        // an ellipse, which is what the same element looks like on the web.
        var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / 100, y: rect.height / 100)
        return path.copy(using: &transform) ?? path
    }
}

// MARK: - SVGPath

/// A parser for the subset of SVG path data the shape catalog uses.
///
/// Deliberately a subset: `M`, `L`, `H`, `V`, `C`, `Q`, `Z` (and their relative spellings) are
/// every command in the catalog, and a general SVG parser — arcs, smooth curves, implicit repeats
/// across command boundaries — would be several hundred lines of code with no second caller and no
/// way to be confident it is right. An unsupported command aborts the parse, which surfaces as the
/// shape drawing as a plain rectangle rather than as a silently wrong outline.
enum SVGPath {

    /// Parses path data in the catalog's 100×100 space, or nil if it contains anything unsupported.
    static func parse(_ data: String) -> CGPath? {
        let path = CGMutablePath()
        var tokens = Tokenizer(data)
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var command: Character?
        var hasMoved = false

        while let token = tokens.next() {
            if let letter = token.command {
                command = letter
            } else {
                // A repeated coordinate set continues the previous command — `L 1,2 3,4` — which
                // the catalog does not use but SVG allows, and which is free to support here.
                tokens.pushBack(token)
            }
            guard let letter = command else { return nil }

            let relative = letter.isLowercase
            switch Character(letter.lowercased()) {
            case "m":
                guard let x = tokens.number(), let y = tokens.number() else { return nil }
                current = point(x, y, relativeTo: current, relative: relative)
                path.move(to: current)
                subpathStart = current
                hasMoved = true
                // Per the SVG spec a second coordinate pair after `M` is a line, not another move.
                command = relative ? "l" : "L"

            case "l":
                guard hasMoved, let x = tokens.number(), let y = tokens.number() else { return nil }
                current = point(x, y, relativeTo: current, relative: relative)
                path.addLine(to: current)

            case "h":
                guard hasMoved, let x = tokens.number() else { return nil }
                current = CGPoint(x: relative ? current.x + CGFloat(x) : CGFloat(x), y: current.y)
                path.addLine(to: current)

            case "v":
                guard hasMoved, let y = tokens.number() else { return nil }
                current = CGPoint(x: current.x, y: relative ? current.y + CGFloat(y) : CGFloat(y))
                path.addLine(to: current)

            case "q":
                guard hasMoved,
                      let cx = tokens.number(), let cy = tokens.number(),
                      let x = tokens.number(), let y = tokens.number() else { return nil }
                let control = point(cx, cy, relativeTo: current, relative: relative)
                current = point(x, y, relativeTo: current, relative: relative)
                path.addQuadCurve(to: current, control: control)

            case "c":
                guard hasMoved,
                      let c1x = tokens.number(), let c1y = tokens.number(),
                      let c2x = tokens.number(), let c2y = tokens.number(),
                      let x = tokens.number(), let y = tokens.number() else { return nil }
                let control1 = point(c1x, c1y, relativeTo: current, relative: relative)
                let control2 = point(c2x, c2y, relativeTo: current, relative: relative)
                current = point(x, y, relativeTo: current, relative: relative)
                path.addCurve(to: current, control1: control1, control2: control2)

            case "z":
                guard hasMoved else { return nil }
                path.closeSubpath()
                current = subpathStart

            default:
                return nil
            }
        }
        return path.isEmpty ? nil : path.copy()
    }

    private static func point(_ x: Double, _ y: Double, relativeTo origin: CGPoint,
                              relative: Bool) -> CGPoint {
        relative ? CGPoint(x: origin.x + CGFloat(x), y: origin.y + CGFloat(y))
                 : CGPoint(x: CGFloat(x), y: CGFloat(y))
    }

    // MARK: - Tokenizer

    private struct Token {
        let command: Character?
        let number: Double?
    }

    private struct Tokenizer {

        private let characters: [Character]
        private var index: Int = 0
        private var pushedBack: Token?

        init(_ string: String) {
            characters = Array(string)
        }

        mutating func pushBack(_ token: Token) {
            pushedBack = token
        }

        mutating func next() -> Token? {
            if let token = pushedBack {
                pushedBack = nil
                return token
            }
            skipSeparators()
            guard index < characters.count else { return nil }
            let character = characters[index]
            if character.isLetter {
                index += 1
                return Token(command: character, number: nil)
            }
            guard let value = readNumber() else { return nil }
            return Token(command: nil, number: value)
        }

        /// The next number, or nil if what comes next is a command or the end of the data.
        mutating func number() -> Double? {
            guard let token = next() else { return nil }
            guard let value = token.number else {
                pushBack(token)
                return nil
            }
            return value
        }

        private mutating func skipSeparators() {
            while index < characters.count,
                  characters[index] == " " || characters[index] == ","
                    || characters[index] == "\n" || characters[index] == "\t" {
                index += 1
            }
        }

        private mutating func readNumber() -> Double? {
            let start = index
            if index < characters.count, characters[index] == "-" || characters[index] == "+" {
                index += 1
            }
            while index < characters.count,
                  characters[index].isNumber || characters[index] == "." {
                index += 1
            }
            guard index > start else { return nil }
            return Double(String(characters[start..<index]))
        }
    }
}
