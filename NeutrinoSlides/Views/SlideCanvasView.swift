import SwiftUI
import UIKit

// MARK: - SlideCanvasView

/// Draws one slide at whatever size it is given.
///
/// The single renderer behind every surface that shows a slide: the editor's canvas, the thumbnail
/// rail, the layout previews and presenter mode. One renderer rather than four is what keeps a
/// thumbnail an honest preview of the slide — the failure this avoids is the one where a deck looks
/// right in the rail and wrong on the projector.
///
/// Purely a renderer. Selection, handles, gestures and editing all live in ``DeckEditorView``,
/// which overlays them; nothing here knows the deck is being edited.
struct SlideCanvasView: View {

    // MARK: - Input

    let slide: Slide
    /// The deck's theme, for the fallback background when a slide's own is unreadable.
    let theme: SlideTheme
    /// The canvas size in points. Callers get it from ``SlideGeometry/canvasSize(fitting:)``.
    let size: CGSize
    /// Draws a hairline border around the canvas — wanted on a thumbnail, where a white slide on a
    /// white sheet is otherwise invisible, and not wanted when presenting.
    var showsBorder: Bool = false

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            SlideBackgroundView(background: slide.background, theme: theme)

            ForEach(slide.elements, id: \.id) { element in
                SlideElementView(element: element, canvasSize: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .overlay {
            if showsBorder {
                Rectangle()
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// A slide reads to VoiceOver as its text, in the order the elements are stacked — which is the
    /// order they were added, and the closest thing the format has to a reading order.
    private var accessibilityText: String {
        let text = slide.plainText
        return text.isEmpty ? "Empty slide" : text
    }
}

// MARK: - SlideBackgroundView

/// The slide's background: a colour, a CSS gradient, or an image.
///
/// The *value* decides how it is painted, not the declared type. A gradient is routinely stored
/// under `type: "color"` — that is what the web app's `applyTheme` writes and what its renderer
/// paints, since both end up in a CSS `background` — so keying off the type alone would show a flat
/// black slide where the web shows a gradient.
struct SlideBackgroundView: View {

    let background: SlideBackground
    let theme: SlideTheme

    var body: some View {
        switch content {
        case .gradient(let gradient):
            gradient.linearGradient
        case .color(let color):
            color
        case .image(let source):
            SlideImageView(source: source, objectFit: background.objectFit ?? "cover")
        }
    }

    private enum Content {
        case color(Color)
        case gradient(CSSColor.Gradient)
        case image(String)
    }

    private var content: Content {
        if background.isImage, !background.value.isEmpty {
            return .image(background.value)
        }
        if CSSColor.isGradient(background.value), let gradient = CSSColor.gradient(background.value) {
            return .gradient(gradient)
        }
        // The theme's own colour is the fallback rather than white: a deck whose theme is dark and
        // whose background string this build cannot read should stay dark, not flash white.
        return .color(CSSColor.color(background.value)
                      ?? CSSColor.color(theme.backgroundColor)
                      ?? .white)
    }
}

// MARK: - SlideElementView

/// One element, positioned in the canvas.
struct SlideElementView: View {

    let element: SlideElement
    let canvasSize: CGSize

    var body: some View {
        switch element {
        case .text(let text):
            TextElementView(element: text, canvasSize: canvasSize)
                .frame(width: rect(text.frame).width, height: rect(text.frame).height,
                       alignment: .topLeading)
                .offset(x: rect(text.frame).minX, y: rect(text.frame).minY)

        case .shape(let shape):
            ShapeElementView(element: shape, canvasSize: canvasSize)
                .frame(width: rect(shape.frame).width, height: rect(shape.frame).height)
                .offset(x: rect(shape.frame).minX, y: rect(shape.frame).minY)

        case .line(let line):
            // Drawn against the whole canvas rather than a box of its own: the endpoints are canvas
            // coordinates, and a line's bounding box is degenerate — zero-height for a horizontal
            // rule — so there is nothing to draw *inside*.
            LineElementView(element: line, canvasSize: canvasSize)
                .frame(width: canvasSize.width, height: canvasSize.height)

        case .image(let image):
            ImageElementView(element: image)
                .frame(width: rect(image.frame).width, height: rect(image.frame).height)
                .offset(x: rect(image.frame).minX, y: rect(image.frame).minY)

        case .opaque(let opaque):
            if let frame = opaque.frame {
                OpaqueElementView(element: opaque)
                    .frame(width: rect(frame).width, height: rect(frame).height)
                    .offset(x: rect(frame).minX, y: rect(frame).minY)
            }
        }
    }

    private func rect(_ frame: SlideFrame) -> CGRect {
        frame.rect(in: canvasSize)
    }
}

// MARK: - TextElementView

/// A text box.
///
/// Each line of `content` is a paragraph, matching the web renderer, which splits on `\n` and lays
/// the pieces out as separate rows. That is also what makes `spaceBefore` / `spaceAfter` and the
/// list markers land where they do: they are per-paragraph, not per-wrapped-line.
struct TextElementView: View {

    let element: TextElement
    let canvasSize: CGSize

    /// The web renderer's default. A deck that stores nothing takes it, so lines sit the same
    /// distance apart in both clients.
    private static let defaultLineHeight: Double = 1.3

    var body: some View {
        let style = element.style
        let size = SlideGeometry.fontSize(style.fontSize, canvasWidth: canvasSize.width)
        let lines = element.content.components(separatedBy: "\n")

        VStack(alignment: horizontalAlignment, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                paragraph(line, number: index + 1, size: size)
                    .padding(.top, index > 0 ? scaled(style.spaceBefore) : 0)
                    .padding(.bottom, index < lines.count - 1 ? scaled(style.spaceAfter) : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
        .font(Font(CSSColor.font(family: style.fontFamily, size: size,
                                 bold: style.bold, italic: style.italic)))
        .foregroundStyle(CSSColor.color(style.color) ?? .primary)
        .lineSpacing(max(0, (style.lineHeight ?? Self.defaultLineHeight) - 1) * size)
        .background(CSSColor.color(style.backgroundColor) ?? .clear)
        .shadow(color: shadowColor, radius: style.shadow == true ? size * 0.08 : 0,
                x: style.shadow == true ? size * 0.04 : 0,
                y: style.shadow == true ? size * 0.04 : 0)
    }

    // MARK: - Pieces

    @ViewBuilder
    private func paragraph(_ line: String, number: Int, size: CGFloat) -> some View {
        if let marker = listMarker(number: number) {
            HStack(alignment: .firstTextBaseline, spacing: size * 0.4) {
                Text(marker)
                    .accessibilityHidden(true)
                Text(displayed(line))
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
                    .modifier(TextDecorations(style: element.style))
            }
        } else {
            Text(displayed(line))
                .frame(maxWidth: .infinity, alignment: frameAlignment)
                .modifier(TextDecorations(style: element.style))
        }
    }

    /// An empty line still occupies a row — the web renderer substitutes a space for exactly this
    /// reason, so a blank line between paragraphs is a blank line rather than nothing.
    private func displayed(_ line: String) -> String {
        line.isEmpty ? " " : line
    }

    private func listMarker(number: Int) -> String? {
        switch element.style.listType {
        case "bullet":   return "\u{2022}"
        case "numbered": return "\(number)."
        default:         return nil
        }
    }

    private func scaled(_ points: Double?) -> CGFloat {
        guard let points, points > 0 else { return 0 }
        return SlideGeometry.fontSize(points, canvasWidth: canvasSize.width)
    }

    private var shadowColor: Color {
        guard element.style.shadow == true else { return .clear }
        return CSSColor.color(element.style.shadowColor) ?? Color.black.opacity(0.5)
    }

    private var horizontalAlignment: HorizontalAlignment {
        switch element.style.align {
        case "center": return .center
        case "right":  return .trailing
        default:       return .leading
        }
    }

    private var frameAlignment: Alignment {
        switch element.style.align {
        case "center": return .center
        case "right":  return .trailing
        default:       return .leading
        }
    }
}

// MARK: - TextDecorations

/// Underline and strikethrough, which have to be applied to the `Text` itself rather than to a
/// container — SwiftUI's modifiers for them are on `Text`, not on `View`.
private struct TextDecorations: ViewModifier {

    let style: TextStyle

    func body(content: Content) -> some View {
        content
            .underline(style.underline)
            .strikethrough(style.isStrikethrough)
            .multilineTextAlignment(alignment)
    }

    private var alignment: TextAlignment {
        switch style.align {
        case "center": return .center
        case "right":  return .trailing
        default:       return .leading
        }
    }
}

// MARK: - ShapeElementView

/// A filled shape from ``ShapeCatalog``.
struct ShapeElementView: View {

    let element: ShapeElement
    let canvasSize: CGSize

    var body: some View {
        GeometryReader { proxy in
            let path = Path(ShapeCatalog.cgPath(for: element.shape,
                                                in: CGRect(origin: .zero, size: proxy.size)))
            ZStack {
                path.fill(CSSColor.color(element.fill) ?? .clear)
                if let stroke = CSSColor.color(element.stroke), element.strokeWidth > 0 {
                    path.stroke(stroke, style: strokeStyle)
                }
            }
        }
    }

    private var strokeStyle: StrokeStyle {
        StrokeStyle(
            lineWidth: SlideGeometry.strokeWidth(element.strokeWidth, canvasWidth: canvasSize.width),
            dash: dashPattern
        )
    }

    /// An SVG dash array (`"8 4"`) as a Core Graphics dash pattern, scaled with the canvas so a
    /// dashed border on a thumbnail is not a solid one.
    private var dashPattern: [CGFloat] {
        guard let strokeDash = element.strokeDash else { return [] }
        return strokeDash
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .compactMap { Double($0) }
            .map { SlideGeometry.strokeWidth($0, canvasWidth: canvasSize.width) }
    }
}

// MARK: - LineElementView

/// A straight line, with the arrowheads its ends ask for.
struct LineElementView: View {

    let element: LineElement
    let canvasSize: CGSize

    var body: some View {
        let start = point(element.x1, element.y1)
        let end = point(element.x2, element.y2)
        let color = CSSColor.color(element.stroke) ?? .primary
        let width = SlideGeometry.strokeWidth(element.strokeWidth, canvasWidth: canvasSize.width)

        ZStack {
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dashPattern))

            if arrow(element.startArrow) {
                arrowhead(at: start, pointingFrom: end, width: width).fill(color)
            }
            if arrow(element.endArrow) {
                arrowhead(at: end, pointingFrom: start, width: width).fill(color)
            }
        }
    }

    private func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: CGFloat(x / 100) * canvasSize.width, y: CGFloat(y / 100) * canvasSize.height)
    }

    /// `"arrow"` and `"triangle"` both draw a filled head. The web app draws them as two different
    /// SVG markers, but at slide scale on a phone the difference between a stroked chevron and a
    /// filled triangle is a pixel; both read as "this end points here", which is the whole content
    /// of the distinction.
    private func arrow(_ value: String?) -> Bool {
        value == "arrow" || value == "triangle"
    }

    private func arrowhead(at tip: CGPoint, pointingFrom origin: CGPoint,
                           width: CGFloat) -> Path {
        let angle = atan2(tip.y - origin.y, tip.x - origin.x)
        let length = max(6, width * 4)
        let spread = CGFloat.pi / 7
        return Path { path in
            path.move(to: tip)
            path.addLine(to: CGPoint(x: tip.x - length * cos(angle - spread),
                                     y: tip.y - length * sin(angle - spread)))
            path.addLine(to: CGPoint(x: tip.x - length * cos(angle + spread),
                                     y: tip.y - length * sin(angle + spread)))
            path.closeSubpath()
        }
    }

    private var dashPattern: [CGFloat] {
        guard let strokeDash = element.strokeDash else { return [] }
        return strokeDash
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .compactMap { Double($0) }
            .map { SlideGeometry.strokeWidth($0, canvasWidth: canvasSize.width) }
    }
}

// MARK: - ImageElementView

/// A picture, with the web app's adjustment sliders applied.
struct ImageElementView: View {

    let element: ImageElement

    var body: some View {
        SlideImageView(source: element.src, objectFit: element.objectFit)
            .opacity(element.opacity)
            // The web renderer's `1 + value / 100`, which is why a stored `0` is the untouched
            // image. SwiftUI's `brightness` is additive over −1…1 rather than a multiplier, so it
            // takes the offset directly; the other two are multipliers, as in CSS.
            .brightness(element.brightness / 100)
            .contrast(1 + element.contrast / 100)
            .saturation(max(0, 1 + element.saturation / 100))
            .overlay {
                if let tint = CSSColor.color(element.tintColor), element.tintStrength > 0 {
                    tint.opacity(element.tintStrength).blendMode(.multiply)
                }
            }
            .overlay {
                // `warmth` is a sepia-and-hue-rotate stack in CSS, which has no SwiftUI equivalent
                // that is worth a Core Image pass per frame on a thumbnail rail. A warm or cool
                // wash over the image is the visible part of the effect, and it costs nothing.
                if element.warmth != 0 {
                    (element.warmth > 0 ? Color.orange : Color.blue)
                        .opacity(min(0.4, abs(element.warmth) / 250))
                        .blendMode(.overlay)
                }
            }
            .clipped()
    }
}

// MARK: - SlideImageView

/// Draws whatever a deck's image `src` points at.
///
/// Three forms, and only two of them are bytes this build can reach:
///
/// - `data:` — decoded here, and the form the PPTX importer writes, so an imported deck's pictures
///   render.
/// - `http(s):` — fetched by `AsyncImage`.
/// - `neutrino-drive:<fileId>` — a reference to an *encrypted* Drive file. Resolving it means
///   downloading the file, fetching its sealed key and decrypting it in the browser's place, which
///   is Epic 15. Until then it draws a labelled placeholder, so a deck full of Drive images reads
///   as "pictures this build cannot show yet" rather than as a deck full of holes.
struct SlideImageView: View {

    let source: String
    let objectFit: String

    var body: some View {
        switch form {
        case .data(let image):
            fitted(Image(uiImage: image))

        case .remote(let url):
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    fitted(image)
                case .failure:
                    placeholder(symbol: "photo.badge.exclamationmark", label: "Image unavailable")
                default:
                    Color(.secondarySystemBackground)
                }
            }

        case .driveReference:
            placeholder(symbol: "lock.doc", label: "Encrypted image")

        case .missing:
            placeholder(symbol: "photo", label: "No image")
        }
    }

    // MARK: - Form

    private enum Form {
        case data(UIImage)
        case remote(URL)
        case driveReference
        case missing
    }

    private var form: Form {
        guard !source.isEmpty else { return .missing }
        if source.hasPrefix(ImageElement.drivePrefix) { return .driveReference }
        if source.hasPrefix("data:") {
            guard let range = source.range(of: "base64,"),
                  let data = Data(base64Encoded: String(source[range.upperBound...])),
                  let image = UIImage(data: data) else { return .missing }
            return .data(image)
        }
        guard let url = URL(string: source), url.scheme?.hasPrefix("http") == true else {
            return .missing
        }
        return .remote(url)
    }

    /// Applies `objectFit`. `"fill"` is a plain `resizable()` — the box's aspect ratio wins, and
    /// the picture is stretched — which is what CSS's `fill` means and what neither `.fit` nor
    /// `.fill` does.
    @ViewBuilder
    private func fitted(_ image: Image) -> some View {
        if objectFit == "fill" {
            image.resizable()
        } else {
            image
                .resizable()
                .aspectRatio(contentMode: objectFit == "contain" ? .fit : .fill)
        }
    }

    private func placeholder(symbol: String, label: String) -> some View {
        ZStack {
            Color(.secondarySystemBackground)
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(4)
        }
    }
}

// MARK: - OpaqueElementView

/// The placeholder for an element this build does not render — a live sheet embed, a video, a
/// diagram.
///
/// Drawn as a labelled dashed box rather than left blank. The element is *there*, it takes up that
/// space on the projector, and a user rearranging a slide around an invisible hole would produce a
/// deck that only looks right on a phone.
struct OpaqueElementView: View {

    let element: OpaqueElement

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.secondarySystemBackground))
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color(.separator), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            VStack(spacing: 4) {
                Image(systemName: element.iconName)
                    .foregroundStyle(.secondary)
                Text(element.displayName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(4)
        }
        .accessibilityLabel("\(element.displayName), shown on the web")
    }
}
