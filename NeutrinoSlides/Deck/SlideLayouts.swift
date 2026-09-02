import Foundation

// MARK: - SlideLayout

/// A starting arrangement for a slide, mirroring `SLIDE_LAYOUTS` in the web app's
/// `slideEditorConstants.ts` — the same ten layouts, the same geometry, the same placeholder text.
///
/// Applying one **replaces** the slide's elements. That is what it does on the web too, and it is
/// why the editor puts it behind undo rather than behind a confirmation: an undoable replace is
/// quicker to recover from than a dialog is to read.
struct SlideLayout: Identifiable, Hashable {

    let id: String
    let name: String
    /// Rectangles for the gallery card, in the web app's 160×90 preview space.
    let preview: [PreviewRect]
    /// Builds the elements, styled from the deck's theme and master.
    ///
    /// A closure rather than stored elements because a layout is a *recipe*: "a title at the
    /// master's title size in the master's title colour", not "a 40pt slate-grey title". Applying
    /// the same layout under two themes has to produce two differently styled slides.
    let makeElements: (SlideTheme, SlideMaster) -> [SlideElement]

    // MARK: - Hashable

    /// Layouts are identified by `id`; the closure is not comparable and does not need to be, since
    /// two layouts with the same id are the same layout.
    static func == (lhs: SlideLayout, rhs: SlideLayout) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: - PreviewRect

    /// One rectangle in the 160×90 layout preview.
    struct PreviewRect: Hashable {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
        /// A ``PreviewInk`` role rather than a colour, so the card follows Dark Mode instead of
        /// painting the web app's light-mode greys onto a dark sheet.
        let ink: PreviewInk

        init(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ ink: PreviewInk) {
            self.x = x
            self.y = y
            self.w = w
            self.h = h
            self.ink = ink
        }
    }

    /// What a preview rectangle stands for. The web app hardcodes four hex values (`TITLE_PV`,
    /// `BODY_PV`, `BOX_PV`, `SUB_PV`); naming the roles instead is what lets the same preview be
    /// drawn legibly in either appearance.
    enum PreviewInk: Hashable {
        case title, body, box, subtitle, accent, alternate
    }

    /// The preview's coordinate space, so a card can scale it to whatever size it is drawn at.
    static let previewSize = (width: 160.0, height: 90.0)
}

// MARK: - SlideLayouts

/// The layout gallery.
enum SlideLayouts {

    /// Rounded the way the web app rounds — `Math.round` on a scaled font size — so a layout
    /// applied on a phone stores the same numbers it would have on a laptop.
    private static func scaled(_ size: Double, _ factor: Double) -> Double {
        (size * factor).rounded()
    }

    /// A text element built from a master's title or body style.
    private static func text(_ frame: SlideFrame, _ content: String, size: Double, bold: Bool,
                             color: String, align: String, italic: Bool = false) -> SlideElement {
        .text(TextElement(
            frame: frame,
            content: content,
            style: TextStyle(fontSize: size, bold: bold, italic: italic, color: color, align: align)
        ))
    }

    /// The accent rule several layouts draw under their title.
    private static func rule(_ frame: SlideFrame, color: String) -> SlideElement {
        .shape(ShapeElement(shape: "rect", frame: frame, fill: color, stroke: "transparent",
                            strokeWidth: 0))
    }

    static let all: [SlideLayout] = [
        SlideLayout(id: "blank", name: "Blank", preview: [], makeElements: { _, _ in [] }),

        SlideLayout(
            id: "title-slide",
            name: "Title Slide",
            preview: [
                .init(16, 24, 128, 14, .title),
                .init(36, 44, 88, 7, .subtitle),
            ],
            makeElements: { _, master in
                [
                    text(SlideFrame(x: 10, y: 25, w: 80, h: 22), "Presentation Title",
                         size: master.titleFontSize, bold: master.titleBold,
                         color: master.titleColor, align: "center"),
                    text(SlideFrame(x: 15, y: 53, w: 70, h: 12), "Subtitle or author name",
                         size: master.bodyFontSize, bold: false,
                         color: master.bodyColor, align: "center"),
                ]
            }
        ),

        SlideLayout(
            id: "title-content",
            name: "Title & Content",
            preview: [
                .init(8, 5, 96, 9, .title),
                .init(8, 16, 144, 1, .box),
                .init(8, 21, 144, 5, .body),
                .init(8, 30, 120, 5, .body),
                .init(8, 39, 132, 5, .body),
                .init(8, 48, 100, 5, .body),
                .init(8, 57, 112, 5, .body),
                .init(8, 66, 88, 5, .body),
            ],
            makeElements: { theme, master in
                [
                    text(SlideFrame(x: 5, y: 5, w: 90, h: 14), "Slide Title",
                         size: master.titleFontSize, bold: master.titleBold,
                         color: master.titleColor, align: "left"),
                    rule(SlideFrame(x: 5, y: 20, w: 90, h: 1), color: theme.primaryColor),
                    text(SlideFrame(x: 5, y: 24, w: 90, h: 66), "Click to add content",
                         size: master.bodyFontSize, bold: master.bodyBold,
                         color: master.bodyColor, align: "left"),
                ]
            }
        ),

        SlideLayout(
            id: "title-only",
            name: "Title Only",
            preview: [
                .init(8, 5, 96, 9, .title),
                .init(8, 16, 144, 1, .box),
            ],
            makeElements: { theme, master in
                [
                    text(SlideFrame(x: 5, y: 5, w: 90, h: 16), "Slide Title",
                         size: master.titleFontSize, bold: master.titleBold,
                         color: master.titleColor, align: "left"),
                    rule(SlideFrame(x: 5, y: 22, w: 90, h: 1), color: theme.primaryColor),
                ]
            }
        ),

        SlideLayout(
            id: "section-header",
            name: "Section Header",
            preview: [
                .init(16, 26, 128, 16, .title),
                .init(40, 48, 80, 7, .subtitle),
            ],
            makeElements: { _, master in
                [
                    text(SlideFrame(x: 10, y: 30, w: 80, h: 26), "Section Title",
                         size: scaled(master.titleFontSize, 1.1), bold: true,
                         color: master.titleColor, align: "center"),
                    text(SlideFrame(x: 20, y: 60, w: 60, h: 12), "Section subtitle",
                         size: master.bodyFontSize, bold: false,
                         color: master.bodyColor, align: "center"),
                ]
            }
        ),

        SlideLayout(
            id: "two-column",
            name: "Two Column",
            preview: [
                .init(8, 5, 96, 9, .title),
                .init(8, 16, 144, 1, .box),
                .init(8, 21, 66, 5, .body),
                .init(8, 30, 56, 5, .body),
                .init(8, 39, 62, 5, .body),
                .init(8, 48, 50, 5, .body),
                .init(86, 21, 66, 5, .body),
                .init(86, 30, 56, 5, .body),
                .init(86, 39, 62, 5, .body),
                .init(86, 48, 50, 5, .body),
            ],
            makeElements: { theme, master in
                [
                    text(SlideFrame(x: 5, y: 5, w: 90, h: 14), "Two Column Layout",
                         size: master.titleFontSize, bold: master.titleBold,
                         color: master.titleColor, align: "center"),
                    rule(SlideFrame(x: 5, y: 20, w: 90, h: 1), color: theme.primaryColor),
                    text(SlideFrame(x: 5, y: 24, w: 43, h: 66),
                         "Left Column\n\n• Point one\n• Point two\n• Point three",
                         size: master.bodyFontSize, bold: master.bodyBold,
                         color: master.bodyColor, align: "left"),
                    text(SlideFrame(x: 52, y: 24, w: 43, h: 66),
                         "Right Column\n\n• Point one\n• Point two\n• Point three",
                         size: master.bodyFontSize, bold: master.bodyBold,
                         color: master.bodyColor, align: "left"),
                ]
            }
        ),

        SlideLayout(
            id: "comparison",
            name: "Comparison",
            preview: [
                .init(8, 4, 96, 8, .title),
                .init(8, 15, 66, 7, .accent),
                .init(86, 15, 66, 7, .alternate),
                .init(8, 26, 60, 4, .body),
                .init(8, 34, 50, 4, .body),
                .init(8, 42, 55, 4, .body),
                .init(8, 50, 46, 4, .body),
                .init(86, 26, 60, 4, .body),
                .init(86, 34, 50, 4, .body),
                .init(86, 42, 55, 4, .body),
                .init(86, 50, 46, 4, .body),
            ],
            makeElements: { theme, master in
                [
                    text(SlideFrame(x: 5, y: 4, w: 90, h: 13), "Comparison",
                         size: master.titleFontSize, bold: master.titleBold,
                         color: master.titleColor, align: "center"),
                    // The `+ "33"` / `+ "22"` are the web app's own eight-digit hex alphas, kept
                    // verbatim: the two panels are the theme colours at low opacity, and computing
                    // a blend here instead would give a panel a different colour in each client.
                    .shape(ShapeElement(shape: "rect", frame: SlideFrame(x: 5, y: 19, w: 43, h: 73),
                                        fill: theme.accentColor + "33", stroke: theme.accentColor,
                                        strokeWidth: 2)),
                    .shape(ShapeElement(shape: "rect", frame: SlideFrame(x: 52, y: 19, w: 43, h: 73),
                                        fill: theme.primaryColor + "22", stroke: theme.primaryColor,
                                        strokeWidth: 2)),
                    text(SlideFrame(x: 5, y: 20, w: 43, h: 12), "Option A",
                         size: scaled(master.bodyFontSize, 1.1), bold: true,
                         color: theme.accentColor, align: "center"),
                    text(SlideFrame(x: 52, y: 20, w: 43, h: 12), "Option B",
                         size: scaled(master.bodyFontSize, 1.1), bold: true,
                         color: theme.primaryColor, align: "center"),
                    text(SlideFrame(x: 7, y: 34, w: 39, h: 55),
                         "+ Advantage one\n+ Advantage two\n+ Advantage three",
                         size: master.bodyFontSize, bold: master.bodyBold,
                         color: master.bodyColor, align: "left"),
                    text(SlideFrame(x: 54, y: 34, w: 39, h: 55),
                         "+ Advantage one\n+ Advantage two\n+ Advantage three",
                         size: master.bodyFontSize, bold: master.bodyBold,
                         color: master.bodyColor, align: "left"),
                ]
            }
        ),

        SlideLayout(
            id: "content-caption",
            name: "Content & Caption",
            preview: [
                .init(8, 5, 96, 9, .title),
                .init(8, 16, 144, 1, .box),
                .init(8, 20, 104, 62, .box),
                .init(118, 20, 34, 9, .accent),
                .init(118, 33, 34, 4, .body),
                .init(118, 41, 28, 4, .body),
                .init(118, 49, 32, 4, .body),
            ],
            makeElements: { theme, master in
                [
                    text(SlideFrame(x: 5, y: 5, w: 90, h: 13), "Slide Title",
                         size: master.titleFontSize, bold: master.titleBold,
                         color: master.titleColor, align: "left"),
                    rule(SlideFrame(x: 5, y: 20, w: 90, h: 1), color: theme.primaryColor),
                    text(SlideFrame(x: 5, y: 24, w: 65, h: 66), "Main content area",
                         size: master.bodyFontSize, bold: master.bodyBold,
                         color: master.bodyColor, align: "left"),
                    text(SlideFrame(x: 73, y: 24, w: 22, h: 14), "Caption",
                         size: scaled(master.bodyFontSize, 0.9), bold: true,
                         color: theme.primaryColor, align: "left"),
                    text(SlideFrame(x: 73, y: 40, w: 22, h: 50),
                         "Add a caption or supporting note here.",
                         size: scaled(master.bodyFontSize, 0.8), bold: false,
                         color: master.bodyColor, align: "left"),
                ]
            }
        ),

        SlideLayout(
            id: "big-statement",
            name: "Big Statement",
            preview: [
                .init(12, 25, 136, 20, .title),
                .init(52, 52, 56, 7, .subtitle),
            ],
            makeElements: { _, master in
                [
                    text(SlideFrame(x: 10, y: 22, w: 80, h: 30), "Your Big Statement",
                         size: scaled(master.titleFontSize, 1.2), bold: true,
                         color: master.titleColor, align: "center"),
                    text(SlideFrame(x: 20, y: 58, w: 60, h: 14), "Supporting context",
                         size: master.bodyFontSize, bold: false,
                         color: master.bodyColor, align: "center"),
                ]
            }
        ),

        SlideLayout(
            id: "quote",
            name: "Quote",
            preview: [
                .init(10, 10, 18, 22, .title),
                .init(10, 28, 140, 28, .body),
                .init(50, 63, 60, 6, .subtitle),
            ],
            makeElements: { _, master in
                [
                    text(SlideFrame(x: 10, y: 14, w: 16, h: 22), "\u{201C}",
                         size: 80, bold: true, color: master.titleColor, align: "left"),
                    text(SlideFrame(x: 10, y: 28, w: 80, h: 36), "The quote goes here.",
                         size: scaled(master.bodyFontSize, 1.2), bold: false,
                         color: master.bodyColor, align: "center", italic: true),
                    text(SlideFrame(x: 20, y: 68, w: 60, h: 12), "\u{2014} Attribution",
                         size: master.bodyFontSize, bold: false,
                         color: master.bodyColor, align: "center"),
                ]
            }
        ),
    ]

    static func layout(id: String) -> SlideLayout? {
        all.first { $0.id == id }
    }
}
