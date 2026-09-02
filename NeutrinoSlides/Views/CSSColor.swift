import SwiftUI
import UIKit

// MARK: - CSSColor

/// Reads the CSS a deck stores.
///
/// The format was designed for a browser, so every colour in it is a CSS string and every gradient
/// is a CSS `linear-gradient(…)` function. Nothing is normalised on write — the web app stores what
/// its pickers produce — so the reader has to take `#fff`, `#ffffffcc`, `rgb(30 64 175)` and
/// `steelblue` alike.
///
/// Everything is memoised. A slide can hold dozens of elements and a thumbnail rail redraws all of
/// them at once, so parsing the same six strings per frame is the difference between a rail that
/// scrolls smoothly and one that does not.
@MainActor
enum CSSColor {

    // MARK: - Colours

    /// Parses a CSS colour: `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, `rgb(…)`, `rgba(…)`, or one of
    /// the named colours the web app's palette actually emits.
    ///
    /// Returns nil for anything unrecognised, which every caller reads as "use the default" — an
    /// element with an unparseable fill should look plain, not invisible.
    static func uiColor(_ css: String?) -> UIColor? {
        guard let css else { return nil }
        let key = css.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty, key != "none", key != "transparent", key != "inherit" else { return nil }
        if let cached = colorCache[key] { return cached }
        let parsed = parseColor(key)
        colorCache[key] = parsed
        return parsed
    }

    /// The same, as a SwiftUI colour.
    static func color(_ css: String?) -> Color? {
        uiColor(css).map(Color.init)
    }

    private static var colorCache: [String: UIColor?] = [:]

    private static func parseColor(_ key: String) -> UIColor? {
        if key.hasPrefix("#") { return hexColor(String(key.dropFirst())) }
        if key.hasPrefix("rgb") { return functionalColor(key) }
        return namedColors[key]
    }

    private static func hexColor(_ digits: String) -> UIColor? {
        let characters = Array(digits)
        // `#rgb` and `#rgba` are shorthand for doubled digits.
        let expanded: [Character]
        switch characters.count {
        case 3, 4: expanded = characters.flatMap { [$0, $0] }
        case 6, 8: expanded = characters
        default:   return nil
        }
        var components: [CGFloat] = []
        for pair in stride(from: 0, to: expanded.count, by: 2) {
            guard let value = UInt8(String(expanded[pair...pair + 1]), radix: 16) else { return nil }
            components.append(CGFloat(value) / 255)
        }
        return UIColor(red: components[0], green: components[1], blue: components[2],
                       alpha: components.count == 4 ? components[3] : 1)
    }

    private static func functionalColor(_ css: String) -> UIColor? {
        guard let open = css.firstIndex(of: "("), let close = css.lastIndex(of: ")") else { return nil }
        let parts = css[css.index(after: open)..<close]
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 3 else { return nil }
        // The alpha component is 0…1; the colour components are 0…255.
        return UIColor(red: CGFloat(parts[0]) / 255, green: CGFloat(parts[1]) / 255,
                       blue: CGFloat(parts[2]) / 255,
                       alpha: parts.count >= 4 ? CGFloat(parts[3]) : 1)
    }

    /// The named colours the web app's own pickers can produce. Not the full CSS list — an
    /// exhaustive table would be 148 entries of which the app emits perhaps eight.
    private static let namedColors: [String: UIColor] = [
        "black": .black, "white": .white, "red": .systemRed, "green": .systemGreen,
        "blue": .systemBlue, "yellow": .systemYellow, "orange": .systemOrange,
        "purple": .systemPurple, "gray": .systemGray, "grey": .systemGray,
    ]

    // MARK: - Writing

    /// `#rrggbb`, lowercase, in sRGB.
    ///
    /// `UIColor` is asked for its components in the extended sRGB space and the result clamped:
    /// a colour picked in Display P3 can hand back components outside 0…1, which would otherwise
    /// format as `#ff-3ff` — a string nothing can parse.
    static func hex(from color: Color) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let channel = { (value: CGFloat) in Int((value.clamped(to: 0...1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", channel(red), channel(green), channel(blue))
    }

    // MARK: - Gradients

    /// A parsed `linear-gradient(…)`.
    struct Gradient: Equatable {
        var stops: [Stop]
        /// CSS degrees: 0 points to the top of the box, increasing clockwise.
        var angle: Double

        struct Stop: Equatable {
            var color: Color
            /// 0…1 along the gradient line.
            var location: Double
        }

        /// The SwiftUI gradient, with the CSS angle converted into start and end points.
        ///
        /// The conversion is the unit-square approximation rather than CSS's exact gradient-line
        /// length, which also accounts for the box's aspect ratio. On a 16:9 slide the difference
        /// is a couple of degrees of apparent tilt, and the exact version needs the box's size —
        /// which would mean a gradient that has to be rebuilt on every layout pass.
        var linearGradient: LinearGradient {
            let radians = angle * .pi / 180
            let dx = sin(radians) / 2
            let dy = cos(radians) / 2
            return LinearGradient(
                stops: stops.map { .init(color: $0.color, location: $0.location) },
                startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 + dy),
                endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 - dy)
            )
        }
    }

    /// Whether a stored background value is a gradient rather than a flat colour.
    ///
    /// Worth asking because a gradient is routinely stored under `type: "color"` — see
    /// ``SlideTheme/slideBackground`` for why — so the *value* is what decides how to paint it, not
    /// the background's declared type.
    static func isGradient(_ css: String) -> Bool {
        css.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("linear-gradient(")
    }

    /// Parses `linear-gradient(<angle>, <color> <stop>?, …)`.
    ///
    /// Returns nil for a radial or conic gradient, and for anything malformed; the caller falls
    /// back to a flat colour, which is the same thing the CSS spec calls for when a gradient cannot
    /// be resolved.
    static func gradient(_ css: String) -> Gradient? {
        let trimmed = css.trimmingCharacters(in: .whitespaces)
        if let cached = gradientCache[trimmed] { return cached }
        let parsed = parseGradient(trimmed)
        gradientCache[trimmed] = parsed
        return parsed
    }

    private static var gradientCache: [String: Gradient?] = [:]

    private static func parseGradient(_ css: String) -> Gradient? {
        let lower = css.lowercased()
        guard lower.hasPrefix("linear-gradient("), css.hasSuffix(")") else { return nil }
        let inner = String(css.dropFirst("linear-gradient(".count).dropLast())
        var parts = splitTopLevel(inner)
        guard !parts.isEmpty else { return nil }

        // The first part is the direction, when there is one: `135deg`, `to right`, `to bottom
        // left`. A gradient with no direction runs top to bottom, which is CSS's default.
        var angle: Double = 180
        if let direction = angleValue(parts[0]) {
            angle = direction
            parts.removeFirst()
        }
        guard !parts.isEmpty else { return nil }

        var stops: [Gradient.Stop] = []
        for (index, part) in parts.enumerated() {
            let (colorToken, positionToken) = splitStop(part)
            guard let color = color(colorToken) else { continue }
            let location: Double
            if let positionToken, positionToken.hasSuffix("%"),
               let percent = Double(positionToken.dropLast()) {
                location = percent / 100
            } else {
                // Evenly spaced, which is what CSS does for stops with no position.
                location = parts.count > 1 ? Double(index) / Double(parts.count - 1) : 0
            }
            stops.append(Gradient.Stop(color: color, location: location.clamped(to: 0...1)))
        }
        guard stops.count >= 2 else { return nil }
        return Gradient(stops: stops, angle: angle)
    }

    /// Splits one stop into its colour and its optional position.
    ///
    /// Not a split on whitespace: `rgb(1, 2, 3) 50%` is a colour containing two spaces, and cutting
    /// at the first one leaves `rgb(1,` — which parses as nothing, so the stop is dropped and a
    /// two-stop gradient becomes no gradient at all.
    private static func splitStop(_ part: String) -> (color: String, position: String?) {
        if let open = part.firstIndex(of: "("), let close = part[open...].firstIndex(of: ")") {
            let color = String(part[...close])
            let rest = part[part.index(after: close)...].trimmingCharacters(in: .whitespaces)
            return (color, rest.isEmpty ? nil : rest)
        }
        let tokens = part.split(separator: " ", maxSplits: 1).map(String.init)
        return (tokens.first ?? part, tokens.count > 1 ? tokens[1] : nil)
    }

    /// The angle a direction token names, or nil when the token is a colour stop instead.
    private static func angleValue(_ token: String) -> Double? {
        let lower = token.lowercased()
        if lower.hasSuffix("deg") { return Double(lower.dropLast(3)) }
        guard lower.hasPrefix("to ") else { return nil }
        switch lower.dropFirst(3).trimmingCharacters(in: .whitespaces) {
        case "top":                        return 0
        case "top right", "right top":     return 45
        case "right":                      return 90
        case "bottom right", "right bottom": return 135
        case "bottom":                     return 180
        case "bottom left", "left bottom": return 225
        case "left":                       return 270
        case "top left", "left top":       return 315
        default:                           return nil
        }
    }

    /// Splits on commas that are not inside brackets, so `rgb(1, 2, 3) 50%` stays one part.
    private static func splitTopLevel(_ string: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for character in string {
            switch character {
            case "(": depth += 1; current.append(character)
            case ")": depth -= 1; current.append(character)
            case "," where depth == 0:
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            default: current.append(character)
            }
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { parts.append(last) }
        return parts.filter { !$0.isEmpty }
    }

    // MARK: - Fonts

    /// The font for stored text, honouring family, size, weight and slant.
    ///
    /// Falls back to the system face for any family the device does not have. The web app's default
    /// stack is Inter/system-ui, which on iOS *is* the system face, so the common case is a plain
    /// system font and the fallback is not a compromise.
    static func font(family: String?, size: CGFloat, bold: Bool, italic: Bool) -> UIFont {
        let key = FontKey(family: family, size: size, bold: bold, italic: italic)
        if let cached = fontCache[key] { return cached }

        let custom = customFont(named: family, size: size)
        var font = custom ?? UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        var traits: UIFontDescriptor.SymbolicTraits = []
        // A custom face needs its traits applied by descriptor; the system face already carries
        // its weight from `systemFont(ofSize:weight:)`.
        if bold, custom != nil { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if !traits.isEmpty, let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            font = UIFont(descriptor: descriptor, size: size)
        }
        fontCache[key] = font
        return font
    }

    /// Resolves the first family in a CSS font stack that the device actually has.
    private static func customFont(named family: String?, size: CGFloat) -> UIFont? {
        guard let family else { return nil }
        for candidate in family.split(separator: ",") {
            let name = candidate.trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
            guard !name.isEmpty else { continue }
            // These are the CSS generics and the system stack; they mean "the system face", which
            // is the fallback anyway.
            let lower = name.lowercased()
            if ["inter", "system-ui", "-apple-system", "sans-serif", "ui-sans-serif",
                "arial", "helvetica"].contains(lower) { return nil }
            if let font = UIFont(name: name, size: size) { return font }
        }
        return nil
    }

    private struct FontKey: Hashable {
        let family: String?
        let size: CGFloat
        let bold: Bool
        let italic: Bool
    }

    private static var fontCache: [FontKey: UIFont] = [:]

    // MARK: - Cache lifetime

    /// Drops the memo tables. Called on a memory warning — every entry is reconstructible, and a
    /// deck with a hundred distinct styles is the case where the caches are worth the most and cost
    /// the most.
    static func flushCaches() {
        colorCache.removeAll(keepingCapacity: true)
        gradientCache.removeAll(keepingCapacity: true)
        fontCache.removeAll(keepingCapacity: true)
    }
}

// MARK: - StyleColors

/// The colours the format controls offer.
///
/// Everything written into a deck is `#rrggbb`. The web app's own pickers write hex, the renderer
/// parses it, and a device-dependent spelling — a `UIColor` description, a P3 `color()` function —
/// would be a value the browser could not read at all.
@MainActor
enum StyleColors {

    /// Neutrals, saturated hues and their tints, drawn from the palette the built-in themes use so
    /// a hand-picked fill sits next to a themed one without clashing.
    static let palette: [[String]] = [
        ["#000000", "#374151", "#6b7280", "#9ca3af", "#d1d5db", "#e5e7eb", "#f3f4f6", "#ffffff"],
        ["#b91c1c", "#c2410c", "#b45309", "#15803d", "#0f766e", "#1e40af", "#4338ca", "#6d28d9"],
        ["#fee2e2", "#ffedd5", "#fef3c7", "#dcfce7", "#ccfbf1", "#dbeafe", "#e0e7ff", "#ede9fe"],
    ]
}

// MARK: - ColorPickerSheet

/// Picks one colour for a style field: a swatch grid, an arbitrary-colour picker, and a way back to
/// no colour at all.
struct ColorPickerSheet: View {

    // MARK: - Input

    let title: String
    /// What the field currently holds, so the grid can mark it.
    let selected: String?
    /// The wording for clearing the field — "Automatic" for text, "No Fill" for a background.
    /// Nil hides the clear button entirely, for a field that must hold a colour.
    var clearLabel: String?
    let onPick: (String?) -> Void

    // MARK: - State

    @Environment(\.dismiss) private var dismiss
    @State private var custom: Color = .accentColor

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 8)

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(StyleColors.palette.enumerated()), id: \.offset) { _, row in
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(row, id: \.self) { hex in
                                swatch(hex)
                            }
                        }
                    }

                    Divider()

                    ColorPicker("Custom Colour", selection: $custom, supportsOpacity: false)
                        .onChange(of: custom) { pick(CSSColor.hex(from: $0)) }

                    if let clearLabel {
                        Button(role: .destructive) {
                            pick(nil)
                        } label: {
                            Label(clearLabel, systemImage: "slash.circle")
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Pieces

    private func swatch(_ hex: String) -> some View {
        let isSelected = selected?.lowercased() == hex
        return Button {
            pick(hex)
        } label: {
            RoundedRectangle(cornerRadius: 6)
                .fill(CSSColor.color(hex) ?? .clear)
                .frame(height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isSelected ? Color.accentColor : Color(.separator),
                                      lineWidth: isSelected ? 3 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hex)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Applies and dismisses in one step: a colour sheet that stays open after a tap makes the user
    /// close it themselves to see what they picked, over the slide it just changed.
    private func pick(_ hex: String?) {
        onPick(hex)
        dismiss()
    }
}
