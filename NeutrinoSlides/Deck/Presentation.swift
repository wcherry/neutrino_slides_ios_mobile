import Foundation

// MARK: - TextStyle

/// How a text box is drawn, mirroring `TextStyle` in
/// `web/apps/web/src/app/(apps)/slides/editor/slideEditorTypes.ts`.
///
/// The seven fields the web app always writes are non-optional here and always written back; the
/// rest are omitted when nil, because the web app writes a sparse object and a deck that gained
/// `"lineHeight":null` on every mobile save would differ from the same deck saved on the web for no
/// reason.
///
/// `align` and `listType` are deliberately *not* Swift enums. An unrecognised value must survive a
/// round trip rather than fail to decode: `justify` was added to the web app after this app was
/// written, and a decoder that rejected it would refuse to open the deck.
struct TextStyle: Hashable {

    // MARK: - Always written

    /// Points, as the web app stores them — a plain number, not a CSS length.
    var fontSize: Double
    var bold: Bool
    var italic: Bool
    var underline: Bool
    /// A CSS colour, e.g. `"#1f2937"`.
    var color: String
    /// `"left"`, `"center"`, `"right"` or `"justify"`.
    var align: String
    var fontFamily: String

    // MARK: - Optional

    var strikethrough: Bool?
    var backgroundColor: String?
    var lineHeight: Double?
    /// Points of space above each paragraph except the first.
    var spaceBefore: Double?
    /// Points of space below each paragraph.
    var spaceAfter: Double?
    /// `"none"`, `"bullet"` or `"numbered"`.
    var listType: String?
    var shadow: Bool?
    var shadowColor: String?

    /// Anything a later web release adds. See ``JSONValue``.
    var unknownFields: UnknownFields

    // MARK: - Init

    init(fontSize: Double = 24, bold: Bool = false, italic: Bool = false, underline: Bool = false,
         color: String = "#1f2937", align: String = "left", fontFamily: String = "Inter",
         strikethrough: Bool? = nil, backgroundColor: String? = nil, lineHeight: Double? = nil,
         spaceBefore: Double? = nil, spaceAfter: Double? = nil, listType: String? = nil,
         shadow: Bool? = nil, shadowColor: String? = nil,
         unknownFields: UnknownFields = UnknownFields()) {
        self.fontSize = fontSize
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.color = color
        self.align = align
        self.fontFamily = fontFamily
        self.strikethrough = strikethrough
        self.backgroundColor = backgroundColor
        self.lineHeight = lineHeight
        self.spaceBefore = spaceBefore
        self.spaceAfter = spaceAfter
        self.listType = listType
        self.shadow = shadow
        self.shadowColor = shadowColor
        self.unknownFields = unknownFields
    }

    // MARK: - Computed

    var isStrikethrough: Bool { strikethrough == true }
    var isBulleted: Bool { listType == "bullet" }
    var isNumbered: Bool { listType == "numbered" }
}

// MARK: - TextStyle + Codable

extension TextStyle: Codable {

    static let knownKeys: Set<String> = ["fontSize", "bold", "italic", "underline", "color",
                                         "align", "fontFamily", "strikethrough", "backgroundColor",
                                         "lineHeight", "spaceBefore", "spaceAfter", "listType",
                                         "shadow", "shadowColor"]

    private enum CodingKeys: String, CodingKey {
        case fontSize, bold, italic, underline, color, align, fontFamily
        case strikethrough, backgroundColor, lineHeight, spaceBefore, spaceAfter, listType
        case shadow, shadowColor
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Every one of these is defaulted rather than required. A deck built by the PPTX importer
        // or by an older web release can be missing any of them, and refusing to open a deck over a
        // missing `underline` would be a decoder that is stricter than the format.
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 24
        bold = try container.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        italic = try container.decodeIfPresent(Bool.self, forKey: .italic) ?? false
        underline = try container.decodeIfPresent(Bool.self, forKey: .underline) ?? false
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? "#1f2937"
        align = try container.decodeIfPresent(String.self, forKey: .align) ?? "left"
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? "Inter"
        strikethrough = try container.decodeIfPresent(Bool.self, forKey: .strikethrough)
        backgroundColor = try container.decodeIfPresent(String.self, forKey: .backgroundColor)
        lineHeight = try container.decodeIfPresent(Double.self, forKey: .lineHeight)
        spaceBefore = try container.decodeIfPresent(Double.self, forKey: .spaceBefore)
        spaceAfter = try container.decodeIfPresent(Double.self, forKey: .spaceAfter)
        listType = try container.decodeIfPresent(String.self, forKey: .listType)
        shadow = try container.decodeIfPresent(Bool.self, forKey: .shadow)
        shadowColor = try container.decodeIfPresent(String.self, forKey: .shadowColor)
        unknownFields = try UnknownFields(from: decoder, excluding: Self.knownKeys)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(bold, forKey: .bold)
        try container.encode(italic, forKey: .italic)
        try container.encode(underline, forKey: .underline)
        try container.encode(color, forKey: .color)
        try container.encode(align, forKey: .align)
        try container.encode(fontFamily, forKey: .fontFamily)
        try container.encodeIfPresent(strikethrough, forKey: .strikethrough)
        try container.encodeIfPresent(backgroundColor, forKey: .backgroundColor)
        try container.encodeIfPresent(lineHeight, forKey: .lineHeight)
        try container.encodeIfPresent(spaceBefore, forKey: .spaceBefore)
        try container.encodeIfPresent(spaceAfter, forKey: .spaceAfter)
        try container.encodeIfPresent(listType, forKey: .listType)
        try container.encodeIfPresent(shadow, forKey: .shadow)
        try container.encodeIfPresent(shadowColor, forKey: .shadowColor)
        try unknownFields.encode(to: encoder, excluding: Self.knownKeys)
    }
}

// MARK: - ElementAnimation

/// A per-element entrance animation, mirroring `ElementAnimation` on the web.
///
/// Modelled but **not played**: presenter mode animates the slide *transition* (Epic 12) and leaves
/// element entrances to Epic 18. Typing it anyway is what keeps it on the file — an animation set on
/// the web has to survive a save made from a phone.
struct ElementAnimation: Codable, Hashable {
    /// `"none"`, `"fade"`, `"fly-in"` or `"zoom"`.
    var type: String
    /// Milliseconds.
    var duration: Double
    /// Milliseconds.
    var delay: Double
    /// `"left"`, `"right"`, `"top"` or `"bottom"`, for `fly-in`.
    var direction: String?
}

// MARK: - TextElement

/// A text box. Geometry is in canvas percent — see ``SlideFrame``.
struct TextElement: Hashable {
    var id: String
    var frame: SlideFrame
    var content: String
    var style: TextStyle
    var animation: ElementAnimation?
    var unknownFields: UnknownFields

    init(id: String = SlideID.make(), frame: SlideFrame, content: String, style: TextStyle,
         animation: ElementAnimation? = nil, unknownFields: UnknownFields = UnknownFields()) {
        self.id = id
        self.frame = frame
        self.content = content
        self.style = style
        self.animation = animation
        self.unknownFields = unknownFields
    }
}

// MARK: - ShapeElement

/// A filled shape drawn from ``ShapeCatalog``.
struct ShapeElement: Hashable {
    var id: String
    /// A key into ``ShapeCatalog``; an unknown key draws as a rectangle rather than as nothing.
    var shape: String
    var frame: SlideFrame
    var fill: String
    var stroke: String
    var strokeWidth: Double
    /// An SVG dash pattern, e.g. `"8 4"`.
    var strokeDash: String?
    var animation: ElementAnimation?
    var unknownFields: UnknownFields

    init(id: String = SlideID.make(), shape: String = "rect", frame: SlideFrame,
         fill: String = "#818cf8", stroke: String = "transparent", strokeWidth: Double = 0,
         strokeDash: String? = nil, animation: ElementAnimation? = nil,
         unknownFields: UnknownFields = UnknownFields()) {
        self.id = id
        self.shape = shape
        self.frame = frame
        self.fill = fill
        self.stroke = stroke
        self.strokeWidth = strokeWidth
        self.strokeDash = strokeDash
        self.animation = animation
        self.unknownFields = unknownFields
    }
}

// MARK: - LineElement

/// A straight line or arrow. Stored as two endpoints rather than a box, which is why it is the one
/// element whose ``SlideElement/frame`` is derived; see ``LineElement/frame``.
struct LineElement: Hashable {
    var id: String
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double
    var stroke: String
    var strokeWidth: Double
    var strokeDash: String?
    /// `"none"`, `"arrow"` or `"triangle"`.
    var startArrow: String?
    var endArrow: String?
    var animation: ElementAnimation?
    var unknownFields: UnknownFields

    init(id: String = SlideID.make(), x1: Double, y1: Double, x2: Double, y2: Double,
         stroke: String = "#1f2937", strokeWidth: Double = 2, strokeDash: String? = nil,
         startArrow: String? = nil, endArrow: String? = nil, animation: ElementAnimation? = nil,
         unknownFields: UnknownFields = UnknownFields()) {
        self.id = id
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
        self.stroke = stroke
        self.strokeWidth = strokeWidth
        self.strokeDash = strokeDash
        self.startArrow = startArrow
        self.endArrow = endArrow
        self.animation = animation
        self.unknownFields = unknownFields
    }

    /// The bounding box of the two endpoints, so a line can be dragged and resized like anything
    /// else on the canvas.
    var frame: SlideFrame {
        SlideFrame(x: min(x1, x2), y: min(y1, y2), w: abs(x2 - x1), h: abs(y2 - y1))
    }

    /// Maps the endpoints into `frame`, keeping which corner each one sits in.
    ///
    /// Proportional rather than absolute: a line drawn bottom-left to top-right must still run
    /// bottom-left to top-right after a resize, and rewriting the endpoints as
    /// `(frame.minX, frame.minY)` and `(frame.maxX, frame.maxY)` would silently flip half of them.
    mutating func setFrame(_ frame: SlideFrame) {
        let old = self.frame
        func map(_ value: Double, from origin: Double, oldSize: Double,
                 to newOrigin: Double, newSize: Double) -> Double {
            // A zero-width box has no ratio to preserve; both endpoints sit on the new origin.
            guard oldSize > 0 else { return newOrigin }
            return newOrigin + (value - origin) / oldSize * newSize
        }
        x1 = map(x1, from: old.x, oldSize: old.w, to: frame.x, newSize: frame.w)
        x2 = map(x2, from: old.x, oldSize: old.w, to: frame.x, newSize: frame.w)
        y1 = map(y1, from: old.y, oldSize: old.h, to: frame.y, newSize: frame.h)
        y2 = map(y2, from: old.y, oldSize: old.h, to: frame.y, newSize: frame.h)
    }
}

// MARK: - ImageElement

/// A picture. `src` is one of three things, and only two of them are bytes this app can draw:
/// a `data:` URL, an `http(s):` URL, or a `neutrino-drive:<fileId>` reference (see the web app's
/// `lib/driveImages.ts`). The reference form needs the download-and-decrypt path that is Epic 15,
/// and until then it renders as a labelled placeholder rather than as nothing.
struct ImageElement: Hashable {
    var id: String
    var frame: SlideFrame
    var src: String
    var driveFileID: String?
    var opacity: Double
    var tintColor: String?
    var tintStrength: Double
    /// Adjustments as *offsets from zero*, the way the web app's sliders store them: the renderer
    /// applies `1 + value / 100`, so `0` is the untouched image and `-100` is black. Not
    /// percentages of the original, which is what the names suggest and what would make every
    /// stored `0` mean "invisible".
    var brightness: Double
    var contrast: Double
    var saturation: Double
    /// Positive warms the image (sepia and a hue shift), negative cools it.
    var warmth: Double
    /// `"cover"`, `"contain"` or `"fill"`.
    var objectFit: String
    var animation: ElementAnimation?
    var unknownFields: UnknownFields

    init(id: String = SlideID.make(), frame: SlideFrame, src: String, driveFileID: String? = nil,
         opacity: Double = 1, tintColor: String? = nil, tintStrength: Double = 0,
         brightness: Double = 0, contrast: Double = 0, saturation: Double = 0,
         warmth: Double = 0, objectFit: String = "cover", animation: ElementAnimation? = nil,
         unknownFields: UnknownFields = UnknownFields()) {
        self.id = id
        self.frame = frame
        self.src = src
        self.driveFileID = driveFileID
        self.opacity = opacity
        self.tintColor = tintColor
        self.tintStrength = tintStrength
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.warmth = warmth
        self.objectFit = objectFit
        self.animation = animation
        self.unknownFields = unknownFields
    }

    /// The Drive file id this image is a reference to, if it is one.
    var driveReference: String? {
        driveFileID ?? (src.hasPrefix(Self.drivePrefix) ? String(src.dropFirst(Self.drivePrefix.count)) : nil)
    }

    static let drivePrefix = "neutrino-drive:"
}

// MARK: - OpaqueElement

/// An element of a kind this app does not model — a live sheet embed, a video, a diagram, or
/// whatever a later web release invents.
///
/// Kept whole rather than dropped, for the reason ``JSONValue`` exists: a phone that cannot render
/// a spreadsheet embed must still not be the thing that deletes it. Geometry is the one part read
/// and written, so the placeholder lands where the real element is and can be moved with the rest of
/// the slide; nothing else about it is touched.
struct OpaqueElement: Hashable {

    private(set) var values: [String: JSONValue]

    init(_ values: [String: JSONValue]) {
        self.values = values
    }

    var id: String { values["id"]?.stringValue ?? "" }

    /// The element's `type`, for the placeholder's label.
    var kind: String { values["type"]?.stringValue ?? "unknown" }

    /// The stored box, when the element has one. A `line`-shaped unknown element has endpoints
    /// instead and is left where it is.
    var frame: SlideFrame? {
        guard let x = values["x"]?.numberValue, let y = values["y"]?.numberValue,
              let w = values["w"]?.numberValue, let h = values["h"]?.numberValue else { return nil }
        return SlideFrame(x: x, y: y, w: w, h: h)
    }

    mutating func setFrame(_ frame: SlideFrame) {
        guard self.frame != nil else { return }
        values["x"] = .number(frame.x)
        values["y"] = .number(frame.y)
        values["w"] = .number(frame.w)
        values["h"] = .number(frame.h)
    }

    /// A new id, for Duplicate. Everything else is carried across untouched.
    func withNewID(_ id: String) -> OpaqueElement {
        var copy = self
        copy.values["id"] = .string(id)
        return copy
    }

    /// What a placeholder should say this is.
    var displayName: String {
        switch kind {
        case "sheetEmbed": return "Spreadsheet"
        case "video":      return "Video"
        case "diagram":    return "Diagram"
        default:           return kind.capitalized
        }
    }

    var iconName: String {
        switch kind {
        case "sheetEmbed": return "tablecells"
        case "video":      return "play.rectangle"
        case "diagram":    return "flowchart"
        default:           return "square.on.square.dashed"
        }
    }
}

// MARK: - SlideElement

/// One thing on a slide.
enum SlideElement: Hashable {
    case text(TextElement)
    case shape(ShapeElement)
    case line(LineElement)
    case image(ImageElement)
    case opaque(OpaqueElement)

    // MARK: - Identity

    var id: String {
        switch self {
        case .text(let element):   return element.id
        case .shape(let element):  return element.id
        case .line(let element):   return element.id
        case .image(let element):  return element.id
        case .opaque(let element): return element.id
        }
    }

    /// The element's `type` on the wire.
    var kind: String {
        switch self {
        case .text:                return "text"
        case .shape:               return "shape"
        case .line:                return "line"
        case .image:               return "image"
        case .opaque(let element): return element.kind
        }
    }

    // MARK: - Geometry

    /// Where the element sits, in canvas percent. Nil only for an unmodelled element that stores no
    /// box — there is nowhere to draw it and nothing to move.
    var frame: SlideFrame? {
        switch self {
        case .text(let element):   return element.frame
        case .shape(let element):  return element.frame
        case .line(let element):   return element.frame
        case .image(let element):  return element.frame
        case .opaque(let element): return element.frame
        }
    }

    /// The same element moved or resized. A frame is clamped to the canvas by
    /// ``SlideFrame/clampedToCanvas()`` at the call site, not here: the editor clamps a drag, and a
    /// layout is free to place an element wherever the web app placed it.
    func withFrame(_ frame: SlideFrame) -> SlideElement {
        switch self {
        case .text(var element):
            element.frame = frame
            return .text(element)
        case .shape(var element):
            element.frame = frame
            return .shape(element)
        case .line(var element):
            element.setFrame(frame)
            return .line(element)
        case .image(var element):
            element.frame = frame
            return .image(element)
        case .opaque(var element):
            element.setFrame(frame)
            return .opaque(element)
        }
    }

    /// A copy under a new id, for Duplicate and for cloning a slide.
    func withNewID(_ id: String = SlideID.make()) -> SlideElement {
        switch self {
        case .text(var element):
            element.id = id
            return .text(element)
        case .shape(var element):
            element.id = id
            return .shape(element)
        case .line(var element):
            element.id = id
            return .line(element)
        case .image(var element):
            element.id = id
            return .image(element)
        case .opaque(let element):
            return .opaque(element.withNewID(id))
        }
    }

    // MARK: - Convenience

    var text: TextElement? {
        if case .text(let element) = self { return element }
        return nil
    }

    var shape: ShapeElement? {
        if case .shape(let element) = self { return element }
        return nil
    }

    var line: LineElement? {
        if case .line(let element) = self { return element }
        return nil
    }

    var image: ImageElement? {
        if case .image(let element) = self { return element }
        return nil
    }

    /// True for the kinds this app renders for real. An opaque element draws a placeholder, so its
    /// styling controls are hidden rather than shown doing nothing.
    var isModelled: Bool {
        if case .opaque = self { return false }
        return true
    }

    /// The plain text this element contributes to a search or an outline.
    var plainText: String? {
        text?.content
    }

    var displayName: String {
        switch self {
        case .text(let element):
            let trimmed = element.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Text" : String(trimmed.prefix(24))
        case .shape(let element):  return ShapeCatalog.label(for: element.shape)
        case .line:                return "Line"
        case .image:               return "Image"
        case .opaque(let element): return element.displayName
        }
    }

    var iconName: String {
        switch self {
        case .text:                return "textformat"
        case .shape:               return "square.on.circle"
        case .line:                return "line.diagonal"
        case .image:               return "photo"
        case .opaque(let element): return element.iconName
        }
    }
}

// MARK: - SlideElement + Codable

extension SlideElement: Codable {

    private enum TypeKey: String, CodingKey { case type }

    init(from decoder: any Decoder) throws {
        let kind = try decoder.container(keyedBy: TypeKey.self)
            .decodeIfPresent(String.self, forKey: .type) ?? ""
        switch kind {
        case "text":  self = .text(try TextElement(from: decoder))
        case "shape": self = .shape(try ShapeElement(from: decoder))
        case "line":  self = .line(try LineElement(from: decoder))
        case "image": self = .image(try ImageElement(from: decoder))
        default:
            // Everything else — including an element with no `type` at all — is kept verbatim.
            let values = try [String: JSONValue](from: decoder)
            self = .opaque(OpaqueElement(values))
        }
    }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .text(let element):   try element.encode(to: encoder)
        case .shape(let element):  try element.encode(to: encoder)
        case .line(let element):   try element.encode(to: encoder)
        case .image(let element):  try element.encode(to: encoder)
        case .opaque(let element): try element.values.encode(to: encoder)
        }
    }
}

// MARK: - TextElement + Codable

extension TextElement: Codable {

    static let knownKeys: Set<String> = ["id", "type", "x", "y", "w", "h", "content", "style",
                                         "animation"]

    private enum CodingKeys: String, CodingKey {
        case id, type, x, y, w, h, content, style, animation
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? SlideID.make()
        frame = SlideFrame(
            x: try container.decodeIfPresent(Double.self, forKey: .x) ?? 0,
            y: try container.decodeIfPresent(Double.self, forKey: .y) ?? 0,
            w: try container.decodeIfPresent(Double.self, forKey: .w) ?? 80,
            h: try container.decodeIfPresent(Double.self, forKey: .h) ?? 15
        )
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        style = try container.decodeIfPresent(TextStyle.self, forKey: .style) ?? TextStyle()
        animation = try container.decodeIfPresent(ElementAnimation.self, forKey: .animation)
        unknownFields = try UnknownFields(from: decoder, excluding: Self.knownKeys)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode("text", forKey: .type)
        try container.encode(frame.x, forKey: .x)
        try container.encode(frame.y, forKey: .y)
        try container.encode(frame.w, forKey: .w)
        try container.encode(frame.h, forKey: .h)
        try container.encode(content, forKey: .content)
        try container.encode(style, forKey: .style)
        try container.encodeIfPresent(animation, forKey: .animation)
        try unknownFields.encode(to: encoder, excluding: Self.knownKeys)
    }
}

// MARK: - ShapeElement + Codable

extension ShapeElement: Codable {

    static let knownKeys: Set<String> = ["id", "type", "shape", "x", "y", "w", "h", "fill",
                                         "stroke", "strokeWidth", "strokeDash", "animation"]

    private enum CodingKeys: String, CodingKey {
        case id, type, shape, x, y, w, h, fill, stroke, strokeWidth, strokeDash, animation
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? SlideID.make()
        shape = try container.decodeIfPresent(String.self, forKey: .shape) ?? "rect"
        frame = SlideFrame(
            x: try container.decodeIfPresent(Double.self, forKey: .x) ?? 0,
            y: try container.decodeIfPresent(Double.self, forKey: .y) ?? 0,
            w: try container.decodeIfPresent(Double.self, forKey: .w) ?? 20,
            h: try container.decodeIfPresent(Double.self, forKey: .h) ?? 20
        )
        fill = try container.decodeIfPresent(String.self, forKey: .fill) ?? "#818cf8"
        stroke = try container.decodeIfPresent(String.self, forKey: .stroke) ?? "transparent"
        strokeWidth = try container.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? 0
        strokeDash = try container.decodeIfPresent(String.self, forKey: .strokeDash)
        animation = try container.decodeIfPresent(ElementAnimation.self, forKey: .animation)
        unknownFields = try UnknownFields(from: decoder, excluding: Self.knownKeys)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode("shape", forKey: .type)
        try container.encode(shape, forKey: .shape)
        try container.encode(frame.x, forKey: .x)
        try container.encode(frame.y, forKey: .y)
        try container.encode(frame.w, forKey: .w)
        try container.encode(frame.h, forKey: .h)
        try container.encode(fill, forKey: .fill)
        try container.encode(stroke, forKey: .stroke)
        try container.encode(strokeWidth, forKey: .strokeWidth)
        try container.encodeIfPresent(strokeDash, forKey: .strokeDash)
        try container.encodeIfPresent(animation, forKey: .animation)
        try unknownFields.encode(to: encoder, excluding: Self.knownKeys)
    }
}

// MARK: - LineElement + Codable

extension LineElement: Codable {

    static let knownKeys: Set<String> = ["id", "type", "x1", "y1", "x2", "y2", "stroke",
                                         "strokeWidth", "strokeDash", "startArrow", "endArrow",
                                         "animation"]

    private enum CodingKeys: String, CodingKey {
        case id, type, x1, y1, x2, y2, stroke, strokeWidth, strokeDash, startArrow, endArrow
        case animation
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? SlideID.make()
        x1 = try container.decodeIfPresent(Double.self, forKey: .x1) ?? 10
        y1 = try container.decodeIfPresent(Double.self, forKey: .y1) ?? 50
        x2 = try container.decodeIfPresent(Double.self, forKey: .x2) ?? 90
        y2 = try container.decodeIfPresent(Double.self, forKey: .y2) ?? 50
        stroke = try container.decodeIfPresent(String.self, forKey: .stroke) ?? "#1f2937"
        strokeWidth = try container.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? 2
        strokeDash = try container.decodeIfPresent(String.self, forKey: .strokeDash)
        startArrow = try container.decodeIfPresent(String.self, forKey: .startArrow)
        endArrow = try container.decodeIfPresent(String.self, forKey: .endArrow)
        animation = try container.decodeIfPresent(ElementAnimation.self, forKey: .animation)
        unknownFields = try UnknownFields(from: decoder, excluding: Self.knownKeys)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode("line", forKey: .type)
        try container.encode(x1, forKey: .x1)
        try container.encode(y1, forKey: .y1)
        try container.encode(x2, forKey: .x2)
        try container.encode(y2, forKey: .y2)
        try container.encode(stroke, forKey: .stroke)
        try container.encode(strokeWidth, forKey: .strokeWidth)
        try container.encodeIfPresent(strokeDash, forKey: .strokeDash)
        try container.encodeIfPresent(startArrow, forKey: .startArrow)
        try container.encodeIfPresent(endArrow, forKey: .endArrow)
        try container.encodeIfPresent(animation, forKey: .animation)
        try unknownFields.encode(to: encoder, excluding: Self.knownKeys)
    }
}

// MARK: - ImageElement + Codable

extension ImageElement: Codable {

    static let knownKeys: Set<String> = ["id", "type", "x", "y", "w", "h", "src", "driveFileId",
                                         "opacity", "tintColor", "tintStrength", "brightness",
                                         "contrast", "saturation", "warmth", "objectFit",
                                         "animation"]

    private enum CodingKeys: String, CodingKey {
        case id, type, x, y, w, h, src, opacity, tintColor, tintStrength, brightness, contrast
        case saturation, warmth, objectFit, animation
        case driveFileID = "driveFileId"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? SlideID.make()
        frame = SlideFrame(
            x: try container.decodeIfPresent(Double.self, forKey: .x) ?? 0,
            y: try container.decodeIfPresent(Double.self, forKey: .y) ?? 0,
            w: try container.decodeIfPresent(Double.self, forKey: .w) ?? 40,
            h: try container.decodeIfPresent(Double.self, forKey: .h) ?? 40
        )
        src = try container.decodeIfPresent(String.self, forKey: .src) ?? ""
        driveFileID = try container.decodeIfPresent(String.self, forKey: .driveFileID)
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        tintColor = try container.decodeIfPresent(String.self, forKey: .tintColor)
        tintStrength = try container.decodeIfPresent(Double.self, forKey: .tintStrength) ?? 0
        brightness = try container.decodeIfPresent(Double.self, forKey: .brightness) ?? 0
        contrast = try container.decodeIfPresent(Double.self, forKey: .contrast) ?? 0
        saturation = try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 0
        warmth = try container.decodeIfPresent(Double.self, forKey: .warmth) ?? 0
        objectFit = try container.decodeIfPresent(String.self, forKey: .objectFit) ?? "cover"
        animation = try container.decodeIfPresent(ElementAnimation.self, forKey: .animation)
        unknownFields = try UnknownFields(from: decoder, excluding: Self.knownKeys)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode("image", forKey: .type)
        try container.encode(frame.x, forKey: .x)
        try container.encode(frame.y, forKey: .y)
        try container.encode(frame.w, forKey: .w)
        try container.encode(frame.h, forKey: .h)
        try container.encode(src, forKey: .src)
        try container.encodeIfPresent(driveFileID, forKey: .driveFileID)
        try container.encode(opacity, forKey: .opacity)
        try container.encodeIfPresent(tintColor, forKey: .tintColor)
        try container.encode(tintStrength, forKey: .tintStrength)
        try container.encode(brightness, forKey: .brightness)
        try container.encode(contrast, forKey: .contrast)
        try container.encode(saturation, forKey: .saturation)
        try container.encode(warmth, forKey: .warmth)
        try container.encode(objectFit, forKey: .objectFit)
        try container.encodeIfPresent(animation, forKey: .animation)
        try unknownFields.encode(to: encoder, excluding: Self.knownKeys)
    }
}

// MARK: - SlideBackground

/// What is painted behind a slide's elements.
///
/// `type` is a string rather than an enum for the reason ``TextStyle/align`` is: a background kind
/// this build does not draw must survive a save. An unrecognised kind falls back to the theme's
/// background colour on screen and is written back exactly as it arrived.
struct SlideBackground: Hashable {
    /// `"color"`, `"gradient"` or `"image"`.
    var type: String
    /// A CSS colour, a CSS gradient function, or an image URL / `neutrino-drive:` reference.
    var value: String
    /// `"cover"`, `"contain"` or `"fill"`, for `image`.
    var objectFit: String?
    var unknownFields: UnknownFields

    init(type: String, value: String, objectFit: String? = nil,
         unknownFields: UnknownFields = UnknownFields()) {
        self.type = type
        self.value = value
        self.objectFit = objectFit
        self.unknownFields = unknownFields
    }

    static func color(_ value: String) -> SlideBackground {
        SlideBackground(type: "color", value: value)
    }

    static func gradient(_ value: String) -> SlideBackground {
        SlideBackground(type: "gradient", value: value)
    }

    static func image(_ value: String, objectFit: String = "cover") -> SlideBackground {
        SlideBackground(type: "image", value: value, objectFit: objectFit)
    }

    var isColor: Bool { type == "color" }
    var isGradient: Bool { type == "gradient" }
    var isImage: Bool { type == "image" }
}

// MARK: - SlideBackground + Codable

extension SlideBackground: Codable {

    static let knownKeys: Set<String> = ["type", "value", "objectFit"]

    private enum CodingKeys: String, CodingKey {
        case type, value, objectFit
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "color"
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? "#ffffff"
        objectFit = try container.decodeIfPresent(String.self, forKey: .objectFit)
        unknownFields = try UnknownFields(from: decoder, excluding: Self.knownKeys)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(value, forKey: .value)
        try container.encodeIfPresent(objectFit, forKey: .objectFit)
        try unknownFields.encode(to: encoder, excluding: Self.knownKeys)
    }
}

// MARK: - Slide

/// One slide: its background, what is on it, its speaker notes, and how it arrives.
struct Slide: Hashable {

    var id: String
    var background: SlideBackground
    var elements: [SlideElement]
    var notes: String
    /// A ``SlideTransition`` raw value. Stored as a string so a transition added on the web is not
    /// lost by a save made here.
    var transition: String
    var unknownFields: UnknownFields

    init(id: String = SlideID.make(),
         background: SlideBackground = .color("#ffffff"),
         elements: [SlideElement] = [],
         notes: String = "",
         transition: String = SlideTransition.fade.rawValue,
         unknownFields: UnknownFields = UnknownFields()) {
        self.id = id
        self.background = background
        self.elements = elements
        self.notes = notes
        self.transition = transition
        self.unknownFields = unknownFields
    }

    // MARK: - Computed

    func element(id: String) -> SlideElement? {
        elements.first { $0.id == id }
    }

    func index(ofElement id: String) -> Int? {
        elements.firstIndex { $0.id == id }
    }

    /// The largest text on the slide, which is what a thumbnail and the outline use as its title.
    /// Nil when the slide carries no text at all.
    var title: String? {
        elements
            .compactMap(\.text)
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .max { $0.style.fontSize < $1.style.fontSize }?
            .content
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every word on the slide, notes included — the same flattening the web app's
    /// `extractSlideText` does for the search index.
    var plainText: String {
        var parts = elements.compactMap(\.plainText)
        if !notes.isEmpty { parts.append(notes) }
        return parts.joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A copy of the slide with fresh ids throughout, for Duplicate.
    ///
    /// The elements are re-identified too, not just the slide: two slides holding elements with the
    /// same id would make every by-id lookup in the editor ambiguous.
    func duplicated() -> Slide {
        var copy = self
        copy.id = SlideID.make()
        copy.elements = elements.map { $0.withNewID() }
        return copy
    }
}

// MARK: - Slide + Codable

extension Slide: Codable {

    static let knownKeys: Set<String> = ["id", "background", "elements", "notes", "transition"]

    private enum CodingKeys: String, CodingKey {
        case id, background, elements, notes, transition
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? SlideID.make()
        background = try container.decodeIfPresent(SlideBackground.self, forKey: .background)
            ?? .color("#ffffff")
        elements = try container.decodeIfPresent([SlideElement].self, forKey: .elements) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        transition = try container.decodeIfPresent(String.self, forKey: .transition)
            ?? SlideTransition.none.rawValue
        unknownFields = try UnknownFields(from: decoder, excluding: Self.knownKeys)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(background, forKey: .background)
        try container.encode(elements, forKey: .elements)
        try container.encode(notes, forKey: .notes)
        try container.encode(transition, forKey: .transition)
        try unknownFields.encode(to: encoder, excluding: Self.knownKeys)
    }
}

// MARK: - SlideMaster

/// The title and body styles a layout builds from, mirroring `SlideMaster` on the web.
struct SlideMaster: Codable, Hashable {
    var background: String
    var titleFontSize: Double
    var titleBold: Bool
    var titleColor: String
    var bodyFontSize: Double
    var bodyBold: Bool
    var bodyColor: String

    /// The web app's `makeDefaultMaster()`.
    static let `default` = SlideMaster(
        background: "#ffffff",
        titleFontSize: 40, titleBold: true, titleColor: "#1f2937",
        bodyFontSize: 24, bodyBold: false, bodyColor: "#6b7280"
    )
}

// MARK: - SlideDeck

/// A whole presentation: the `{"slides":[…],"theme":{…}}` document stored as `slide.json`.
///
/// This is the contract with the web app, so both directions matter — see ``decode(from:)``.
struct SlideDeck: Hashable {

    var slides: [Slide]
    var theme: SlideTheme
    /// Optional on the wire, and left absent when it was absent: a deck that never had a master
    /// should not gain one just because a phone opened it.
    var master: SlideMaster?

    /// Top-level keys this app does not model, preserved for the reason ``JSONValue`` exists.
    var unknownFields: UnknownFields

    init(slides: [Slide] = [], theme: SlideTheme = .default, master: SlideMaster? = nil,
         unknownFields: UnknownFields = UnknownFields()) {
        self.slides = slides
        self.theme = theme
        self.master = master
        self.unknownFields = unknownFields
    }

    /// The deck the web editor shows for a new file, and what the server seeds `slide.json` with
    /// (`EMPTY_SLIDES_CONTENT` in `src/drive/storage/native_types.rs`): one title slide.
    static var empty: SlideDeck {
        SlideDeck(
            slides: [
                Slide(
                    background: .color("#ffffff"),
                    elements: [
                        .text(TextElement(
                            frame: SlideFrame(x: 10, y: 30, w: 80, h: 20),
                            content: "Click to add title",
                            style: TextStyle(fontSize: 40, bold: true, color: "#1f2937",
                                             align: "center")
                        )),
                        .text(TextElement(
                            frame: SlideFrame(x: 15, y: 55, w: 70, h: 15),
                            content: "Click to add subtitle",
                            style: TextStyle(fontSize: 24, color: "#6b7280", align: "center")
                        )),
                    ],
                    transition: SlideTransition.fade.rawValue
                ),
            ],
            theme: .default,
            master: .default
        )
    }

    // MARK: - Computed

    /// The master a layout or the theme should build from. A deck with no stored master uses the
    /// default one rather than nothing, which is what the web app's `master ?? makeDefaultMaster()`
    /// does at every call site.
    var effectiveMaster: SlideMaster { master ?? .default }

    func slide(id: String) -> Slide? {
        slides.first { $0.id == id }
    }

    func index(ofSlide id: String) -> Int? {
        slides.firstIndex { $0.id == id }
    }
}

// MARK: - SlideDeck + Codable

extension SlideDeck: Codable {

    static let knownKeys: Set<String> = ["slides", "theme", "master"]

    private enum CodingKeys: String, CodingKey {
        case slides, theme, master
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slides = try container.decodeIfPresent([Slide].self, forKey: .slides) ?? []
        theme = try container.decodeIfPresent(SlideTheme.self, forKey: .theme) ?? .default
        master = try container.decodeIfPresent(SlideMaster.self, forKey: .master)
        unknownFields = try UnknownFields(from: decoder, excluding: Self.knownKeys)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(slides, forKey: .slides)
        try container.encode(theme, forKey: .theme)
        try container.encodeIfPresent(master, forKey: .master)
        try unknownFields.encode(to: encoder, excluding: Self.knownKeys)
    }
}

// MARK: - SlideDeck + Codec

extension SlideDeck {

    /// Decodes a stored deck body, tolerating what the server can hand back.
    ///
    /// Unlike a spreadsheet's `sheet.json`, the seeded body of a new presentation is already in
    /// this shape — `EMPTY_SLIDES_CONTENT` is a real one-slide deck — so there is no second format
    /// to convert. What still has to be tolerated is a body that will not parse at all (a truncated
    /// upload, a file that was never a deck) and a parsed deck with no slides in it: both open as
    /// ``empty``, matching the web editor's `catch { … makeDefaultPresentation() }`.
    ///
    /// A deck that *is* readable is never replaced, however little of it this app understands. Only
    /// a failure to parse produces a default, and only then because there is nothing else to show.
    static func decode(from data: Data) -> SlideDeck {
        guard let deck = try? JSONDecoder().decode(SlideDeck.self, from: data),
              !deck.slides.isEmpty else {
            return .empty
        }
        return deck
    }

    /// Encodes the deck as the web app writes it.
    ///
    /// `.sortedKeys` is what makes a round trip byte-stable: `JSONEncoder` orders dictionary keys
    /// arbitrarily otherwise, so the same deck saved twice would produce two different blobs, and
    /// the fixtures in `PresentationCodecTests` could not assert anything. `.withoutEscapingSlashes`
    /// keeps a `data:` image URL readable rather than writing `data:image\/png`.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

// MARK: - SlideID

/// Ids for slides and elements.
///
/// Eight base-36 characters, which is what the web app's `uid()` produces
/// (`Math.random().toString(36).slice(2, 10)`). Matching it is not cosmetic: the two clients write
/// into the same file, and an id shape that stood out would make it obvious which device touched a
/// deck — but more practically, the web app's `key` props and its `pptxExport` both assume a short
/// id, and a 36-character UUID would bloat every element in a large deck for nothing.
enum SlideID {

    private static let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")

    static func make() -> String {
        String((0..<8).map { _ in alphabet.randomElement() ?? "0" })
    }
}
