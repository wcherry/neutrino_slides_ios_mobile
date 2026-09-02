import Foundation

// MARK: - TextStylePatch

/// A partial change to a ``TextStyle``: the fields it names are written, the rest are left alone.
///
/// Every formatting control produces one of these rather than a whole style, for one reason: a
/// control knows what *it* changed and nothing about the rest. A bold button that handed back a
/// complete style would also be asserting a colour, an alignment and a font — and would silently
/// undo whatever the user set with the control beside it.
///
/// The nested optionals are the price of that. `color: nil` means "leave the colour"; `color:
/// .some(nil)` means "clear it back to the default". Only the fields that can be *absent* on the
/// wire need the second level; `fontSize` and `bold` are always written, so they are plain
/// optionals.
struct TextStylePatch: Equatable {

    var fontSize: Double?
    var bold: Bool?
    var italic: Bool?
    var underline: Bool?
    var strikethrough: Bool??
    var color: String?
    var backgroundColor: String??
    var align: String?
    var fontFamily: String?
    var lineHeight: Double??
    var listType: String??
    var shadow: Bool??
    var shadowColor: String??

    init(fontSize: Double? = nil, bold: Bool? = nil, italic: Bool? = nil, underline: Bool? = nil,
         strikethrough: Bool?? = nil, color: String? = nil, backgroundColor: String?? = nil,
         align: String? = nil, fontFamily: String? = nil, lineHeight: Double?? = nil,
         listType: String?? = nil, shadow: Bool?? = nil, shadowColor: String?? = nil) {
        self.fontSize = fontSize
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.color = color
        self.backgroundColor = backgroundColor
        self.align = align
        self.fontFamily = fontFamily
        self.lineHeight = lineHeight
        self.listType = listType
        self.shadow = shadow
        self.shadowColor = shadowColor
    }

    // MARK: - Applying

    /// The style with this patch written over it.
    func applied(to style: TextStyle) -> TextStyle {
        var style = style
        if let fontSize { style.fontSize = fontSize.clamped(to: Self.fontSizeRange) }
        if let bold { style.bold = bold }
        if let italic { style.italic = italic }
        if let underline { style.underline = underline }
        if let strikethrough { style.strikethrough = strikethrough }
        if let color { style.color = color }
        if let backgroundColor { style.backgroundColor = backgroundColor }
        if let align { style.align = align }
        if let fontFamily { style.fontFamily = fontFamily }
        if let lineHeight { style.lineHeight = lineHeight }
        if let listType { style.listType = listType }
        if let shadow { style.shadow = shadow }
        if let shadowColor { style.shadowColor = shadowColor }
        return style
    }

    var isEmpty: Bool { self == TextStylePatch() }

    // MARK: - Limits

    /// What the size stepper may reach. The floor is legibility on a projector; the ceiling is the
    /// point past which a single word fills a slide, and both match the range the web app's own
    /// size control offers.
    static let fontSizeRange: ClosedRange<Double> = 8...144

    /// The step the "bigger"/"smaller" buttons take, matching the web app's `±2`.
    static let fontSizeStep: Double = 2

    // MARK: - Common patches

    static func size(_ points: Double) -> TextStylePatch {
        TextStylePatch(fontSize: points)
    }

    static func align(_ value: String) -> TextStylePatch {
        TextStylePatch(align: value)
    }

    static func color(_ value: String) -> TextStylePatch {
        TextStylePatch(color: value)
    }

    static func highlight(_ value: String?) -> TextStylePatch {
        TextStylePatch(backgroundColor: .some(value))
    }

    static func fontFamily(_ value: String) -> TextStylePatch {
        TextStylePatch(fontFamily: value)
    }

    static func list(_ value: String?) -> TextStylePatch {
        TextStylePatch(listType: .some(value))
    }
}

// MARK: - FontFamilies

/// The font stacks the picker offers.
///
/// Named the way the web app names them, because the *string* is what gets stored and a deck styled
/// on a phone has to ask for a face the browser can also find. What each one resolves to differs by
/// platform, and that is expected: `Inter` is the web app's default and is the system face here.
enum FontFamilies {

    static let all: [String] = [
        "Inter", "Georgia", "Times New Roman", "Courier New", "Verdana", "Trebuchet MS",
        "Palatino", "Impact",
    ]

    /// What to show for a stored family that is not in the list — the family itself, since it is a
    /// real choice somebody made on the web.
    static func displayName(_ family: String) -> String {
        family.isEmpty ? "Inter" : family
    }
}
