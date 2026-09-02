import SwiftUI

// MARK: - ElementFormatBar

/// The one-tap controls for the selected element, under the canvas.
///
/// Under rather than over, for the reason a spreadsheet's format bar is: it is used with a thumb
/// while the eye is on the slide, and a bar at the top puts the controls at the far end of the
/// reach from the work.
///
/// What it offers depends on what is selected — a text box gets type controls, a shape gets a fill,
/// an element this build only preserves gets arrangement and delete and nothing else. Controls that
/// would do nothing are *absent*, not disabled: a row of greyed-out buttons is a worse answer to
/// "what can I do with this?" than a shorter row.
struct ElementFormatBar: View {

    // MARK: - Input

    let element: SlideElement?
    let perform: (ElementCommand) -> Void
    let onEditText: (String) -> Void
    let onMoreText: () -> Void
    let onShapes: () -> Void

    // MARK: - State

    @State private var colorTarget: ColorTarget?

    private enum ColorTarget: String, Identifiable {
        case textColor, shapeFill, lineStroke
        var id: String { rawValue }

        var title: String {
            switch self {
            case .textColor:  return "Text Colour"
            case .shapeFill:  return "Fill"
            case .lineStroke: return "Line Colour"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                if let element {
                    switch element {
                    case .text(let text): textControls(text)
                    case .shape:          shapeControls()
                    case .line(let line): lineControls(line)
                    // An image or an element this build only preserves has no styling controls
                    // here; both can still be moved, arranged and deleted.
                    case .image, .opaque: EmptyView()
                    }

                    Divider().frame(height: 24).padding(.horizontal, 4)

                    arrangeControls
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(.systemBackground))
        .sheet(item: $colorTarget) { target in
            ColorPickerSheet(title: target.title, selected: currentColor(for: target),
                             clearLabel: nil) { hex in
                guard let hex else { return }
                switch target {
                case .textColor:  perform(.style(.color(hex), name: "Text Colour"))
                case .shapeFill:  perform(.shapeFill(hex))
                case .lineStroke: perform(.lineStroke(hex, width: nil))
                }
            }
        }
    }

    // MARK: - Text

    @ViewBuilder
    private func textControls(_ text: TextElement) -> some View {
        button("Edit", systemImage: "character.cursor.ibeam") { onEditText(text.id) }

        toggle("Bold", systemImage: "bold", isOn: text.style.bold) {
            perform(.style(TextStylePatch(bold: !text.style.bold), name: "Bold"))
        }
        toggle("Italic", systemImage: "italic", isOn: text.style.italic) {
            perform(.style(TextStylePatch(italic: !text.style.italic), name: "Italic"))
        }
        toggle("Underline", systemImage: "underline", isOn: text.style.underline) {
            perform(.style(TextStylePatch(underline: !text.style.underline), name: "Underline"))
        }

        button("Smaller", systemImage: "textformat.size.smaller") {
            perform(.stepFontSize(-TextStylePatch.fontSizeStep))
        }
        button("Bigger", systemImage: "textformat.size.larger") {
            perform(.stepFontSize(TextStylePatch.fontSizeStep))
        }

        alignControls(text.style.align)

        button("Colour", systemImage: "paintpalette") { colorTarget = .textColor }
        button("More", systemImage: "ellipsis.circle") { onMoreText() }
    }

    @ViewBuilder
    private func alignControls(_ align: String) -> some View {
        toggle("Align Left", systemImage: "text.alignleft", isOn: align == "left") {
            perform(.style(.align("left"), name: "Align Left"))
        }
        toggle("Align Centre", systemImage: "text.aligncenter", isOn: align == "center") {
            perform(.style(.align("center"), name: "Align Centre"))
        }
        toggle("Align Right", systemImage: "text.alignright", isOn: align == "right") {
            perform(.style(.align("right"), name: "Align Right"))
        }
    }

    // MARK: - Shapes

    @ViewBuilder
    private func shapeControls() -> some View {
        button("Fill", systemImage: "paintbrush.fill") { colorTarget = .shapeFill }
        button("Shape", systemImage: "square.on.circle") { onShapes() }
    }

    // MARK: - Lines

    @ViewBuilder
    private func lineControls(_ line: LineElement) -> some View {
        button("Colour", systemImage: "paintbrush") { colorTarget = .lineStroke }
        button("Thinner", systemImage: "minus") {
            perform(.lineStroke(nil, width: max(0.5, line.strokeWidth - 1)))
        }
        button("Thicker", systemImage: "plus") {
            perform(.lineStroke(nil, width: min(24, line.strokeWidth + 1)))
        }
    }

    // MARK: - Arrangement

    @ViewBuilder
    private var arrangeControls: some View {
        Menu {
            Button { perform(.bringForward) } label: {
                Label("Bring Forward", systemImage: "square.2.layers.3d.top.filled")
            }
            Button { perform(.sendBackward) } label: {
                Label("Send Backward", systemImage: "square.2.layers.3d.bottom.filled")
            }
            Button { perform(.bringToFront) } label: {
                Label("Bring to Front", systemImage: "square.3.layers.3d.top.filled")
            }
            Button { perform(.sendToBack) } label: {
                Label("Send to Back", systemImage: "square.3.layers.3d.bottom.filled")
            }
            Divider()
            Button { perform(.duplicate) } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
        } label: {
            barLabel("Arrange", systemImage: "square.stack.3d.up")
        }
        .accessibilityLabel("Arrange")

        button("Delete", systemImage: "trash", role: .destructive) { perform(.delete) }
    }

    // MARK: - Controls

    private func button(_ title: String, systemImage: String, role: ButtonRole? = nil,
                        action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            barLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func toggle(_ title: String, systemImage: String, isOn: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            barLabel(title, systemImage: systemImage)
                .background(isOn ? Color.accentColor.opacity(0.18) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func barLabel(_ title: String, systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 15))
            .frame(width: 38, height: 30)
            .contentShape(Rectangle())
    }

    // MARK: - Current values

    private func currentColor(for target: ColorTarget) -> String? {
        switch target {
        case .textColor:  return element?.text?.style.color
        case .shapeFill:  return element?.shape?.fill
        case .lineStroke: return element?.line?.stroke
        }
    }
}

// MARK: - TextFormatSheet

/// Everything the format bar has no room for: the exact size, the font, spacing, lists, highlight
/// and the two decorations that are not on the bar.
struct TextFormatSheet: View {

    // MARK: - Input

    let style: TextStyle?
    let perform: (ElementCommand) -> Void

    // MARK: - State

    @Environment(\.dismiss) private var dismiss
    @State private var showTextColor = false
    @State private var showHighlight = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                if let style {
                    sizeSection(style)
                    fontSection(style)
                    styleSection(style)
                    listSection(style)
                    colourSection(style)
                } else {
                    Text("Select a text box to format it.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showTextColor) {
                ColorPickerSheet(title: "Text Colour", selected: style?.color,
                                 clearLabel: nil) { hex in
                    if let hex { perform(.style(.color(hex), name: "Text Colour")) }
                }
            }
            .sheet(isPresented: $showHighlight) {
                ColorPickerSheet(title: "Highlight", selected: style?.backgroundColor,
                                 clearLabel: "No Highlight") { hex in
                    perform(.style(.highlight(hex), name: "Highlight"))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sections

    private func sizeSection(_ style: TextStyle) -> some View {
        Section("Size") {
            HStack {
                Text("\(Int(style.fontSize)) pt")
                    .monospacedDigit()
                Spacer()
                Stepper("Size", value: Binding(
                    get: { style.fontSize },
                    set: { perform(.style(.size($0), name: "Text Size")) }
                ), in: TextStylePatch.fontSizeRange, step: TextStylePatch.fontSizeStep)
                .labelsHidden()
            }
        }
    }

    private func fontSection(_ style: TextStyle) -> some View {
        Section {
            Picker("Font", selection: Binding(
                get: { style.fontFamily },
                set: { perform(.style(.fontFamily($0), name: "Font")) }
            )) {
                // A family the deck holds but the list does not is added, so opening the picker on
                // a deck styled with a web font does not silently restyle it on the way out.
                ForEach(fontOptions(current: style.fontFamily), id: \.self) { family in
                    Text(FontFamilies.displayName(family)).tag(family)
                }
            }
        } footer: {
            Text("The name is stored as written, so the web app can find the same face. A font this "
                 + "device doesn\u{2019}t have falls back to the system one here and still looks "
                 + "right in a browser that does.")
        }
    }

    private func fontOptions(current: String) -> [String] {
        FontFamilies.all.contains(current) ? FontFamilies.all : [current] + FontFamilies.all
    }

    private func styleSection(_ style: TextStyle) -> some View {
        Section("Style") {
            Toggle("Bold", isOn: binding(style.bold) { TextStylePatch(bold: $0) })
            Toggle("Italic", isOn: binding(style.italic) { TextStylePatch(italic: $0) })
            Toggle("Underline", isOn: binding(style.underline) { TextStylePatch(underline: $0) })
            Toggle("Strikethrough", isOn: binding(style.isStrikethrough) {
                TextStylePatch(strikethrough: .some($0))
            })
            Toggle("Shadow", isOn: binding(style.shadow == true) {
                TextStylePatch(shadow: .some($0))
            })
        }
    }

    private func listSection(_ style: TextStyle) -> some View {
        Section {
            Picker("List", selection: Binding(
                get: { style.listType ?? "none" },
                set: { perform(.style(.list($0 == "none" ? nil : $0), name: "List")) }
            )) {
                Text("None").tag("none")
                Text("Bulleted").tag("bullet")
                Text("Numbered").tag("numbered")
            }
        } footer: {
            Text("Each line of the text box becomes one item.")
        }
    }

    private func colourSection(_ style: TextStyle) -> some View {
        Section("Colour") {
            Button {
                showTextColor = true
            } label: {
                LabeledContent("Text") {
                    swatch(style.color)
                }
            }
            Button {
                showHighlight = true
            } label: {
                LabeledContent("Highlight") {
                    swatch(style.backgroundColor)
                }
            }
        }
    }

    // MARK: - Pieces

    private func swatch(_ css: String?) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(CSSColor.color(css) ?? .clear)
            .frame(width: 28, height: 20)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(.separator)))
    }

    private func binding(_ value: Bool,
                         patch: @escaping (Bool) -> TextStylePatch) -> Binding<Bool> {
        Binding(get: { value }, set: { perform(.style(patch($0), name: "Text Style")) })
    }
}
