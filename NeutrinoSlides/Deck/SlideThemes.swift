import Foundation

// MARK: - SlideTheme

/// A deck's theme, as it is stored *inside* the deck — mirroring `Theme` in the web app's
/// `slideEditorTypes.ts`.
///
/// Not the same shape as the theme records `/api/v1/slides/themes` returns: those are user-owned
/// rows with an id and a `gradientBackground` field, and applying one copies it into this shape
/// (see ``StoredSlideTheme/asDeckTheme``). The deck keeps its own copy on purpose — a deck emailed
/// to somebody whose account has never seen that theme still opens looking right.
struct SlideTheme: Hashable {

    var name: String
    var primaryColor: String
    var backgroundColor: String
    var textColor: String
    var accentColor: String
    var fontFamily: String
    /// A URL or `neutrino-drive:` reference. When set it wins over ``backgroundColor``.
    var backgroundImage: String?
    /// A CSS gradient. When set it wins over ``backgroundColor``.
    var gradient: String?
    /// A ``SlideTransition`` raw value, given to every slide the theme is applied to.
    var defaultTransition: String

    var unknownFields: UnknownFields

    init(name: String, primaryColor: String, backgroundColor: String, textColor: String,
         accentColor: String, fontFamily: String = "Inter", backgroundImage: String? = nil,
         gradient: String? = nil, defaultTransition: String = SlideTransition.fade.rawValue,
         unknownFields: UnknownFields = UnknownFields()) {
        self.name = name
        self.primaryColor = primaryColor
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.accentColor = accentColor
        self.fontFamily = fontFamily
        self.backgroundImage = backgroundImage
        self.gradient = gradient
        self.defaultTransition = defaultTransition
        self.unknownFields = unknownFields
    }

    // MARK: - Derived

    /// The background a slide gets when this theme is applied, in the web app's order of
    /// precedence: image, then gradient, then the flat colour.
    ///
    /// A gradient is written under `type: "color"` — which looks wrong and is deliberately kept:
    /// that is exactly what `applyTheme` in `SlideEditor.tsx` writes, the web renderer puts the
    /// value straight into a CSS `background`, and writing `type: "gradient"` here instead would
    /// produce decks the two clients disagree about.
    var slideBackground: SlideBackground {
        if let backgroundImage, !backgroundImage.isEmpty {
            return .image(backgroundImage)
        }
        return .color(gradient ?? backgroundColor)
    }

    // MARK: - Presets

    /// The web app's `DEFAULT_THEME`, and what a deck with no theme of its own is read as.
    static let `default` = SlideTheme(
        name: "Default",
        primaryColor: "#4f46e5",
        backgroundColor: "#ffffff",
        textColor: "#1f2937",
        accentColor: "#818cf8",
        fontFamily: "Inter",
        defaultTransition: SlideTransition.fade.rawValue
    )

    /// The themes offered when `/api/v1/slides/themes` cannot be reached.
    ///
    /// Not a copy of the server's system themes — this app has no way to know what those are
    /// offline — but a small set that covers the cases a deck is usually restyled for: a light
    /// deck, a dark one, and a couple with some colour in them. The server's themes replace these
    /// the moment the list loads.
    static let builtIns: [SlideTheme] = [
        .default,
        SlideTheme(name: "Midnight", primaryColor: "#818cf8", backgroundColor: "#0f172a",
                   textColor: "#e2e8f0", accentColor: "#38bdf8",
                   defaultTransition: SlideTransition.fade.rawValue),
        SlideTheme(name: "Paper", primaryColor: "#b45309", backgroundColor: "#faf7f0",
                   textColor: "#3f3f46", accentColor: "#d97706",
                   defaultTransition: SlideTransition.dissolve.rawValue),
        SlideTheme(name: "Forest", primaryColor: "#15803d", backgroundColor: "#f0fdf4",
                   textColor: "#14532d", accentColor: "#4ade80",
                   defaultTransition: SlideTransition.fade.rawValue),
        SlideTheme(name: "Ink", primaryColor: "#e5e7eb", backgroundColor: "#111827",
                   textColor: "#f9fafb", accentColor: "#9ca3af",
                   defaultTransition: SlideTransition.slideRight.rawValue),
        SlideTheme(name: "Dusk", primaryColor: "#c084fc", backgroundColor: "#1a1a2e",
                   textColor: "#ede9fe", accentColor: "#f472b6",
                   gradient: "linear-gradient(135deg, #0f0c29 0%, #302b63 50%, #24243e 100%)",
                   defaultTransition: SlideTransition.fade.rawValue),
    ]
}

// MARK: - SlideTheme + Codable

extension SlideTheme: Codable {

    static let knownKeys: Set<String> = ["name", "primaryColor", "backgroundColor", "textColor",
                                         "accentColor", "fontFamily", "backgroundImage",
                                         "gradient", "defaultTransition"]

    private enum CodingKeys: String, CodingKey {
        case name, primaryColor, backgroundColor, textColor, accentColor, fontFamily
        case backgroundImage, gradient, defaultTransition
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = SlideTheme.default
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? fallback.name
        primaryColor = try container.decodeIfPresent(String.self, forKey: .primaryColor)
            ?? fallback.primaryColor
        backgroundColor = try container.decodeIfPresent(String.self, forKey: .backgroundColor)
            ?? fallback.backgroundColor
        textColor = try container.decodeIfPresent(String.self, forKey: .textColor)
            ?? fallback.textColor
        accentColor = try container.decodeIfPresent(String.self, forKey: .accentColor)
            ?? fallback.accentColor
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily)
            ?? fallback.fontFamily
        backgroundImage = try container.decodeIfPresent(String.self, forKey: .backgroundImage)
        gradient = try container.decodeIfPresent(String.self, forKey: .gradient)
        defaultTransition = try container.decodeIfPresent(String.self, forKey: .defaultTransition)
            ?? fallback.defaultTransition
        unknownFields = try UnknownFields(from: decoder, excluding: Self.knownKeys)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(primaryColor, forKey: .primaryColor)
        try container.encode(backgroundColor, forKey: .backgroundColor)
        try container.encode(textColor, forKey: .textColor)
        try container.encode(accentColor, forKey: .accentColor)
        try container.encode(fontFamily, forKey: .fontFamily)
        try container.encodeIfPresent(backgroundImage, forKey: .backgroundImage)
        try container.encodeIfPresent(gradient, forKey: .gradient)
        try container.encode(defaultTransition, forKey: .defaultTransition)
        try unknownFields.encode(to: encoder, excluding: Self.knownKeys)
    }
}

// MARK: - StoredSlideTheme

/// A theme record from `GET /api/v1/slides/themes` — a user-owned row rather than part of a deck.
///
/// The one place the two shapes disagree is the gradient: the row calls it `gradientBackground`,
/// the deck calls it `gradient`. That is the web app's `dbThemeToTheme`, translated.
struct StoredSlideTheme: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let primaryColor: String
    let backgroundColor: String
    let textColor: String
    let accentColor: String
    let fontFamily: String?
    let backgroundImage: String?
    let gradientBackground: String?
    let defaultTransition: String?
    /// True for the themes the server ships, false for one the user made on the web. Only used to
    /// group the gallery — this app does not create or edit theme records.
    let isSystem: Bool?

    /// The theme as a deck stores it.
    var asDeckTheme: SlideTheme {
        SlideTheme(name: name,
                   primaryColor: primaryColor,
                   backgroundColor: backgroundColor,
                   textColor: textColor,
                   accentColor: accentColor,
                   fontFamily: fontFamily ?? "Inter",
                   backgroundImage: backgroundImage,
                   gradient: gradientBackground,
                   defaultTransition: defaultTransition ?? SlideTransition.fade.rawValue)
    }
}

// MARK: - ThemeApplication

/// Applying a theme to a whole deck.
///
/// A pure function on the deck rather than a method on the editor, because it is the one operation
/// that touches every slide and every element: it is worth being able to assert what it changed —
/// and what it left alone — without an editor, a network, or a canvas.
enum ThemeApplication {

    /// Restyles `deck` with `theme`, exactly as the web app's `applyTheme` does:
    ///
    /// - every slide takes the theme's background and its default transition,
    /// - every text element takes the theme's text colour and font family,
    /// - every shape takes the theme's primary colour as its fill.
    ///
    /// Content is never touched — not the words, not the positions, not the sizes — and neither are
    /// images, lines, or the elements this app keeps opaquely. A theme is a palette, and a "restyle"
    /// that moved things would be a redesign the user did not ask for.
    static func apply(_ theme: SlideTheme, to deck: SlideDeck) -> SlideDeck {
        var updated = deck
        updated.theme = theme
        let background = theme.slideBackground
        updated.slides = deck.slides.map { slide in
            var slide = slide
            slide.background = background
            slide.transition = theme.defaultTransition
            slide.elements = slide.elements.map { element in
                switch element {
                case .text(var text):
                    text.style.color = theme.textColor
                    text.style.fontFamily = theme.fontFamily
                    return .text(text)
                case .shape(var shape):
                    shape.fill = theme.primaryColor
                    return .shape(shape)
                case .line, .image, .opaque:
                    return element
                }
            }
            return slide
        }
        return updated
    }

    /// Writes the master's background and text styles across every slide — the web app's "apply to
    /// all slides" in the Slide Master panel.
    ///
    /// Title and body are told apart by size, the same way the master itself defines them: the
    /// largest text on a slide is its title. Nothing else works on this format, which has no notion
    /// of a placeholder role — and it is what the layouts produce, since each builds its title from
    /// `master.titleFontSize`.
    static func applyMaster(_ master: SlideMaster, to deck: SlideDeck) -> SlideDeck {
        var updated = deck
        updated.master = master
        updated.slides = deck.slides.map { slide in
            var slide = slide
            slide.background = .color(master.background)
            let titleID = slide.elements
                .compactMap(\.text)
                .max { $0.style.fontSize < $1.style.fontSize }?
                .id
            slide.elements = slide.elements.map { element in
                guard case .text(var text) = element else { return element }
                let isTitle = text.id == titleID
                text.style.fontSize = isTitle ? master.titleFontSize : master.bodyFontSize
                text.style.bold = isTitle ? master.titleBold : master.bodyBold
                text.style.color = isTitle ? master.titleColor : master.bodyColor
                return .text(text)
            }
            return slide
        }
        return updated
    }
}
