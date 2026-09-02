import SwiftUI

// MARK: - LayoutGalleryView

/// Epic 8 — the layout gallery.
///
/// Each card draws the layout's own preview rectangles rather than a rendered slide. That is what
/// the web app does, and it is the right call for a phone as well: rendering ten real slides to
/// pick one is a lot of work to show ten grey boxes, and the abstraction reads *better* — the card
/// says "title, then bullets", which is the choice being made.
struct LayoutGalleryView: View {

    let theme: SlideTheme
    let master: SlideMaster
    let onApply: (SlideLayout) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(SlideLayouts.all) { layout in
                        Button {
                            onApply(layout)
                            dismiss()
                        } label: {
                            VStack(spacing: 6) {
                                LayoutPreview(layout: layout)
                                Text(layout.name)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(layout.name) layout")
                    }
                }
                .padding(16)
            }
            .navigationTitle("Layout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Applying a layout replaces what is on this slide. Undo puts it back.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
    }
}

// MARK: - LayoutPreview

/// One layout's card: its rectangles, drawn in the 160×90 space they are authored in.
struct LayoutPreview: View {

    let layout: SlideLayout

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / SlideLayout.previewSize.width
            ZStack(alignment: .topLeading) {
                Color(.systemBackground)
                ForEach(Array(layout.preview.enumerated()), id: \.offset) { _, rect in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color(for: rect.ink))
                        .frame(width: rect.w * scale, height: rect.h * scale)
                        .offset(x: rect.x * scale, y: rect.y * scale)
                }
                if layout.preview.isEmpty {
                    Text("Blank")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .aspectRatio(SlideGeometry.aspectRatio, contentMode: .fit)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(.separator)))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    /// The web app's four preview inks, as roles rather than hex — so the card is legible in Dark
    /// Mode, where its light greys would be invisible.
    private func color(for ink: SlideLayout.PreviewInk) -> Color {
        switch ink {
        case .title:     return Color.accentColor
        case .body:      return Color(.tertiaryLabel)
        case .box:       return Color(.quaternaryLabel)
        case .subtitle:  return Color(.secondaryLabel)
        case .accent:    return Color.accentColor.opacity(0.6)
        case .alternate: return Color.green.opacity(0.6)
        }
    }
}

// MARK: - ThemeGalleryView

/// Epic 10 — the theme gallery, backed by `/api/v1/slides/themes` with the built-ins always
/// present.
struct ThemeGalleryView: View {

    let current: SlideTheme
    let onApply: (SlideTheme) -> Void

    @EnvironmentObject private var themeService: SlideThemeService
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(themeService.galleryThemes, id: \.name) { theme in
                        Button {
                            onApply(theme)
                            dismiss()
                        } label: {
                            ThemeCard(theme: theme, isCurrent: theme.name == current.name)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(theme.name) theme")
                    }
                }
                .padding(16)
            }
            .navigationTitle("Theme")
            .navigationBarTitleDisplayMode(.inline)
            .task { await themeService.load() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("A theme restyles every slide: backgrounds, text colour, font and shape fills. "
                     + "Your words, positions and sizes are left alone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
    }
}

// MARK: - ThemeCard

/// A theme, shown as the slide it would produce rather than as a row of swatches — which is the
/// question being asked: "what will my deck look like?"
struct ThemeCard: View {

    let theme: SlideTheme
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let size = CGSize(width: proxy.size.width,
                                  height: proxy.size.width / SlideGeometry.aspectRatio)
                SlideCanvasView(slide: sampleSlide, theme: theme, size: size, showsBorder: true)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 2)
                    )
            }
            .aspectRatio(SlideGeometry.aspectRatio, contentMode: .fit)

            HStack(spacing: 4) {
                Text(theme.name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    /// A title and a line of body text, styled by the theme — the smallest slide that shows what a
    /// theme decides.
    private var sampleSlide: Slide {
        Slide(
            background: theme.slideBackground,
            elements: [
                .text(TextElement(
                    frame: SlideFrame(x: 8, y: 20, w: 84, h: 26),
                    content: "Title",
                    style: TextStyle(fontSize: 40, bold: true, color: theme.textColor,
                                     align: "left", fontFamily: theme.fontFamily)
                )),
                .shape(ShapeElement(
                    shape: "rect", frame: SlideFrame(x: 8, y: 50, w: 40, h: 3),
                    fill: theme.primaryColor, stroke: "transparent", strokeWidth: 0
                )),
                .text(TextElement(
                    frame: SlideFrame(x: 8, y: 58, w: 84, h: 20),
                    content: "Body text",
                    style: TextStyle(fontSize: 24, color: theme.textColor, align: "left",
                                     fontFamily: theme.fontFamily)
                )),
            ]
        )
    }
}

// MARK: - BackgroundPickerView

/// Epic 10 — the per-slide background: a colour, one of the web app's preset gradients, a gradient
/// typed by hand, or an image URL.
///
/// The four are one picker rather than four buttons because they are one field: a slide has exactly
/// one background, and choosing a gradient means *not* having a colour.
struct BackgroundPickerView: View {

    let background: SlideBackground
    let theme: SlideTheme
    let onPick: (SlideBackground) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var custom: Color = .white
    @State private var customGradient: String = ""
    @State private var imageURL: String = ""

    private let gradientColumns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        NavigationStack {
            Form {
                currentSection
                colorSection
                gradientSection
                customSection
            }
            .navigationTitle("Background")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                custom = CSSColor.color(background.isColor ? background.value : nil) ?? .white
                if CSSColor.isGradient(background.value) { customGradient = background.value }
                if background.isImage { imageURL = background.value }
            }
        }
    }

    // MARK: - Sections

    private var currentSection: some View {
        Section("Current") {
            HStack(spacing: 12) {
                SlideBackgroundView(background: background, theme: theme)
                    .frame(width: 72, height: 72 / SlideGeometry.aspectRatio)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(.separator)))
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var colorSection: some View {
        Section("Colour") {
            ColorPicker("Solid Colour", selection: $custom, supportsOpacity: false)
                .onChange(of: custom) { pick(.color(CSSColor.hex(from: $0))) }

            Button("Use the Theme\u{2019}s Background") {
                pick(theme.slideBackground)
            }
        }
    }

    private var gradientSection: some View {
        Section("Gradients") {
            LazyVGrid(columns: gradientColumns, spacing: 10) {
                ForEach(SlideGradients.presets, id: \.self) { preset in
                    Button {
                        // Stored as `type: "color"` with a gradient value, which is what the web
                        // app writes and reads. See `SlideTheme.slideBackground`.
                        pick(.color(preset))
                    } label: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(CSSColor.gradient(preset)?.linearGradient
                                  ?? LinearGradient(colors: [.gray], startPoint: .top,
                                                    endPoint: .bottom))
                            .frame(height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(background.value == preset
                                                  ? Color.accentColor : Color(.separator),
                                                  lineWidth: background.value == preset ? 3 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Gradient")
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var customSection: some View {
        Section {
            TextField("linear-gradient(135deg, #000 0%, #fff 100%)", text: $customGradient)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.system(.footnote, design: .monospaced))
            Button("Use This Gradient") {
                pick(.color(customGradient.trimmingCharacters(in: .whitespaces)))
            }
            .disabled(CSSColor.gradient(customGradient) == nil)

            TextField("https://example.com/background.jpg", text: $imageURL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .font(.system(.footnote, design: .monospaced))
            Button("Use This Image") {
                pick(.image(imageURL.trimmingCharacters(in: .whitespaces)))
            }
            .disabled(URL(string: imageURL)?.scheme?.hasPrefix("http") != true)
        } header: {
            Text("Custom")
        } footer: {
            Text("A gradient has to be CSS the web app can paint too, so it is checked before it "
                 + "can be applied. An image set here is a link, not a copy \u{2014} it has to stay "
                 + "reachable for the slide to show it.")
        }
    }

    // MARK: - Actions

    private func pick(_ background: SlideBackground) {
        onPick(background)
        dismiss()
    }

    private var description: String {
        if background.isImage { return background.value }
        if CSSColor.isGradient(background.value) { return "Gradient" }
        return background.value
    }
}

// MARK: - TransitionPickerView

/// Epic 10 — how this slide arrives.
struct TransitionPickerView: View {

    let current: SlideTransition
    let onPick: (SlideTransition) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(SlideTransition.allCases) { transition in
                Button {
                    onPick(transition)
                    dismiss()
                } label: {
                    HStack {
                        Label(transition.displayName, systemImage: transition.iconName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if transition == current {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
            .navigationTitle("Transition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Transitions play when presenting. The ones this app does not animate itself "
                     + "\u{2014} cube, gallery, pixelate \u{2014} still travel with the deck and "
                     + "play on the web.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
    }
}

// MARK: - ShapePickerView

/// Epic 7 — the shape catalog, grouped as the web app groups it.
struct ShapePickerView: View {

    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(ShapeCatalog.Group.allCases) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.displayName)
                                .font(.subheadline.weight(.semibold))
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(ShapeCatalog.entries(in: group)) { entry in
                                    Button {
                                        onPick(entry.key)
                                        dismiss()
                                    } label: {
                                        ShapeSwatch(entry: entry)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(entry.label)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Shape")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - ShapeSwatch

private struct ShapeSwatch: View {

    let entry: ShapeCatalog.Entry

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                Path(ShapeCatalog.cgPath(for: entry.key,
                                         in: CGRect(origin: .zero, size: proxy.size)))
                    .fill(Color.accentColor.opacity(0.8))
            }
            .frame(height: 48)
            Text(entry.label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(4)
    }
}
