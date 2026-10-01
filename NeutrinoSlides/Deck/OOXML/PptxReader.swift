import Foundation
import NeutrinoOOXML

// MARK: - PptxReader

/// Reads the slides out of a `.pptx` that carries no model Neutrino can trust — a deck made in
/// PowerPoint or Keynote, or a Neutrino deck that went through one and came back without its model.
///
/// A port of `importFromPptx` in `web/apps/web/src/app/(apps)/slides/editor/pptxImport.ts`, mapping
/// to the same element shapes with the same unit conversions, so a foreign deck opens the same way on
/// both clients. It is lossy in the same places, by design: one text style per box (taken from the
/// first run, through the slide → layout → master cascade), no tables or charts, and pictures carried
/// inline as `data:` URLs.
///
/// Where the web version misreads a common file, this one does not, and says so at the spot:
/// slide order comes from `presentation.xml` rather than file names, notes are found through the
/// slide's relationships, grouped shapes are placed through their group's transform, and
/// a shape's fill is read from its own properties rather than from the first fill anywhere inside.
enum PptxReader {

    /// Reads `zip` as a deck. Never throws: a package with no readable slides opens as
    /// ``SlideDeck/empty``, matching the web's `makeDefaultPresentation()` fallback.
    static func read(_ zip: ZipArchive) -> SlideDeck {
        var context = Context(zip: zip)
        let slidePaths = context.slidePaths()
        guard !slidePaths.isEmpty else { return .empty }

        if let first = slidePaths.first { context.loadTheme(firstSlide: first) }
        let slides = slidePaths.compactMap { context.slide(at: $0) }
        guard !slides.isEmpty else { return .empty }
        return SlideDeck(slides: slides, theme: .default, master: .default)
    }

    /// Reads bytes as a deck, or returns nil when they are not a package.
    static func read(_ data: Data) -> SlideDeck? {
        guard let zip = try? ZipArchive(data: data) else { return nil }
        return read(zip)
    }
}

// MARK: - Context

private struct Context {

    let zip: ZipArchive
    private var documents: [String: XMLElement] = [:]
    private var relationships: [String: [String: String]] = [:]
    private var themeColors: [String: String] = [:]
    private var minorFont = "Inter"
    private var slideWidth = Double(PptxWriter.slideWidth)
    private var slideHeight = Double(PptxWriter.slideHeight)

    init(zip: ZipArchive) {
        self.zip = zip
        if let size = document("ppt/presentation.xml")?.descendant("sldSz"),
           let cx = size.attribute("cx").flatMap(Double.init),
           let cy = size.attribute("cy").flatMap(Double.init), cx > 0, cy > 0 {
            slideWidth = cx
            slideHeight = cy
        }
    }

    // MARK: Parts

    mutating func document(_ path: String) -> XMLElement? {
        if let cached = documents[path] { return cached }
        guard let data = zip.data(for: path), let root = XMLElement.parse(data) else { return nil }
        documents[path] = root
        return root
    }

    /// `path`'s relationships, id → resolved part path.
    mutating func rels(for path: String) -> [String: String] {
        if let cached = relationships[path] { return cached }
        var out: [String: String] = [:]
        if let root = document(OOXMLPackage.relsPart(for: path)) {
            let directory = path.split(separator: "/").dropLast().joined(separator: "/")
            for rel in root.elements("Relationship") {
                guard let id = rel.attribute("Id"), let target = rel.attribute("Target"),
                      rel.attribute("TargetMode") != "External" else { continue }
                out[id] = OOXMLPackage.resolve(target: target, from: directory)
            }
        }
        relationships[path] = out
        return out
    }

    private mutating func related(_ path: String, containing fragment: String) -> String? {
        rels(for: path).values.sorted().first { $0.contains(fragment) }
    }

    /// The slide parts in presentation order.
    ///
    /// `sldIdLst` is the order; the web sorts by the number in the file name, which agrees for a
    /// freshly written deck and not for one whose slides were reordered in PowerPoint. The file
    /// name order is still the fallback for a package with no usable list.
    mutating func slidePaths() -> [String] {
        let presentation = "ppt/presentation.xml"
        let presentationRels = rels(for: presentation)
        let ordered = (document(presentation)?.descendant("sldIdLst")?.elements("sldId") ?? [])
            .compactMap { $0.attribute("id", uri: OOXMLNamespace.r).flatMap { presentationRels[$0] } }
            .filter { zip.contains($0) }
        if !ordered.isEmpty { return ordered }

        func number(_ path: String) -> Int {
            Int(path.dropFirst("ppt/slides/slide".count).dropLast(".xml".count)) ?? 0
        }
        return zip.names
            .filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") && !$0.contains("/_rels/") }
            .sorted { number($0) < number($1) }
    }

    // MARK: Theme

    /// Follows the first slide to its layout, master and theme, as the web does.
    mutating func loadTheme(firstSlide: String) {
        var themePath: String?
        if let layout = related(firstSlide, containing: "slideLayouts/"),
           let master = related(layout, containing: "slideMasters/") {
            themePath = related(master, containing: "theme/")
        }
        let path = themePath ?? zip.names.sorted().first {
            $0.hasPrefix("ppt/theme/theme") && $0.hasSuffix(".xml")
        }
        guard let path, let theme = document(path) else { return }

        if let scheme = theme.descendant("clrScheme") {
            for slot in scheme.children {
                if let rgb = slot.element("srgbClr")?.attribute("val") {
                    themeColors[slot.localName] = rgb
                } else if let last = slot.element("sysClr")?.attribute("lastClr") {
                    themeColors[slot.localName] = last
                }
            }
        }
        // The usual colour map, so `tx1` and `bg1` — which is what most text and backgrounds name —
        // resolve rather than falling to black. The web reader has no aliases and paints both black.
        for (alias, slot) in ["tx1": "dk1", "bg1": "lt1", "tx2": "dk2", "bg2": "lt2"] {
            if themeColors[alias] == nil, let value = themeColors[slot] { themeColors[alias] = value }
        }
        if let face = theme.descendant("minorFont")?.element("latin")?.attribute("typeface"),
           !face.isEmpty, !face.hasPrefix("+") {
            minorFont = face
        }
    }

    // MARK: Slide

    mutating func slide(at path: String) -> Slide? {
        guard let root = document(path) else { return nil }
        let layoutPath = related(path, containing: "slideLayouts/")
        let masterPath = layoutPath.flatMap { related($0, containing: "slideMasters/") }
        let layout = layoutPath.flatMap { document($0) }
        let master = masterPath.flatMap { document($0) }

        var background: SlideBackground?
        for (doc, docPath) in [(root, path), (layout, layoutPath), (master, masterPath)] {
            guard let doc, let docPath else { continue }
            if let found = self.background(doc.descendant("cSld")?.element("bg"), partPath: docPath) {
                background = found
                break
            }
        }

        var elements: [SlideElement] = []
        if let tree = root.descendant("spTree") {
            collect(tree, transform: .identity, partPath: path,
                    layout: layout, master: master, into: &elements)
        }

        return Slide(background: background ?? .color("#ffffff"),
                     elements: elements,
                     notes: notes(forSlide: path),
                     transition: transition(root.element("transition")))
    }

    /// Walks a shape tree, descending into groups.
    ///
    /// A grouped shape's position is in the group's own child coordinate space, so it is mapped
    /// through the group's transform on the way down. The web reader skips groups entirely, which
    /// drops everything a PowerPoint user grouped.
    private mutating func collect(_ tree: XMLElement, transform: GroupTransform, partPath: String,
                                  layout: XMLElement?, master: XMLElement?,
                                  into elements: inout [SlideElement]) {
        for child in tree.children {
            switch child.localName {
            case "sp":
                if let element = shape(child, transform: transform, layout: layout, master: master) {
                    elements.append(element)
                }
            case "pic":
                if let element = picture(child, transform: transform, partPath: partPath) {
                    elements.append(.image(element))
                }
            case "cxnSp":
                if let spPr = child.element("spPr"), let xfrm = spPr.element("xfrm"),
                   let element = line(xfrm: xfrm, outline: spPr.element("ln"), transform: transform) {
                    elements.append(.line(element))
                }
            case "grpSp":
                let inner = child.element("grpSpPr")?.element("xfrm")
                    .map { transform.composed(with: GroupTransform(groupXfrm: $0)) } ?? transform
                collect(child, transform: inner, partPath: partPath,
                        layout: layout, master: master, into: &elements)
            default:
                continue
            }
        }
    }

    // MARK: Geometry

    private func box(_ xfrm: XMLElement, _ transform: GroupTransform) -> SlideFrame? {
        guard let raw = transform.apply(xfrm) else { return nil }
        let w = raw.cx / slideWidth * 100
        let h = raw.cy / slideHeight * 100
        guard w > 0, h > 0 else { return nil }
        return SlideFrame(x: clamp(raw.x / slideWidth * 100, 0, 100),
                          y: clamp(raw.y / slideHeight * 100, 0, 100),
                          w: clamp(w, 0, 100), h: clamp(h, 0, 100))
    }

    private func line(xfrm: XMLElement, outline: XMLElement?, transform: GroupTransform) -> LineElement? {
        guard let raw = transform.apply(xfrm) else { return nil }
        let flipH = xfrm.attribute("flipH") == "1"
        let flipV = xfrm.attribute("flipV") == "1"
        func px(_ value: Double) -> Double { clamp(value / slideWidth * 100, 0, 100) }
        func py(_ value: Double) -> Double { clamp(value / slideHeight * 100, 0, 100) }
        let x1 = px(flipH ? raw.x + raw.cx : raw.x)
        let y1 = py(flipV ? raw.y + raw.cy : raw.y)
        let x2 = px(flipH ? raw.x : raw.x + raw.cx)
        let y2 = py(flipV ? raw.y : raw.y + raw.cy)
        guard x1 != x2 || y1 != y2 else { return nil }

        return LineElement(x1: x1, y1: y1, x2: x2, y2: y2,
                           stroke: solidColor(outline?.element("solidFill")) ?? "#000000",
                           strokeWidth: strokeWidth(outline, minimum: 1),
                           strokeDash: dash(outline),
                           startArrow: arrow(outline?.element("headEnd")),
                           endArrow: arrow(outline?.element("tailEnd")))
    }

    private func strokeWidth(_ outline: XMLElement?, minimum: Double) -> Double {
        guard let w = outline?.attribute("w").flatMap(Double.init) else { return minimum }
        return max(1, (w / 12_700).rounded())
    }

    private func dash(_ outline: XMLElement?) -> String? {
        guard let value = outline?.element("prstDash")?.attribute("val"), value != "solid" else { return nil }
        return value.lowercased().contains("dot") ? "2 4" : "8 4"
    }

    private func arrow(_ end: XMLElement?) -> String {
        switch end?.attribute("type") ?? "none" {
        case "none":                 return "none"
        case "triangle", "stealth":  return "triangle"
        default:                     return "arrow"
        }
    }

    // MARK: Shapes and text

    private mutating func shape(_ sp: XMLElement, transform: GroupTransform,
                                layout: XMLElement?, master: XMLElement?) -> SlideElement? {
        let spPr = sp.element("spPr")
        guard let xfrm = spPr?.element("xfrm") else { return nil }

        let body = sp.element("txBody")
        let paragraphs = body?.elements("p") ?? []
        let content = paragraphs.map { paragraph in
            paragraph.children.compactMap { child -> String? in
                switch child.localName {
                case "r", "fld": return child.element("t")?.textContent
                case "br":       return "\n"
                default:         return nil
                }
            }.joined()
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        if !content.isEmpty, let frame = box(xfrm, transform) {
            return .text(TextElement(frame: frame, content: content,
                                     style: textStyle(sp: sp, spPr: spPr, body: body,
                                                      paragraphs: paragraphs,
                                                      layout: layout, master: master)))
        }

        let preset = spPr?.element("prstGeom")?.attribute("prst") ?? "rect"
        let outline = spPr?.element("ln")
        if preset == "line" {
            return line(xfrm: xfrm, outline: outline, transform: transform).map(SlideElement.line)
        }
        guard let frame = box(xfrm, transform) else { return nil }

        // The fill is a *direct* child of `spPr`. The web asks for the first `solidFill` anywhere
        // inside it, which for an unfilled shape is the outline's colour.
        var fill = "transparent"
        if let solid = spPr?.element("solidFill") {
            fill = solidColor(solid) ?? "transparent"
        } else if let gradient = spPr?.element("gradFill") {
            fill = gradientCSS(gradient)
        } else if spPr?.element("noFill") == nil, let style = sp.element("style") {
            // No fill of its own: PowerPoint paints the style's fill reference, which is how most
            // shapes drawn from the toolbar get their colour.
            fill = solidColor(style.element("fillRef")) ?? "transparent"
        }

        var stroke = "transparent"
        var width = 0.0
        if let outline, outline.element("noFill") == nil {
            stroke = solidColor(outline.element("solidFill")) ?? "transparent"
            width = stroke == "transparent" ? 0 : strokeWidth(outline, minimum: 1)
        }
        guard fill != "transparent" || stroke != "transparent" else { return nil }

        var key = Self.shapeKeys[preset] ?? "rect"
        if preset == "chevron", xfrm.attribute("flipH") == "1" { key = "chevron-l" }
        return .shape(ShapeElement(shape: key, frame: frame, fill: fill, stroke: stroke,
                                   strokeWidth: width, strokeDash: dash(outline)))
    }

    private mutating func textStyle(sp: XMLElement, spPr: XMLElement?, body: XMLElement?,
                                    paragraphs: [XMLElement],
                                    layout: XMLElement?, master: XMLElement?) -> TextStyle {
        let placeholder = sp.element("nvSpPr")?.element("nvPr")?.element("ph")
        let type = placeholder?.attribute("type")
        let index = placeholder?.attribute("idx")
        let layoutPlaceholder = Self.matchingPlaceholder(in: layout, type: type, index: index)
        let masterPlaceholder = Self.matchingPlaceholder(in: master, type: type, index: index)

        let first = paragraphs.first
        let pPr = first?.element("pPr")
        let level = max(1, (pPr?.attribute("lvl").flatMap(Int.init) ?? 0) + 1)
        let firstRun = first?.elements("r").first

        // Cascade: run → paragraph default → slide list style → layout → master.
        let sources = [
            firstRun?.element("rPr"),
            pPr?.element("defRPr"),
            Self.listDefault(body, level: level),
            Self.listDefault(layoutPlaceholder?.element("txBody"), level: level),
            Self.listDefault(masterPlaceholder?.element("txBody"), level: level),
        ].compactMap { $0 }
        func attribute(_ name: String) -> String? {
            sources.lazy.compactMap { $0.attribute(name) }.first
        }

        let sizeText = attribute("sz")
        let fontSize = sizeText.flatMap(Double.init).map { ($0 / 100 * 1.333).rounded() } ?? 24
        let color = sources.compactMap { solidColor($0.element("solidFill")) }.first ?? "#1f2937"
        let font = sources.lazy.compactMap { $0.element("latin")?.attribute("typeface") }
            .first { !$0.isEmpty && !$0.hasPrefix("+") } ?? minorFont

        let align: String
        switch pPr?.attribute("algn") {
        case "ctr":  align = "center"
        case "r":    align = "right"
        case "just": align = "justify"
        default:     align = "left"
        }

        // Line height from the largest space-before and the first paragraph's line spacing, the
        // web's approximation of PowerPoint's per-paragraph spacing.
        let sizeHundredths = sizeText.flatMap(Double.init) ?? 1800
        let spaces = paragraphs.dropFirst().map {
            $0.element("pPr")?.element("spcBef")?.element("spcPts")?.attribute("val").flatMap(Double.init) ?? 0
        }
        let maxSpace = spaces.max() ?? 0
        let multiplier = pPr?.element("lnSpc")?.element("spcPct")?.attribute("val")
            .flatMap(Double.init).map { $0 / 100_000 } ?? 1
        let lineHeight = maxSpace > 0
            ? ((multiplier + maxSpace / sizeHundredths) * 100).rounded() / 100
            : nil

        var background: String?
        if let fill = solidColor(spPr?.element("solidFill")), fill != "#ffffff" { background = fill }

        var listType: String?
        if pPr?.element("buChar") != nil { listType = "bullet" }
        if pPr?.element("buAutoNum") != nil { listType = "numbered" }

        return TextStyle(fontSize: clamp(fontSize, 8, 120),
                         bold: attribute("b") == "1",
                         italic: attribute("i") == "1",
                         underline: attribute("u").map { $0 != "none" } ?? false,
                         color: color, align: align, fontFamily: font,
                         strikethrough: attribute("strike") == "sngStrike" || attribute("strike") == "dblStrike",
                         backgroundColor: background, lineHeight: lineHeight, listType: listType)
    }

    private static func matchingPlaceholder(in doc: XMLElement?, type: String?, index: String?) -> XMLElement? {
        guard let doc, type != nil || index != nil else { return nil }
        let candidates = doc.descendants("sp")
        func placeholder(_ sp: XMLElement) -> XMLElement? {
            sp.element("nvSpPr")?.element("nvPr")?.element("ph")
        }
        if let type, let match = candidates.first(where: { placeholder($0)?.attribute("type") == type }) {
            return match
        }
        if let index, let match = candidates.first(where: { placeholder($0)?.attribute("idx") == index }) {
            return match
        }
        return nil
    }

    private static func listDefault(_ body: XMLElement?, level: Int) -> XMLElement? {
        body?.element("lstStyle")?.element("lvl\(level)pPr")?.element("defRPr")
    }

    // MARK: Pictures

    private mutating func picture(_ pic: XMLElement, transform: GroupTransform,
                                  partPath: String) -> ImageElement? {
        guard let blip = pic.element("blipFill")?.element("blip"),
              let id = blip.attribute("embed", uri: OOXMLNamespace.r),
              let source = dataURL(rels(for: partPath)[id]),
              let xfrm = pic.element("spPr")?.element("xfrm"),
              let frame = box(xfrm, transform) else { return nil }
        let opacity = blip.element("alphaModFix")?.attribute("amt").flatMap(Double.init)
            .map { $0 / 100_000 } ?? 1
        return ImageElement(frame: frame, src: source, opacity: opacity, objectFit: "cover")
    }

    private func dataURL(_ path: String?) -> String? {
        guard let path, let data = zip.data(for: path) else { return nil }
        let ext = path.split(separator: ".").last.map { $0.lowercased() } ?? "png"
        let mime = Self.imageTypes[ext] ?? "image/png"
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    // MARK: Background

    private mutating func background(_ bg: XMLElement?, partPath: String) -> SlideBackground? {
        guard let bg else { return nil }
        if let properties = bg.element("bgPr") {
            if let gradient = properties.element("gradFill") {
                return .gradient(gradientCSS(gradient))
            }
            if let blip = properties.element("blipFill")?.element("blip"),
               let id = blip.attribute("embed", uri: OOXMLNamespace.r),
               let source = dataURL(rels(for: partPath)[id]) {
                return .image(source, objectFit: "cover")
            }
            if let color = solidColor(properties.element("solidFill")) {
                return .color(color)
            }
        }
        if let reference = bg.element("bgRef"), let color = solidColor(reference) {
            return .color(color)
        }
        return nil
    }

    // MARK: Notes

    /// The slide's speaker notes, found through its relationships.
    ///
    /// The web reader assumes `notesSlideN` belongs to `slideN`, which holds for a freshly written
    /// deck and not after slides are reordered. The first shape on a notes page is the slide image,
    /// so — like the web — the notes are the first text after it.
    private mutating func notes(forSlide path: String) -> String {
        guard let notesPath = related(path, containing: "notesSlides/"),
              let notes = document(notesPath) else { return "" }
        for sp in notes.descendants("sp").dropFirst() {
            guard let body = sp.element("txBody") else { continue }
            let text = body.elements("p").map { paragraph in
                paragraph.descendants("t").map(\.textContent).joined()
            }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return ""
    }

    // MARK: Transition

    private func transition(_ element: XMLElement?) -> String {
        guard let effect = element?.children.first else { return SlideTransition.none.rawValue }
        let direction = effect.attribute("dir") ?? ""
        let value: SlideTransition
        switch effect.localName {
        case "fade", "smoothFade":           value = .fade
        case "dissolve":                     value = .dissolve
        case "zoom", "flythrough":           value = .zoom
        case "flip":                         value = .flip
        case "cube":                         value = .cube
        case "wipe":                         value = .wipe
        case "cover", "uncover":             value = .cover
        case "push", "pull":                 value = direction == "r" || direction == "d" ? .slideLeft : .slideRight
        case "conveyor":                     value = direction == "r" ? .slideLeft : .slideRight
        case "gallery":                      value = .gallery
        case "checker", "blinds", "circle":  value = .pixelate
        default:                             value = .none
        }
        return value.rawValue
    }

    // MARK: Colour

    /// The colour a fill-like element holds, as `#rrggbb`, with any luminance modifiers applied.
    func solidColor(_ container: XMLElement?) -> String? {
        guard let container else { return nil }
        if let rgb = container.element("srgbClr"), let value = rgb.attribute("val") {
            return "#" + Self.applyModifiers(value, rgb)
        }
        if let scheme = container.element("schemeClr") {
            let base = themeColors[scheme.attribute("val") ?? ""] ?? "000000"
            return "#" + Self.applyModifiers(base, scheme)
        }
        if let system = container.element("sysClr"), let last = system.attribute("lastClr") {
            return "#" + last.lowercased()
        }
        if let preset = container.element("prstClr") {
            let base = Self.presetColors[preset.attribute("val") ?? ""] ?? "000000"
            return "#" + Self.applyModifiers(base, preset)
        }
        return nil
    }

    private func gradientCSS(_ gradient: XMLElement) -> String {
        let stops = gradient.element("gsLst")?.elements("gs") ?? []
        guard !stops.isEmpty else { return "linear-gradient(90deg, #cccccc, #ffffff)" }
        let list = stops.map { stop -> String in
            let position = (stop.attribute("pos").flatMap(Double.init) ?? 0) / 1000
            return "\(solidColor(stop) ?? "#000000") \(Self.number(position))%"
        }.joined(separator: ", ")
        var degrees = 90.0
        if let angle = gradient.element("lin")?.attribute("ang").flatMap(Double.init) {
            degrees = (angle / 60_000 + 90).truncatingRemainder(dividingBy: 360)
        }
        return "linear-gradient(\(Int(degrees.rounded()))deg, \(list))"
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    /// `lumMod`, `lumOff`, `shade` and `tint`, in HSL, exactly as the web applies them.
    static func applyModifiers(_ hex: String, _ element: XMLElement) -> String {
        let padded = String(repeating: "0", count: max(0, 6 - hex.count)) + hex
        guard let value = UInt32(padded.prefix(6), radix: 16) else { return "000000" }
        let r = Double((value >> 16) & 0xff) / 255
        let g = Double((value >> 8) & 0xff) / 255
        let b = Double(value & 0xff) / 255
        var (h, s, l) = rgbToHSL(r, g, b)
        func percent(_ name: String) -> Double? {
            element.element(name).map { Double($0.attribute("val") ?? "100000").map { $0 / 100_000 } ?? 1 }
        }
        if let mod = percent("lumMod") { l *= mod }
        if let off = percent("lumOff") { l += off }
        if let shade = percent("shade") { l *= shade }
        if let tint = percent("tint") { l += (1 - l) * (1 - tint) }
        let (nr, ng, nb) = hslToRGB(h, s, clamp(l, 0, 1))
        return [nr, ng, nb].map { String(format: "%02x", Int(clamp($0, 0, 255))) }.joined()
    }

    private static func rgbToHSL(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let maximum = max(r, g, b), minimum = min(r, g, b)
        let l = (maximum + minimum) / 2
        guard maximum != minimum else { return (0, 0, l) }
        let d = maximum - minimum
        let s = l > 0.5 ? d / (2 - maximum - minimum) : d / (maximum + minimum)
        var h: Double
        switch maximum {
        case r:  h = (g - b) / d + (g < b ? 6 : 0)
        case g:  h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        h /= 6
        return (h, s, l)
    }

    private static func hslToRGB(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
        guard s != 0 else { let v = (l * 255).rounded(); return (v, v, v) }
        func channel(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        return ((channel(p, q, h + 1.0 / 3) * 255).rounded(),
                (channel(p, q, h) * 255).rounded(),
                (channel(p, q, h - 1.0 / 3) * 255).rounded())
    }

    // MARK: Tables

    /// `PRST_GEOM_MAP` from the importer, plus `plus` — PowerPoint's actual name for the cross,
    /// which is also what ``PptxWriter`` writes.
    static let shapeKeys: [String: String] = [
        "rect": "rect", "roundRect": "rounded-rect", "ellipse": "circle",
        "triangle": "triangle", "rtTriangle": "right-triangle",
        "parallelogram": "parallelogram", "trapezoid": "trapezoid", "diamond": "diamond",
        "pentagon": "pentagon", "hexagon": "hexagon", "octagon": "octagon",
        "cross": "cross", "plus": "cross", "heart": "heart",
        "star4": "star4", "star5": "star5", "star6": "star6",
        "star7": "star5", "star8": "star5", "star10": "star5", "star12": "star5", "star16": "star5",
        "rightArrow": "arrow-right", "leftArrow": "arrow-left",
        "upArrow": "arrow-up", "downArrow": "arrow-down",
        "leftRightArrow": "arrow-lr", "upDownArrow": "arrow-ud",
        "chevron": "chevron-r", "leftChevron": "chevron-l",
        "homePlate": "arrow-pentagon", "notchedRightArrow": "arrow-notched",
        "quadArrow": "arrow-quad",
        "wedgeRectCallout": "callout-rect", "wedgeRoundRectCallout": "callout-rounded",
        "wedgeEllipseCallout": "callout-oval", "cloudCallout": "callout-cloud",
    ]

    private static let presetColors: [String: String] = [
        "white": "ffffff", "black": "000000", "red": "ff0000", "green": "008000",
        "blue": "0000ff", "yellow": "ffff00", "cyan": "00ffff", "magenta": "ff00ff",
        "orange": "ffa500", "purple": "800080", "gray": "808080", "grey": "808080",
        "darkGray": "a9a9a9", "lightGray": "d3d3d3", "brown": "a52a2a",
    ]

    private static let imageTypes: [String: String] = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
        "bmp": "image/bmp", "webp": "image/webp", "svg": "image/svg+xml",
        "tiff": "image/tiff", "tif": "image/tiff",
    ]
}

// MARK: - GroupTransform

/// Maps a shape's `a:xfrm` out of the coordinate space of the groups it sits in.
///
/// A group declares where it sits (`off`/`ext`) and the space its children are laid out in
/// (`chOff`/`chExt`); a child point maps as `off + (point - chOff) * ext / chExt`. Nested groups
/// compose.
private struct GroupTransform {
    var scaleX = 1.0, scaleY = 1.0, offsetX = 0.0, offsetY = 0.0

    static let identity = GroupTransform()

    init() {}

    init(groupXfrm xfrm: XMLElement) {
        let off = Self.point(xfrm.element("off"), "x", "y")
        let ext = Self.point(xfrm.element("ext"), "cx", "cy")
        let childOff = Self.point(xfrm.element("chOff"), "x", "y")
        let childExt = Self.point(xfrm.element("chExt"), "cx", "cy")
        scaleX = childExt.0 > 0 ? ext.0 / childExt.0 : 1
        scaleY = childExt.1 > 0 ? ext.1 / childExt.1 : 1
        offsetX = off.0 - childOff.0 * scaleX
        offsetY = off.1 - childOff.1 * scaleY
    }

    /// `inner` applied first, then this.
    func composed(with inner: GroupTransform) -> GroupTransform {
        var out = GroupTransform()
        out.scaleX = scaleX * inner.scaleX
        out.scaleY = scaleY * inner.scaleY
        out.offsetX = offsetX + inner.offsetX * scaleX
        out.offsetY = offsetY + inner.offsetY * scaleY
        return out
    }

    func apply(_ xfrm: XMLElement) -> (x: Double, y: Double, cx: Double, cy: Double)? {
        guard let off = xfrm.element("off"), let ext = xfrm.element("ext") else { return nil }
        let (x, y) = Self.point(off, "x", "y")
        let (cx, cy) = Self.point(ext, "cx", "cy")
        return (offsetX + x * scaleX, offsetY + y * scaleY, cx * scaleX, cy * scaleY)
    }

    private static func point(_ element: XMLElement?, _ a: String, _ b: String) -> (Double, Double) {
        (element?.attribute(a).flatMap(Double.init) ?? 0, element?.attribute(b).flatMap(Double.init) ?? 0)
    }
}

private func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
    min(high, max(low, value))
}
