import Foundation
import NeutrinoOOXML

// MARK: - PptxWriter

/// Renders a ``SlideDeck`` as the PresentationML half of a `.pptx` — the copy PowerPoint, Keynote
/// and LibreOffice read.
///
/// This is the counterpart of `pptxExport.ts`, and like it, it is deliberately the *lossy* half:
/// ``PptxCodec`` packs the full model in beside it, so anything not written here still survives a
/// save in Neutrino. What is written is what another tool can show — text with its run formatting,
/// shapes, lines and arrows, pictures carried as bytes, solid, gradient and picture backgrounds,
/// speaker notes, and the transitions PresentationML has a plain name for.
///
/// What is *not* written, and why:
///
/// - A `neutrino-drive:` or `http(s):` picture. The bytes live elsewhere, and fetching them is the
///   download-and-decrypt path that is Epic 15. The web resolves Drive references before it writes;
///   until this app can, those pictures are absent from the PowerPoint copy only.
/// - Elements this app does not model (videos, live sheet embeds, diagrams). They have no OOXML
///   form here and ride in the model untouched.
/// - Flip, cube and gallery transitions, which only exist as PowerPoint 2010 extension elements.
///
/// The output is deterministic: the same deck produces the same parts in the same order, which
/// ``ZipArchive`` turns into the same bytes. That keeps a no-op save from looking like an edit.
enum PptxWriter {

    // MARK: - Geometry

    /// 16:9 at ten inches wide — pptxgenjs's `LAYOUT_16x9`, so a deck saved on either client opens
    /// at the same size in PowerPoint.
    static let slideWidth = 9_144_000
    static let slideHeight = 5_143_500

    /// EMUs per point.
    private static let emuPerPoint = 12_700.0

    // MARK: - Entry point

    static func write(_ deck: SlideDeck) -> ZipArchive {
        var zip = ZipArchive()
        var media = MediaStore()
        var slideParts: [(xml: String, rels: String, notes: String?)] = []

        for (index, slide) in deck.slides.enumerated() {
            let number = index + 1
            var rels = Relationships()
            rels.add(type: RelType.slideLayout, target: "../slideLayouts/slideLayout1.xml")
            let hasNotes = !slide.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasNotes {
                rels.add(type: RelType.notesSlide, target: "../notesSlides/notesSlide\(number).xml")
            }
            let xml = slideXML(slide, rels: &rels, media: &media)
            slideParts.append((xml, rels.xml, hasNotes ? notesXML(slide.notes) : nil))
        }

        zip.set(OOXMLPackage.contentTypesPart, text: contentTypes(slideParts: slideParts, media: media))
        zip.set(OOXMLPackage.rootRelsPart, text: rootRels)
        zip.set(OOXMLPackage.corePropsPart, text: coreProps)
        zip.set(OOXMLPackage.appPropsPart, text: appProps(slideCount: slideParts.count))
        zip.set("ppt/presentation.xml", text: presentation(slideCount: slideParts.count))
        zip.set("ppt/_rels/presentation.xml.rels", text: presentationRels(slideCount: slideParts.count))
        zip.set("ppt/presProps.xml", text: presProps)
        zip.set("ppt/viewProps.xml", text: viewProps)
        zip.set("ppt/tableStyles.xml", text: tableStyles)
        zip.set("ppt/slideMasters/slideMaster1.xml", text: slideMaster)
        zip.set("ppt/slideMasters/_rels/slideMaster1.xml.rels", text: slideMasterRels)
        zip.set("ppt/slideLayouts/slideLayout1.xml", text: slideLayout)
        zip.set("ppt/slideLayouts/_rels/slideLayout1.xml.rels", text: slideLayoutRels)
        zip.set("ppt/notesMasters/notesMaster1.xml", text: notesMaster)
        zip.set("ppt/notesMasters/_rels/notesMaster1.xml.rels", text: notesMasterRels)
        zip.set("ppt/theme/theme1.xml", text: theme(name: "Neutrino"))
        zip.set("ppt/theme/theme2.xml", text: theme(name: "Neutrino Notes"))

        for (index, part) in slideParts.enumerated() {
            let number = index + 1
            zip.set("ppt/slides/slide\(number).xml", text: part.xml)
            zip.set("ppt/slides/_rels/slide\(number).xml.rels", text: part.rels)
            if let notes = part.notes {
                zip.set("ppt/notesSlides/notesSlide\(number).xml", text: notes)
                zip.set("ppt/notesSlides/_rels/notesSlide\(number).xml.rels",
                        text: notesSlideRels(slideNumber: number))
            }
        }
        for item in media.items {
            zip.set("ppt/media/\(item.fileName)", data: item.data)
        }
        return zip
    }

    // MARK: - Slide

    private static func slideXML(_ slide: Slide, rels: inout Relationships,
                                 media: inout MediaStore) -> String {
        var shapes = ""
        var nextID = 2
        for element in slide.elements {
            let id = nextID
            switch element {
            case .text(let text):
                shapes += textShape(text, id: id)
            case .shape(let shape):
                shapes += autoShape(shape, id: id)
            case .line(let line):
                shapes += connector(line, id: id)
            case .image(let image):
                guard let embedded = media.add(dataURL: image.src) else { continue }
                let rID = rels.add(type: RelType.image, target: "../media/\(embedded)")
                shapes += picture(image, id: id, relationshipID: rID)
            case .opaque:
                continue
            }
            nextID += 1
        }

        return XMLText.declaration
            + "<p:sld \(namespaces)><p:cSld>"
            + background(slide.background, rels: &rels, media: &media)
            + "<p:spTree>\(groupProperties)\(shapes)</p:spTree></p:cSld>"
            + "<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>"
            + transition(slide.transition)
            + "</p:sld>"
    }

    private static func background(_ background: SlideBackground, rels: inout Relationships,
                                   media: inout MediaStore) -> String {
        let fill: String
        // The *value* decides, not the declared type: the web's `applyTheme` stores a gradient under
        // `type: "color"`, and the renderer on both clients paints whatever the value is.
        if let gradient = CSSPaint.gradient(background.value) {
            fill = gradientFill(gradient)
        } else if background.isImage {
            guard let embedded = media.add(dataURL: background.value) else { return "" }
            let rID = rels.add(type: RelType.image, target: "../media/\(embedded)")
            fill = "<a:blipFill dpi=\"0\" rotWithShape=\"1\"><a:blip r:embed=\"\(rID)\"/>"
                + "<a:srcRect/><a:stretch><a:fillRect/></a:stretch></a:blipFill>"
        } else if let color = CSSPaint.color(background.value) {
            fill = solidFill(color)
        } else {
            return ""
        }
        return "<p:bg><p:bgPr>\(fill)<a:effectLst/></p:bgPr></p:bg>"
    }

    /// PresentationML names for the transitions that have one in the base schema. The mapping is
    /// the inverse of `parseTransition` in `pptxImport.ts`, so a deck read back without its model
    /// arrives with the transition it left with.
    private static func transition(_ name: String) -> String {
        let body: String
        switch SlideTransition(rawValue: name) {
        case .fade:       body = "<p:fade/>"
        case .dissolve:   body = "<p:dissolve/>"
        case .zoom:       body = "<p:zoom/>"
        case .wipe:       body = "<p:wipe/>"
        case .cover:      body = "<p:cover/>"
        case .pixelate:   body = "<p:checker/>"
        case .slideRight: body = "<p:push/>"
        case .slideLeft:  body = "<p:push dir=\"r\"/>"
        default:          return ""
        }
        return "<p:transition>\(body)</p:transition>"
    }

    // MARK: - Elements

    private static func textShape(_ element: TextElement, id: Int) -> String {
        let style = element.style
        let boxFill = CSSPaint.color(style.backgroundColor).map(solidFill) ?? "<a:noFill/>"
        let paragraphs = element.content
            .components(separatedBy: "\n")
            .enumerated()
            .map { index, line in paragraph(line, style: style, isFirst: index == 0) }
            .joined()

        return "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"Text \(id)\"/>"
            + "<p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr>"
            + "<p:spPr>\(transform(element.frame))<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>"
            + "\(boxFill)</p:spPr>"
            + "<p:txBody><a:bodyPr wrap=\"square\" rtlCol=\"0\"><a:noAutofit/></a:bodyPr><a:lstStyle/>"
            + paragraphs
            + "</p:txBody></p:sp>"
    }

    private static func paragraph(_ text: String, style: TextStyle, isFirst: Bool) -> String {
        var attributes = ""
        switch style.align {
        case "center":  attributes += " algn=\"ctr\""
        case "right":   attributes += " algn=\"r\""
        case "justify": attributes += " algn=\"just\""
        default:        attributes += " algn=\"l\""
        }
        if style.isBulleted || style.isNumbered {
            attributes += " marL=\"342900\" indent=\"-342900\""
        }

        var properties = ""
        if let lineHeight = style.lineHeight, lineHeight > 0 {
            properties += "<a:lnSpc><a:spcPct val=\"\(Int((lineHeight * 100_000).rounded()))\"/></a:lnSpc>"
        }
        if let before = style.spaceBefore, before > 0, !isFirst {
            properties += "<a:spcBef><a:spcPts val=\"\(Int((before * 100).rounded()))\"/></a:spcBef>"
        }
        if let after = style.spaceAfter, after > 0 {
            properties += "<a:spcAft><a:spcPts val=\"\(Int((after * 100).rounded()))\"/></a:spcAft>"
        }
        if style.isBulleted {
            properties += "<a:buFont typeface=\"Arial\"/><a:buChar char=\"\u{2022}\"/>"
        } else if style.isNumbered {
            properties += "<a:buFont typeface=\"+mj-lt\"/><a:buAutoNum type=\"arabicPeriod\"/>"
        } else {
            properties += "<a:buNone/>"
        }

        let runProperties = runPropertiesXML(style)
        let pPr = "<a:pPr\(attributes)>\(properties)</a:pPr>"
        guard !text.isEmpty else {
            return "<a:p>\(pPr)<a:endParaRPr\(runProperties.attributes)>\(runProperties.children)</a:endParaRPr></a:p>"
        }
        return "<a:p>\(pPr)<a:r><a:rPr\(runProperties.attributes)>\(runProperties.children)</a:rPr>"
            + "<a:t>\(XMLText.escape(text))</a:t></a:r></a:p>"
    }

    /// The attributes and children an `a:rPr` (or `a:endParaRPr`) carries for `style`.
    ///
    /// Font size: the deck stores CSS pixels and PowerPoint hundredths of a point — the same 0.75
    /// factor `pptxExport.ts` applies, and the inverse of the importer's 1.333.
    private static func runPropertiesXML(_ style: TextStyle) -> (attributes: String, children: String) {
        let size = min(400_000, max(100, Int((style.fontSize * 0.75 * 100).rounded())))
        var attributes = " lang=\"en-US\" sz=\"\(size)\""
        if style.bold { attributes += " b=\"1\"" }
        if style.italic { attributes += " i=\"1\"" }
        if style.underline { attributes += " u=\"sng\"" }
        if style.isStrikethrough { attributes += " strike=\"sngStrike\"" }
        attributes += " dirty=\"0\""

        var children = ""
        if let color = CSSPaint.color(style.color) { children += solidFill(color) }
        let face = XMLText.attributeValue(style.fontFamily)
        children += "<a:latin typeface=\"\(face)\"/><a:cs typeface=\"\(face)\"/>"
        return (attributes, children)
    }

    private static func autoShape(_ element: ShapeElement, id: Int) -> String {
        let fill: String
        if let gradient = CSSPaint.gradient(element.fill) {
            fill = gradientFill(gradient)
        } else if let color = CSSPaint.color(element.fill) {
            fill = solidFill(color)
        } else {
            fill = "<a:noFill/>"
        }
        let geometry = presetGeometry[element.shape] ?? "rect"
        // PowerPoint has one chevron, pointing right; a left one is that, mirrored.
        let flip = element.shape == "chevron-l" ? " flipH=\"1\"" : ""
        return "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"Shape \(id)\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>"
            + "<p:spPr>\(transform(element.frame, attributes: flip))"
            + "<a:prstGeom prst=\"\(geometry)\"><a:avLst/></a:prstGeom>\(fill)"
            + outline(color: element.stroke, width: element.strokeWidth, dash: element.strokeDash)
            + "</p:spPr></p:sp>"
    }

    private static func connector(_ element: LineElement, id: Int) -> String {
        // An OOXML line is a box plus two flips: it runs from the box's top-left to its bottom-right
        // unless flipped. Which corner each endpoint is in is therefore what the flips encode.
        var flips = ""
        if element.x1 > element.x2 { flips += " flipH=\"1\"" }
        if element.y1 > element.y2 { flips += " flipV=\"1\"" }
        let ends = arrowEnd("headEnd", element.startArrow) + arrowEnd("tailEnd", element.endArrow)

        return "<p:cxnSp><p:nvCxnSpPr><p:cNvPr id=\"\(id)\" name=\"Line \(id)\"/><p:cNvCxnSpPr/><p:nvPr/>"
            + "</p:nvCxnSpPr><p:spPr>\(transform(element.frame, attributes: flips))"
            + "<a:prstGeom prst=\"line\"><a:avLst/></a:prstGeom>"
            + outline(color: element.stroke, width: max(element.strokeWidth, 0.5),
                      dash: element.strokeDash, ends: ends)
            + "</p:spPr></p:cxnSp>"
    }

    private static func arrowEnd(_ tag: String, _ kind: String?) -> String {
        switch kind {
        case "arrow":    return "<a:\(tag) type=\"arrow\"/>"
        case "triangle": return "<a:\(tag) type=\"triangle\"/>"
        default:         return ""
        }
    }

    private static func picture(_ element: ImageElement, id: Int, relationshipID: String) -> String {
        let alpha = element.opacity < 1
            ? "<a:alphaModFix amt=\"\(Int((max(0, element.opacity) * 100_000).rounded()))\"/>"
            : ""
        return "<p:pic><p:nvPicPr><p:cNvPr id=\"\(id)\" name=\"Picture \(id)\"/>"
            + "<p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>"
            + "<p:blipFill><a:blip r:embed=\"\(relationshipID)\">\(alpha)</a:blip>"
            + "<a:stretch><a:fillRect/></a:stretch></p:blipFill>"
            + "<p:spPr>\(transform(element.frame))<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr>"
            + "</p:pic>"
    }

    // MARK: - DrawingML pieces

    /// `a:xfrm` for a box in canvas percent.
    private static func transform(_ frame: SlideFrame, attributes: String = "") -> String {
        let x = emu(frame.x, of: slideWidth)
        let y = emu(frame.y, of: slideHeight)
        let cx = max(1, emu(frame.w, of: slideWidth))
        let cy = max(1, emu(frame.h, of: slideHeight))
        return "<a:xfrm\(attributes)><a:off x=\"\(x)\" y=\"\(y)\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm>"
    }

    private static func emu(_ percent: Double, of extent: Int) -> Int {
        guard percent.isFinite else { return 0 }
        return Int((percent / 100 * Double(extent)).rounded())
    }

    private static func solidFill(_ color: CSSPaint.RGBA) -> String {
        "<a:solidFill>\(colorXML(color))</a:solidFill>"
    }

    private static func colorXML(_ color: CSSPaint.RGBA) -> String {
        guard color.alpha < 1 else { return "<a:srgbClr val=\"\(color.hex)\"/>" }
        let alpha = Int((max(0, color.alpha) * 100_000).rounded())
        return "<a:srgbClr val=\"\(color.hex)\"><a:alpha val=\"\(alpha)\"/></a:srgbClr>"
    }

    private static func gradientFill(_ gradient: CSSPaint.Gradient) -> String {
        let stops = gradient.stops.map { stop in
            "<a:gs pos=\"\(Int((stop.position * 1000).rounded()))\">\(colorXML(stop.color))</a:gs>"
        }.joined()
        // CSS measures from "to top", clockwise; DrawingML from "to right", clockwise. The importer
        // adds 90 on the way in, so this takes it off on the way out.
        let degrees = (gradient.angle - 90).truncatingRemainder(dividingBy: 360)
        let angle = Int(((degrees < 0 ? degrees + 360 : degrees) * 60_000).rounded())
        return "<a:gradFill rotWithShape=\"1\"><a:gsLst>\(stops)</a:gsLst>"
            + "<a:lin ang=\"\(angle)\" scaled=\"0\"/></a:gradFill>"
    }

    private static func outline(color: String, width: Double, dash: String?, ends: String = "") -> String {
        guard width > 0, let stroke = CSSPaint.color(color) else {
            return "<a:ln><a:noFill/></a:ln>"
        }
        let dashXML = (dash?.isEmpty == false) ? "<a:prstDash val=\"dash\"/>" : ""
        // The deck's stroke width is what pptxgenjs is handed as points and what the importer reads
        // back as `w / 12700`, so it is converted as points here too.
        let w = Int((width * emuPerPoint).rounded())
        return "<a:ln w=\"\(w)\">\(solidFill(stroke))\(dashXML)\(ends)</a:ln>"
    }

    /// The inverse of `PRST_GEOM_MAP` in `pptxImport.ts`. Where the importer folds several
    /// PowerPoint stars onto `star5`, this writes `star5` — the shape the deck actually holds.
    static let presetGeometry: [String: String] = [
        "rect": "rect", "rounded-rect": "roundRect", "circle": "ellipse",
        "triangle": "triangle", "right-triangle": "rtTriangle",
        "parallelogram": "parallelogram", "trapezoid": "trapezoid", "diamond": "diamond",
        "pentagon": "pentagon", "hexagon": "hexagon", "octagon": "octagon",
        "cross": "plus", "heart": "heart",
        "star4": "star4", "star5": "star5", "star6": "star6",
        "arrow-right": "rightArrow", "arrow-left": "leftArrow",
        "arrow-up": "upArrow", "arrow-down": "downArrow",
        "arrow-lr": "leftRightArrow", "arrow-ud": "upDownArrow",
        "chevron-r": "chevron", "chevron-l": "chevron",
        "arrow-pentagon": "homePlate", "arrow-notched": "notchedRightArrow",
        "arrow-quad": "quadArrow",
        "callout-rect": "wedgeRectCallout", "callout-rounded": "wedgeRoundRectCallout",
        "callout-oval": "wedgeEllipseCallout", "callout-cloud": "cloudCallout",
    ]

    // MARK: - Notes

    /// A notes page. The slide-image placeholder comes first because readers — the web's
    /// `pptxImport.ts` among them — skip the first shape and take the notes from the next.
    private static func notesXML(_ notes: String) -> String {
        let paragraphs = notes.components(separatedBy: "\n").map { line in
            line.isEmpty
                ? "<a:p><a:endParaRPr lang=\"en-US\" dirty=\"0\"/></a:p>"
                : "<a:p><a:r><a:rPr lang=\"en-US\" dirty=\"0\"/><a:t>\(XMLText.escape(line))</a:t></a:r></a:p>"
        }.joined()
        return XMLText.declaration
            + "<p:notes \(namespaces)><p:cSld><p:spTree>\(groupProperties)"
            + "<p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"Slide Image Placeholder 1\"/>"
            + "<p:cNvSpPr><a:spLocks noGrp=\"1\" noRot=\"1\" noChangeAspect=\"1\"/></p:cNvSpPr>"
            + "<p:nvPr><p:ph type=\"sldImg\"/></p:nvPr></p:nvSpPr><p:spPr/></p:sp>"
            + "<p:sp><p:nvSpPr><p:cNvPr id=\"3\" name=\"Notes Placeholder 2\"/>"
            + "<p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr>"
            + "<p:nvPr><p:ph type=\"body\" idx=\"1\"/></p:nvPr></p:nvSpPr><p:spPr/>"
            + "<p:txBody><a:bodyPr/><a:lstStyle/>\(paragraphs)</p:txBody></p:sp>"
            + "</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>"
    }

    private static func notesSlideRels(slideNumber: Int) -> String {
        var rels = Relationships()
        rels.add(type: RelType.notesMaster, target: "../notesMasters/notesMaster1.xml")
        rels.add(type: RelType.slide, target: "../slides/slide\(slideNumber).xml")
        return rels.xml
    }

    // MARK: - Package parts

    private static func contentTypes(slideParts: [(xml: String, rels: String, notes: String?)],
                                     media: MediaStore) -> String {
        let pml = "application/vnd.openxmlformats-officedocument.presentationml"
        var overrides = [
            ("/ppt/presentation.xml", "\(pml).presentation.main+xml"),
            ("/ppt/presProps.xml", "\(pml).presProps+xml"),
            ("/ppt/viewProps.xml", "\(pml).viewProps+xml"),
            ("/ppt/tableStyles.xml", "\(pml).tableStyles+xml"),
            ("/ppt/slideMasters/slideMaster1.xml", "\(pml).slideMaster+xml"),
            ("/ppt/slideLayouts/slideLayout1.xml", "\(pml).slideLayout+xml"),
            ("/ppt/notesMasters/notesMaster1.xml", "\(pml).notesMaster+xml"),
            ("/ppt/theme/theme1.xml", "application/vnd.openxmlformats-officedocument.theme+xml"),
            ("/ppt/theme/theme2.xml", "application/vnd.openxmlformats-officedocument.theme+xml"),
            ("/docProps/core.xml", "application/vnd.openxmlformats-package.core-properties+xml"),
            ("/docProps/app.xml", "application/vnd.openxmlformats-officedocument.extended-properties+xml"),
        ]
        for (index, part) in slideParts.enumerated() {
            overrides.append(("/ppt/slides/slide\(index + 1).xml", "\(pml).slide+xml"))
            if part.notes != nil {
                overrides.append(("/ppt/notesSlides/notesSlide\(index + 1).xml", "\(pml).notesSlide+xml"))
            }
        }

        var defaults = [
            ("rels", "application/vnd.openxmlformats-package.relationships+xml"),
            ("xml", "application/xml"),
        ]
        for (ext, type) in media.extensions { defaults.append((ext, type)) }

        return XMLText.declaration
            + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
            + defaults.map { "<Default Extension=\"\($0.0)\" ContentType=\"\($0.1)\"/>" }.joined()
            + overrides.map { "<Override PartName=\"\($0.0)\" ContentType=\"\($0.1)\"/>" }.joined()
            + "</Types>"
    }

    private static var rootRels: String {
        var rels = Relationships()
        rels.add(type: OOXMLRelationship.officeDocument, target: "ppt/presentation.xml")
        rels.add(type: OOXMLRelationship.coreProperties, target: "docProps/core.xml")
        rels.add(type: OOXMLRelationship.extendedProperties, target: "docProps/app.xml")
        return rels.xml
    }

    private static let coreProps = XMLText.declaration
        + "<cp:coreProperties xmlns:cp=\"\(OOXMLNamespace.cp)\" xmlns:dc=\"\(OOXMLNamespace.dc)\""
        + " xmlns:dcterms=\"\(OOXMLNamespace.dcterms)\" xmlns:xsi=\"\(OOXMLNamespace.xsi)\">"
        + "<dc:creator>Neutrino</dc:creator></cp:coreProperties>"

    private static func appProps(slideCount: Int) -> String {
        XMLText.declaration
            + "<Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\""
            + " xmlns:vt=\"\(OOXMLNamespace.vt)\"><Application>Neutrino Slides</Application>"
            + "<PresentationFormat>On-screen Show (16:9)</PresentationFormat>"
            + "<Slides>\(slideCount)</Slides></Properties>"
    }

    private static func presentation(slideCount: Int) -> String {
        // Relationship ids are fixed for the shared parts and follow on for the slides; see
        // `presentationRels`, which must assign them in the same order.
        let slides = (0..<slideCount).map { index in
            "<p:sldId id=\"\(256 + index)\" r:id=\"rId\(firstSlideRelationship + index)\"/>"
        }.joined()
        return XMLText.declaration
            + "<p:presentation \(namespaces) saveSubsetFonts=\"1\">"
            + "<p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"rId1\"/></p:sldMasterIdLst>"
            + "<p:notesMasterIdLst><p:notesMasterId r:id=\"rId2\"/></p:notesMasterIdLst>"
            + "<p:sldIdLst>\(slides)</p:sldIdLst>"
            + "<p:sldSz cx=\"\(slideWidth)\" cy=\"\(slideHeight)\"/>"
            + "<p:notesSz cx=\"6858000\" cy=\"9144000\"/>"
            + "</p:presentation>"
    }

    private static let firstSlideRelationship = 7

    private static func presentationRels(slideCount: Int) -> String {
        var rels = Relationships()
        rels.add(type: RelType.slideMaster, target: "slideMasters/slideMaster1.xml")  // rId1
        rels.add(type: RelType.notesMaster, target: "notesMasters/notesMaster1.xml")  // rId2
        rels.add(type: RelType.theme, target: "theme/theme1.xml")                     // rId3
        rels.add(type: RelType.presProps, target: "presProps.xml")                    // rId4
        rels.add(type: RelType.viewProps, target: "viewProps.xml")                    // rId5
        rels.add(type: RelType.tableStyles, target: "tableStyles.xml")                // rId6
        for index in 0..<slideCount {
            rels.add(type: RelType.slide, target: "slides/slide\(index + 1).xml")
        }
        return rels.xml
    }

    private static let presProps = XMLText.declaration
        + "<p:presentationPr \(namespaces)/>"

    private static let viewProps = XMLText.declaration
        + "<p:viewPr \(namespaces)><p:gridSpacing cx=\"76200\" cy=\"76200\"/></p:viewPr>"

    private static let tableStyles = XMLText.declaration
        + "<a:tblStyleLst xmlns:a=\"\(OOXMLNamespace.a)\" def=\"{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}\"/>"

    private static let colorMap = "bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\""
        + " accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\""
        + " accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\""

    private static let slideMaster = XMLText.declaration
        + "<p:sldMaster \(namespaces)><p:cSld>"
        + "<p:bg><p:bgRef idx=\"1001\"><a:schemeClr val=\"bg1\"/></p:bgRef></p:bg>"
        + "<p:spTree>\(groupProperties)</p:spTree></p:cSld>"
        + "<p:clrMap \(colorMap)/>"
        + "<p:sldLayoutIdLst><p:sldLayoutId id=\"2147483649\" r:id=\"rId1\"/></p:sldLayoutIdLst>"
        + "</p:sldMaster>"

    private static var slideMasterRels: String {
        var rels = Relationships()
        rels.add(type: RelType.slideLayout, target: "../slideLayouts/slideLayout1.xml")
        rels.add(type: RelType.theme, target: "../theme/theme1.xml")
        return rels.xml
    }

    private static let slideLayout = XMLText.declaration
        + "<p:sldLayout \(namespaces) type=\"blank\" preserve=\"1\"><p:cSld name=\"Blank\">"
        + "<p:spTree>\(groupProperties)</p:spTree></p:cSld>"
        + "<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>"

    private static var slideLayoutRels: String {
        var rels = Relationships()
        rels.add(type: RelType.slideMaster, target: "../slideMasters/slideMaster1.xml")
        return rels.xml
    }

    private static let notesMaster = XMLText.declaration
        + "<p:notesMaster \(namespaces)><p:cSld>"
        + "<p:bg><p:bgRef idx=\"1001\"><a:schemeClr val=\"bg1\"/></p:bgRef></p:bg>"
        + "<p:spTree>\(groupProperties)</p:spTree></p:cSld>"
        + "<p:clrMap \(colorMap)/></p:notesMaster>"

    private static var notesMasterRels: String {
        var rels = Relationships()
        rels.add(type: RelType.theme, target: "../theme/theme2.xml")
        return rels.xml
    }

    /// A complete Office theme. Every element here is required by the schema — a theme missing its
    /// format scheme is one PowerPoint offers to repair — even though the slides never refer to it:
    /// every colour and font they use is written out explicitly.
    private static func theme(name: String) -> String {
        func system(_ key: String, _ name: String, _ last: String) -> String {
            "<a:\(key)><a:sysClr val=\"\(name)\" lastClr=\"\(last)\"/></a:\(key)>"
        }
        func rgb(_ key: String, _ hex: String) -> String {
            "<a:\(key)><a:srgbClr val=\"\(hex)\"/></a:\(key)>"
        }
        func fonts(_ key: String, _ latin: String) -> String {
            "<a:\(key)><a:latin typeface=\"\(latin)\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:\(key)>"
        }
        let placeholderFill = "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
        let line = "<a:ln w=\"6350\">\(placeholderFill)</a:ln>"
        let effect = "<a:effectStyle><a:effectLst/></a:effectStyle>"

        return XMLText.declaration
            + "<a:theme xmlns:a=\"\(OOXMLNamespace.a)\" name=\"\(name)\"><a:themeElements>"
            + "<a:clrScheme name=\"Neutrino\">"
            + system("dk1", "windowText", "000000") + system("lt1", "window", "FFFFFF")
            + rgb("dk2", "1F2937") + rgb("lt2", "F3F4F6")
            + rgb("accent1", "6366F1") + rgb("accent2", "8B5CF6") + rgb("accent3", "EC4899")
            + rgb("accent4", "F59E0B") + rgb("accent5", "10B981") + rgb("accent6", "3B82F6")
            + rgb("hlink", "2563EB") + rgb("folHlink", "7C3AED")
            + "</a:clrScheme>"
            + "<a:fontScheme name=\"Neutrino\">" + fonts("majorFont", "Inter") + fonts("minorFont", "Inter")
            + "</a:fontScheme>"
            + "<a:fmtScheme name=\"Neutrino\">"
            + "<a:fillStyleLst>\(placeholderFill)\(placeholderFill)\(placeholderFill)</a:fillStyleLst>"
            + "<a:lnStyleLst>\(line)\(line)\(line)</a:lnStyleLst>"
            + "<a:effectStyleLst>\(effect)\(effect)\(effect)</a:effectStyleLst>"
            + "<a:bgFillStyleLst>\(placeholderFill)\(placeholderFill)\(placeholderFill)</a:bgFillStyleLst>"
            + "</a:fmtScheme></a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>"
    }

    // MARK: - Shared fragments

    private static let namespaces = "xmlns:a=\"\(OOXMLNamespace.a)\" xmlns:r=\"\(OOXMLNamespace.r)\""
        + " xmlns:p=\"\(PresentationNamespace.p)\""

    private static let groupProperties =
        "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>"
        + "<p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/>"
        + "<a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"
}

// MARK: - PresentationML vocabulary

/// The PresentationML namespace. Not in `OOXMLNamespace`, which holds what the shared package's own
/// docx code uses; slides is the only app that speaks this one.
enum PresentationNamespace {
    static let p = "http://schemas.openxmlformats.org/presentationml/2006/main"
}

/// Relationship types for the parts a deck is made of.
enum RelType {
    private static let base = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static let slide = "\(base)/slide"
    static let slideLayout = "\(base)/slideLayout"
    static let slideMaster = "\(base)/slideMaster"
    static let notesSlide = "\(base)/notesSlide"
    static let notesMaster = "\(base)/notesMaster"
    static let theme = "\(base)/theme"
    static let image = "\(base)/image"
    static let presProps = "\(base)/presProps"
    static let viewProps = "\(base)/viewProps"
    static let tableStyles = "\(base)/tableStyles"
}

// MARK: - Relationships

/// One `.rels` part being built, numbering its ids in the order relationships are added.
private struct Relationships {

    private var entries: [(id: String, type: String, target: String)] = []

    @discardableResult
    mutating func add(type: String, target: String) -> String {
        let id = "rId\(entries.count + 1)"
        entries.append((id, type, target))
        return id
    }

    var xml: String {
        XMLText.declaration
            + "<Relationships xmlns=\"\(OOXMLNamespace.packageRels)\">"
            + entries.map {
                "<Relationship Id=\"\($0.id)\" Type=\"\($0.type)\" Target=\"\(XMLText.attributeValue($0.target))\"/>"
            }.joined()
            + "</Relationships>"
    }
}

// MARK: - MediaStore

/// The pictures a deck embeds, deduplicated: a logo on every slide is stored once.
private struct MediaStore {

    struct Item {
        let fileName: String
        let data: Data
    }

    private(set) var items: [Item] = []
    private var bySource: [String: String] = [:]
    /// Extension → content type, in the order first seen, for `[Content_Types].xml`.
    private(set) var extensions: [(String, String)] = []

    /// Stores the picture in a `data:` URL and returns its file name under `ppt/media/`, or nil when
    /// `source` is not a `data:` URL this can decode.
    mutating func add(dataURL source: String) -> String? {
        if let existing = bySource[source] { return existing }
        guard let (mime, data) = Self.decode(source),
              let ext = Self.fileExtensions[mime] else { return nil }
        let name = "image\(items.count + 1).\(ext)"
        items.append(Item(fileName: name, data: data))
        bySource[source] = name
        if !extensions.contains(where: { $0.0 == ext }) { extensions.append((ext, mime)) }
        return name
    }

    private static let fileExtensions = [
        "image/png": "png", "image/jpeg": "jpeg", "image/jpg": "jpeg", "image/gif": "gif",
        "image/bmp": "bmp", "image/tiff": "tiff", "image/svg+xml": "svg", "image/webp": "webp",
    ]

    private static func decode(_ source: String) -> (String, Data)? {
        guard source.hasPrefix("data:"), let comma = source.firstIndex(of: ",") else { return nil }
        let header = source[source.index(source.startIndex, offsetBy: 5)..<comma]
        let parts = header.split(separator: ";").map(String.init)
        guard let mime = parts.first?.lowercased(), parts.contains("base64"),
              let data = Data(base64Encoded: String(source[source.index(after: comma)...]),
                              options: .ignoreUnknownCharacters) else { return nil }
        return (mime, data)
    }
}

// MARK: - CSSPaint

/// Turns the CSS a deck stores into colours DrawingML can carry.
///
/// A pared-down sibling of `CSSColor`, which is UIKit-backed and main-actor isolated because it
/// feeds the renderer. The codec has to run anywhere — in a test, off the main thread — and only
/// ever needs sRGB hex plus an alpha, so it parses that and nothing more.
enum CSSPaint {

    struct RGBA: Equatable {
        /// Six upper-case hex digits, no `#`.
        var hex: String
        var alpha: Double
    }

    struct Gradient: Equatable {
        struct Stop: Equatable {
            var color: RGBA
            /// 0…100.
            var position: Double
        }
        /// CSS degrees: 0 is "to top", 90 "to right".
        var angle: Double
        var stops: [Stop]
    }

    /// A CSS colour, or nil for `transparent`, `none` and anything unrecognised.
    static func color(_ css: String?) -> RGBA? {
        guard let css else { return nil }
        let value = css.trimmingCharacters(in: .whitespaces).lowercased()
        if value.hasPrefix("#") { return hexColor(String(value.dropFirst())) }
        if value.hasPrefix("rgb") { return functionalColor(value) }
        return named[value].flatMap { hexColor($0) }
    }

    /// A `linear-gradient(…)` with at least two stops it could read, or nil.
    static func gradient(_ css: String?) -> Gradient? {
        guard let css else { return nil }
        let value = css.trimmingCharacters(in: .whitespaces)
        guard value.lowercased().hasPrefix("linear-gradient("), value.hasSuffix(")"),
              let open = value.firstIndex(of: "(") else { return nil }
        let inner = String(value[value.index(after: open)..<value.index(before: value.endIndex)])
        var parts = splitTopLevel(inner)
        guard !parts.isEmpty else { return nil }

        var angle = 180.0
        let first = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
        if first.hasSuffix("deg"), let degrees = Double(first.dropLast(3)) {
            angle = degrees
            parts.removeFirst()
        } else if first.hasPrefix("to ") {
            angle = directions[first] ?? 180
            parts.removeFirst()
        }

        var stops: [(RGBA, Double?)] = []
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            // The position is the last token when it ends in `%`; the colour is everything before
            // it, which keeps `rgb(1 2 3) 40%` intact.
            var colorText = trimmed
            var position: Double?
            if let space = trimmed.lastIndex(of: " "), trimmed.hasSuffix("%"),
               let percent = Double(trimmed[trimmed.index(after: space)...].dropLast()) {
                colorText = String(trimmed[..<space])
                position = percent
            }
            if let color = color(colorText) { stops.append((color, position)) }
        }
        guard stops.count >= 2 else { return nil }

        let resolved = stops.enumerated().map { index, stop in
            Gradient.Stop(color: stop.0,
                          position: stop.1 ?? Double(index) / Double(stops.count - 1) * 100)
        }
        return Gradient(angle: angle, stops: resolved)
    }

    private static func hexColor(_ digits: String) -> RGBA? {
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        let expanded: String
        switch digits.count {
        case 3, 4: expanded = digits.map { "\($0)\($0)" }.joined()
        case 6, 8: expanded = digits
        default:   return nil
        }
        let hex = String(expanded.prefix(6)).uppercased()
        guard expanded.count == 8, let alpha = UInt8(expanded.suffix(2), radix: 16) else {
            return RGBA(hex: hex, alpha: 1)
        }
        return RGBA(hex: hex, alpha: Double(alpha) / 255)
    }

    private static func functionalColor(_ css: String) -> RGBA? {
        guard let open = css.firstIndex(of: "("), let close = css.lastIndex(of: ")") else { return nil }
        let tokens = css[css.index(after: open)..<close]
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .map(String.init)
        guard tokens.count >= 3 else { return nil }
        func channel(_ token: String) -> Int? {
            if token.hasSuffix("%"), let percent = Double(token.dropLast()) {
                return Int((percent / 100 * 255).rounded())
            }
            return Double(token).map { Int($0.rounded()) }
        }
        guard let r = channel(tokens[0]), let g = channel(tokens[1]), let b = channel(tokens[2]) else {
            return nil
        }
        var alpha = 1.0
        if tokens.count >= 4 {
            let token = tokens[3]
            alpha = token.hasSuffix("%") ? (Double(token.dropLast()) ?? 100) / 100 : Double(token) ?? 1
        }
        let hex = [r, g, b].map { String(format: "%02X", min(255, max(0, $0))) }.joined()
        return RGBA(hex: hex, alpha: min(1, max(0, alpha)))
    }

    private static func splitTopLevel(_ string: String) -> [String] {
        var parts: [String] = []
        var depth = 0
        var current = ""
        for character in string {
            switch character {
            case "(": depth += 1; current.append(character)
            case ")": depth -= 1; current.append(character)
            case "," where depth == 0:
                parts.append(current)
                current = ""
            default: current.append(character)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(current) }
        return parts
    }

    private static let directions: [String: Double] = [
        "to top": 0, "to right": 90, "to bottom": 180, "to left": 270,
        "to top right": 45, "to right top": 45, "to bottom right": 135, "to right bottom": 135,
        "to bottom left": 225, "to left bottom": 225, "to top left": 315, "to left top": 315,
    ]

    /// The named colours the web palette and the importer's `PRST_COLORS` actually produce.
    private static let named: [String: String] = [
        "white": "ffffff", "black": "000000", "red": "ff0000", "green": "008000",
        "blue": "0000ff", "yellow": "ffff00", "cyan": "00ffff", "magenta": "ff00ff",
        "orange": "ffa500", "purple": "800080", "gray": "808080", "grey": "808080",
        "darkgray": "a9a9a9", "lightgray": "d3d3d3", "brown": "a52a2a", "steelblue": "4682b4",
    ]
}
