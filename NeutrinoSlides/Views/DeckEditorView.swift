import SwiftUI

// MARK: - DeckEditorView

/// One open presentation: the canvas, the thumbnail rail, and everything that acts on them.
///
/// Epic 5 renders it, Epic 6 loads and saves it, and Epics 7–10 turn it into an editor — tap to
/// select, drag to move, pull a handle to resize, type into a text box, add slides, apply layouts
/// and themes. Rendering lives in ``SlideCanvasView``; state lives in ``DeckEditorModel``; this
/// view is the SwiftUI shell that connects them.
struct DeckEditorView: View {

    // MARK: - Input

    let item: SlideItem

    // MARK: - Environment

    @EnvironmentObject private var contentService: SlideContentService
    @EnvironmentObject private var driveService: SlidesDriveService
    @EnvironmentObject private var themeService: SlideThemeService
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - State

    @StateObject private var model: DeckEditorModel

    /// The frame an in-progress drag or resize would land on. Held here rather than written into
    /// the deck on every gesture change: a drag across the slide is one undo step, not sixty, and
    /// the canvas needs somewhere to draw the element while it is being moved.
    @State private var draft: Draft?

    @State private var editingText: EditingText?
    @State private var showRename = false
    @State private var showLayouts = false
    @State private var showThemes = false
    @State private var showBackground = false
    @State private var showTransitions = false
    @State private var showShapes = false
    @State private var showTextFormat = false
    @State private var showPresenter = false

    struct Draft: Equatable {
        let elementID: String
        var frame: SlideFrame
        /// Nil while moving; the handle being pulled while resizing.
        var handle: ResizeHandle?
    }

    /// The text box being typed into, and what has been typed so far. Held as one value so the
    /// sheet cannot open pointing at an element that has since been deleted.
    struct EditingText: Identifiable {
        let id: String
        var content: String
    }

    // MARK: - Init

    init(item: SlideItem) {
        self.item = item
        // The model needs services the environment cannot supply this early, so it is built with
        // placeholders and re-pointed in `.task`. Constructing it here rather than lazily is what
        // keeps it alive across the view's re-evaluations.
        _model = StateObject(wrappedValue: DeckEditorModel(
            item: item, contentService: SlideContentService(), driveService: nil
        ))
    }

    // MARK: - Body

    var body: some View {
        content
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task { await load() }
            // A `.task` rather than a loose `Task {}`: SwiftUI cancels it when the view goes away,
            // and a detached timer would go on saving a deck nobody has open.
            .task { await autosaveLoop() }
            .onDisappear { flush() }
            .onChange(of: scenePhase) { phase in
                // Epic 6 — "Save on background/terminate". `.inactive` fires first and is the last
                // moment the app is reliably given time to finish a request.
                if phase != .active { flush() }
            }
            .sheet(isPresented: $showRename) { RenameSheet(item: item) }
            .sheet(isPresented: $showLayouts) {
                LayoutGalleryView(theme: model.theme, master: model.master) { layout in
                    model.applyLayout(layout)
                    model.saveIfNeeded()
                }
            }
            .sheet(isPresented: $showThemes) {
                ThemeGalleryView(current: model.theme) { theme in
                    model.applyTheme(theme)
                    model.saveIfNeeded()
                }
            }
            .sheet(isPresented: $showBackground) {
                BackgroundPickerView(background: model.currentSlide?.background ?? .color("#ffffff"),
                                     theme: model.theme) { background in
                    model.setBackground(background)
                    model.saveIfNeeded()
                }
            }
            .sheet(isPresented: $showTransitions) {
                TransitionPickerView(
                    current: SlideTransition(stored: model.currentSlide?.transition ?? "")
                ) { transition in
                    model.setTransition(transition)
                    model.saveIfNeeded()
                }
            }
            .sheet(isPresented: $showShapes) {
                ShapePickerView { key in
                    model.addShape(key)
                    model.saveIfNeeded()
                }
            }
            .sheet(isPresented: $showTextFormat) {
                TextFormatSheet(style: model.selectedElement?.text?.style,
                                perform: perform)
            }
            .sheet(item: $editingText) { editing in
                TextEntrySheet(text: editing.content) { committed in
                    model.setText(committed, forElement: editing.id)
                    model.saveIfNeeded()
                }
            }
            .fullScreenCover(isPresented: $showPresenter) {
                if let deck = model.deck {
                    PresenterView(deck: deck, startIndex: model.selectedSlideIndex,
                                  advanceSeconds: settings.advanceSeconds,
                                  keepsScreenAwake: settings.keepScreenAwake)
                }
            }
            .alert(item: $model.conflict) { conflict in
                conflictAlert(conflict)
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.deck == nil {
            ProgressView("Opening\u{2026}")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError = model.loadError {
            errorState(loadError)
        } else {
            VStack(spacing: 0) {
                canvas

                if model.isEditable, model.selectedElement != nil {
                    Divider()
                    ElementFormatBar(element: model.selectedElement,
                                     perform: perform,
                                     onEditText: beginTextEditing,
                                     onMoreText: { showTextFormat = true },
                                     onShapes: { showShapes = true })
                }

                if settings.showNotes {
                    Divider()
                    SpeakerNotesView(notes: model.currentSlide?.notes ?? "",
                                     isEditable: model.isEditable) { notes in
                        model.setNotes(notes)
                    }
                }

                if settings.showThumbnails {
                    Divider()
                    SlideThumbnailRail(slides: model.slides,
                                       theme: model.theme,
                                       selectedIndex: model.selectedSlideIndex,
                                       isEditable: model.isEditable,
                                       onSelect: { model.selectSlide(at: $0) },
                                       onMove: { source, destination in
                                           model.moveSlide(from: source, to: destination)
                                           model.saveIfNeeded()
                                       })
                }

                statusBar
            }
        }
    }

    // MARK: - Canvas

    /// The slide itself, with the selection overlay on top.
    ///
    /// Laid out from the available space rather than at a fixed size, because a slide is 16:9 and
    /// the space it gets is not: ``SlideGeometry/canvasSize(fitting:)`` letterboxes it, and every
    /// gesture converts through that same size so a drag lands where the finger is.
    private var canvas: some View {
        GeometryReader { proxy in
            let size = SlideGeometry.canvasSize(fitting: proxy.size)
            ZStack {
                if let slide = model.currentSlide {
                    SlideCanvasView(slide: slide, theme: model.theme, size: size, showsBorder: true)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            selectElement(at: location, in: size)
                        }
                        .overlay {
                            if model.isEditable {
                                SelectionOverlay(
                                    slide: slide,
                                    selectedID: model.selectedElementID,
                                    draft: draft,
                                    canvasSize: size,
                                    snapStep: settings.snapStep,
                                    showsGuides: settings.showSnapGuides,
                                    onDraft: { draft = $0 },
                                    onCommit: commitDraft,
                                    onActivate: beginTextEditing
                                )
                                .frame(width: size.width, height: size.height)
                            }
                        }
                } else {
                    Color(.secondarySystemBackground)
                        .frame(width: size.width, height: size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Status bar

    /// Where the deck says what it is doing: which slide, whether there is anything unsaved, and
    /// whatever the last command wanted to say.
    private var statusBar: some View {
        HStack(spacing: 12) {
            if let notice = model.notice {
                Label(notice, systemImage: "info.circle")
                    .lineLimit(1)
            } else if !model.isEditable, model.info != nil {
                Label("Read-only", systemImage: "eye")
            } else {
                Text("Slide \(model.selectedSlideIndex + 1) of \(max(1, model.slides.count))")
            }

            Spacer()

            if let saveError = model.saveError {
                Label(saveError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else if model.isSaving {
                Label("Saving\u{2026}", systemImage: "arrow.up.circle")
            } else if model.hasUnsavedChanges {
                Label("Unsaved", systemImage: "circle.dashed")
            } else if model.info != nil {
                Label("Saved", systemImage: "checkmark.circle")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
    }

    // MARK: - Error state

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Couldn\u{2019}t open this presentation")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await model.load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if model.isEditable {
                Button {
                    model.undo()
                    model.saveIfNeeded()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!model.canUndo)
                .accessibilityLabel(model.undoName.map { "Undo \($0)" } ?? "Undo")

                Menu {
                    insertMenu
                    slideMenu
                    designMenu
                    fileMenu
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Actions")
            }

            if FeatureFlags.presenting, !model.slides.isEmpty {
                Button {
                    // A deck is presented as it was last saved *and* as it is now — the presenter
                    // reads the in-memory deck — so an unsaved edit shows. Flushing first anyway
                    // means a phone that dies mid-presentation has not lost it.
                    model.saveIfNeeded()
                    showPresenter = true
                } label: {
                    Image(systemName: "play.fill")
                }
                .accessibilityLabel("Present")
            }
        }
    }

    @ViewBuilder
    private var insertMenu: some View {
        Section("Insert") {
            Button {
                model.addTextBox()
                model.saveIfNeeded()
            } label: {
                Label("Text Box", systemImage: "textformat")
            }
            Button {
                showShapes = true
            } label: {
                Label("Shape\u{2026}", systemImage: "square.on.circle")
            }
            Button {
                model.addLine(endArrow: "triangle")
                model.saveIfNeeded()
            } label: {
                Label("Arrow", systemImage: "line.diagonal.arrow")
            }
        }
    }

    @ViewBuilder
    private var slideMenu: some View {
        if FeatureFlags.slideManagement {
            Section("Slide") {
                Button {
                    model.addSlide()
                    model.saveIfNeeded()
                } label: {
                    Label("New Slide", systemImage: "plus.rectangle")
                }
                Button {
                    model.duplicateSlide()
                    model.saveIfNeeded()
                } label: {
                    Label("Duplicate Slide", systemImage: "plus.square.on.square")
                }
                Button {
                    showLayouts = true
                } label: {
                    Label("Layout\u{2026}", systemImage: "rectangle.3.group")
                }
                Button(role: .destructive) {
                    model.deleteSlide()
                    model.saveIfNeeded()
                } label: {
                    Label("Delete Slide", systemImage: "trash")
                }
                .disabled(!model.canDeleteSlide)
            }
        }
    }

    @ViewBuilder
    private var designMenu: some View {
        if FeatureFlags.theming {
            Section("Design") {
                Button {
                    showThemes = true
                } label: {
                    Label("Theme\u{2026}", systemImage: "paintpalette")
                }
                Button {
                    showBackground = true
                } label: {
                    Label("Background\u{2026}", systemImage: "photo")
                }
                Button {
                    showTransitions = true
                } label: {
                    Label("Transition\u{2026}", systemImage: "sparkles")
                }
            }
        }
    }

    @ViewBuilder
    private var fileMenu: some View {
        Section {
            Button {
                showRename = true
            } label: {
                Label("Rename\u{2026}", systemImage: "pencil")
            }
            Button {
                model.redo()
                model.saveIfNeeded()
            } label: {
                Label(model.redoName.map { "Redo \($0)" } ?? "Redo",
                      systemImage: "arrow.uturn.forward")
            }
            .disabled(!model.canRedo)
        }
    }

    // MARK: - Conflict

    private func conflictAlert(_ conflict: DeckEditorModel.ConflictState) -> Alert {
        // Epic 6 — "409 conflict surfaced to the user, never silently overwritten". Both outcomes
        // lose something, so both are named plainly and neither is the default.
        Alert(
            title: Text("Changed Somewhere Else"),
            message: Text("This presentation was edited on another device since you opened it. "
                          + "Reloading discards your changes here; keeping yours overwrites theirs."),
            primaryButton: .destructive(Text("Keep Mine")) {
                model.keepLocalCopyAfterConflict()
            },
            secondaryButton: .default(Text("Reload")) {
                Task { await model.reloadAfterConflict() }
            }
        )
    }

    // MARK: - Commands

    /// Everything the format bar and the format sheet ask for, in one place so a bar button and a
    /// sheet control cannot drift apart.
    private func perform(_ command: ElementCommand) {
        switch command {
        case .style(let patch, let name):  model.applyTextStyle(patch, name: name)
        case .stepFontSize(let delta):     model.stepFontSize(by: delta)
        case .shapeFill(let color):        model.setShapeFill(color)
        case .shapeKind(let key):          model.setShapeKind(key)
        case .lineStroke(let color, let width):
            model.setLineStroke(color, width: width)
        case .bringForward:                model.reorderSelectedElement(by: 1)
        case .sendBackward:                model.reorderSelectedElement(by: -1)
        case .bringToFront:                model.sendSelectedElement(toFront: true)
        case .sendToBack:                  model.sendSelectedElement(toFront: false)
        case .duplicate:                   model.duplicateSelectedElement()
        case .delete:                      model.deleteSelectedElement()
        }
        model.saveIfNeeded()
    }

    // MARK: - Selection

    private func selectElement(at location: CGPoint, in canvasSize: CGSize) {
        let point = SlideGeometry.percentPoint(location, in: canvasSize)
        let hit = SlideGeometry.element(at: point, in: model.currentSlide?.elements ?? [])
        model.select(elementID: hit?.id)
    }

    // MARK: - Gestures

    /// Writes a finished drag or resize into the deck.
    private func commitDraft() {
        guard let draft else { return }
        model.setFrame(draft.frame, forElement: draft.elementID,
                       name: draft.handle == nil ? "Move" : "Resize")
        self.draft = nil
        model.saveIfNeeded()
    }

    /// Opens the text sheet for `id`, if it is a text box. Called by a double tap on the canvas and
    /// by the format bar's "Edit Text".
    private func beginTextEditing(_ id: String) {
        guard model.isEditable, let text = model.currentSlide?.element(id: id)?.text else { return }
        model.select(elementID: id)
        editingText = EditingText(id: id, content: text.content)
    }

    // MARK: - Lifecycle

    private func load() async {
        model.attach(contentService: contentService, driveService: driveService)
        themeService.authService = driveService.authService
        await model.load()
    }

    /// Epic 7 — "Autosave on an interval from Settings".
    ///
    /// A tick only ever *queues* a save; the chain in ``DeckEditorModel`` decides when it runs, so
    /// a slow upload cannot cause two to overlap however often this fires.
    private func autosaveLoop() async {
        while !Task.isCancelled {
            let interval = UInt64(settings.autoSaveInterval * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: interval)
            } catch {
                return  // Cancelled — the editor is going away.
            }
            model.saveIfNeeded()
        }
    }

    private func flush() {
        Task { await model.flush() }
    }
}

// MARK: - ElementCommand

/// Something to do to the selected element.
///
/// One vocabulary for the format bar, the format sheet and the element menu, so a command has one
/// implementation however it was reached.
enum ElementCommand {
    case style(TextStylePatch, name: String)
    case stepFontSize(Double)
    case shapeFill(String)
    case shapeKind(String)
    case lineStroke(String?, width: Double?)
    case bringForward
    case sendBackward
    case bringToFront
    case sendToBack
    case duplicate
    case delete
}

// MARK: - SelectionOverlay

/// The selection rectangle, its eight handles, and the gestures that move and resize an element.
///
/// Separate from ``SlideCanvasView`` because the canvas is shared with the thumbnails and presenter
/// mode, which must never grow a handle — and because the gesture arithmetic wants the canvas size
/// and the snap step, neither of which a renderer should know about.
struct SelectionOverlay: View {

    let slide: Slide
    let selectedID: String?
    let draft: DeckEditorView.Draft?
    let canvasSize: CGSize
    let snapStep: Double
    let showsGuides: Bool
    let onDraft: (DeckEditorView.Draft?) -> Void
    let onCommit: () -> Void
    let onActivate: (String) -> Void

    /// How big the touch target around a handle is. Bigger than the dot it draws, because a
    /// 10-point dot is below the 44-point minimum and a handle that cannot be grabbed is a handle
    /// that does not exist.
    private static let handleHitSize: CGFloat = 44
    private static let handleDotSize: CGFloat = 12

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showsGuides, let draft, let guides = guides(for: draft) {
                GuideLines(guides: guides, canvasSize: canvasSize)
            }

            if let element = selectedElement, let frame = currentFrame(for: element) {
                let rect = frame.rect(in: canvasSize)

                // A translucent copy of the element under the finger, because the canvas below
                // still shows it where it *was* — nothing is written to the deck until the gesture
                // ends. Without this a drag moves an empty rectangle around and the user has to
                // imagine the result.
                if draft?.elementID == element.id {
                    SlideElementView(element: element.withFrame(frame), canvasSize: canvasSize)
                        .opacity(0.7)
                        .allowsHitTesting(false)
                }

                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .contentShape(Rectangle())
                    .gesture(moveGesture(element: element, frame: frame))
                    .onTapGesture(count: 2) { onActivate(element.id) }
                    .accessibilityLabel("\(element.displayName), selected")

                ForEach(ResizeHandle.allCases) { handle in
                    handleView(handle, element: element, frame: frame, rect: rect)
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
    }

    // MARK: - Pieces

    private func handleView(_ handle: ResizeHandle, element: SlideElement, frame: SlideFrame,
                            rect: CGRect) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
            .frame(width: Self.handleDotSize, height: Self.handleDotSize)
            .frame(width: Self.handleHitSize, height: Self.handleHitSize)
            .contentShape(Rectangle())
            .offset(x: rect.minX + rect.width * handle.anchor.x - Self.handleHitSize / 2,
                    y: rect.minY + rect.height * handle.anchor.y - Self.handleHitSize / 2)
            .gesture(resizeGesture(handle: handle, element: element, frame: frame))
            .accessibilityLabel(handle.accessibilityLabel)
    }

    // MARK: - Gestures

    private func moveGesture(element: SlideElement, frame: SlideFrame) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                onDraft(DeckEditorView.Draft(
                    elementID: element.id,
                    frame: SlideGeometry.drag(frame, by: value.translation, in: canvasSize,
                                              snapStep: snapStep),
                    handle: nil
                ))
            }
            .onEnded { _ in onCommit() }
    }

    private func resizeGesture(handle: ResizeHandle, element: SlideElement,
                               frame: SlideFrame) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                onDraft(DeckEditorView.Draft(
                    elementID: element.id,
                    frame: SlideGeometry.resize(frame, handle: handle, by: value.translation,
                                                in: canvasSize, snapStep: snapStep),
                    handle: handle
                ))
            }
            .onEnded { _ in onCommit() }
    }

    // MARK: - Geometry

    private var selectedElement: SlideElement? {
        selectedID.flatMap { slide.element(id: $0) }
    }

    /// The frame to draw the selection at: the draft while a gesture is running, the stored one
    /// otherwise. The canvas underneath still shows the element where it was, which is why the
    /// overlay draws a copy of it at this frame while a gesture is running.
    private func currentFrame(for element: SlideElement) -> SlideFrame? {
        if let draft, draft.elementID == element.id { return draft.frame }
        return element.frame
    }

    private func guides(for draft: DeckEditorView.Draft) -> SlideGeometry.Guides? {
        let others = slide.elements
            .filter { $0.id != draft.elementID }
            .compactMap(\.frame)
        let guides = SlideGeometry.guides(for: draft.frame, others: others)
        return guides.isEmpty ? nil : guides
    }
}

// MARK: - GuideLines

/// The alignment guides drawn while an element is being dragged.
private struct GuideLines: View {

    let guides: SlideGeometry.Guides
    let canvasSize: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(guides.vertical, id: \.self) { x in
                Rectangle()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: 1, height: canvasSize.height)
                    .offset(x: CGFloat(x / 100) * canvasSize.width)
            }
            ForEach(guides.horizontal, id: \.self) { y in
                Rectangle()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: canvasSize.width, height: 1)
                    .offset(y: CGFloat(y / 100) * canvasSize.height)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - TextEntrySheet

/// Typing into a text box.
///
/// A sheet rather than an inline editor on the canvas, and deliberately: a text box on a phone-sized
/// slide is often a few millimetres tall, the keyboard covers the bottom half of the screen, and
/// editing in place would put the caret under the user's own thumb. The sheet gives the text the
/// whole screen and hands it back on Done.
struct TextEntrySheet: View {

    let text: String
    let onCommit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $draft)
                .focused($isFocused)
                .font(.body)
                .padding(8)
                .navigationTitle("Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            onCommit(draft)
                            dismiss()
                        }
                    }
                }
        }
        .onAppear {
            draft = text
            isFocused = true
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - SpeakerNotesView

/// The notes pane under the canvas.
struct SpeakerNotesView: View {

    let notes: String
    let isEditable: Bool
    let onChange: (String) -> Void

    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Speaker Notes")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

            if isEditable {
                TextEditor(text: $draft)
                    .font(.callout)
                    .frame(height: 72)
                    .padding(.horizontal, 8)
                    // Written back as the user types rather than on blur: a phone has no reliable
                    // blur — the app can be swiped away mid-sentence — and the model drops a write
                    // that changes nothing, so this costs nothing when nobody is typing.
                    .onChange(of: draft) { onChange($0) }
            } else {
                ScrollView {
                    Text(notes.isEmpty ? "No notes for this slide." : notes)
                        .font(.callout)
                        .foregroundStyle(notes.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                }
                .frame(height: 72)
            }
        }
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
        .onAppear { draft = notes }
        // The notes shown have to follow the selected slide, and the draft is what is shown.
        .onChange(of: notes) { newValue in
            if newValue != draft { draft = newValue }
        }
    }
}
