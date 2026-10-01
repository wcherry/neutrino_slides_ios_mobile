Neutrino Slides for iOS — Feature Roadmap

Neutrino Slides for iOS follows the same philosophy as the Neutrino Docs, Notes and Sheets iOS
apps: it is not a standalone presentation tool, it is the iOS client for presentations that already
live in Neutrino Drive. It invents no authentication, no storage, no encryption model and no sync
protocol — it reuses the platform the sibling apps already run on.

This roadmap assumes:

* Reuse the existing Neutrino Auth service and its login flow, through `neutrino_shared_ios`.
* Reuse Neutrino Drive as the storage layer (`?type=slide` already filters listings server-side).
* Reuse the existing E2EE key model, key vault and key-import process.
* Speak the *same file format* as the web app — a `.pptx` carrying the `SlidePresentation` shape in
  `web/apps/web/src/app/(apps)/slides/editor/slideEditorTypes.ts` as its `neutrino/model.json`
  part — readable in both directions, and losing nothing on a round trip through this app.
* Follow the phased approach the sibling roadmaps use, so the app is usable early.

⸻

What the web app actually does

Scoping this app means scoping against the TypeScript under
`neutrino/web/apps/web/src/app/(apps)/slides/`. The surface, measured:

* **Deck** — slides addressed by id, each with a background (colour, CSS gradient, or image), a
  transition from a list of twelve, speaker notes, and an ordered list of elements.
* **Elements** — text (font, size, weight, slant, underline, strikethrough, colour, highlight,
  alignment, line height, paragraph spacing, bullet/numbered lists, shadow), shapes (a catalog of
  35 across three groups, fill, stroke, dash), lines (endpoints, arrowheads, dash), images (Drive
  references, opacity, tint, brightness/contrast/saturation/warmth, object fit), videos, diagram
  references, and live spreadsheet embeds. Every element also carries an optional entrance
  animation.
* **Design** — ten slide layouts, a theme gallery backed by `/api/v1/slides/themes` with user-owned
  themes, a slide master (background plus title/body styles), eighteen preset gradients.
* **Presenting** — full-screen playback with the per-slide transitions, a speaker-notes view, and a
  presenter window.
* **Import / export** — `.pptx` in and out. Every deck *is* a `.pptx` (issue #127), so both are
  file copies. The bespoke `application/x-neutrino-slide` JSON that predated it is gone from the
  server, the web and this app; no file was ever stored in it.
* **AI** — authoring help, image search, design and autoformat, all on `/api/v1/slides/{id}/ai/*`
  with the user's own provider credentials.

"Most of the functionality of the web app" is taken here to mean: opening and reading any deck
without losing what it holds, editing text, shapes, lines and layout, restyling with themes and
layouts, managing slides, and presenting. Collaboration, AI, `.pptx` and the diagram/video/embed
element kinds are deliberately late — and, until they arrive, are *preserved rather than dropped*.

⸻

The API this app talks to

**There is no `/api/v1/slides` CRUD resource for decks.** Per-app editor resources collapsed into
generic Drive endpoints driven by a mime-type registry (`src/drive/storage/native_types.rs`).
Membership in that registry is the marker: a file is a presentation because its mime type is
the `.pptx` type, not because a side table says so — which is also what `?type=slide` matches.

| What | Endpoint |
| --- | --- |
| List | `GET /api/v1/drive/folders/{id}?type=slide`, and `/recent`, `/starred`, `/shared-with-me`, `/trash` |
| Create | `POST /api/v1/drive/files` — client-supplied id, no body; the first autosave writes the sealed `.pptx` |
| Metadata | `GET /api/v1/drive/files/{id}/info` — mime type, `yourRole`, `contentVersion` |
| Content | `GET /api/v1/drive/files/{id}` (409 `NO_CONTENT` before the first save) / `PUT /api/v1/drive/files/{id}/autosave` |
| Keys | `GET` / `PUT /api/v1/drive/files/{id}/key` |
| Organise | `PATCH /drive/files/{id}`, `/drive/bulk/{trash,move}`, `/drive/trash/*` |
| Themes | `GET /api/v1/slides/themes` — the one Slides-specific endpoint this app calls |

Three responsibilities the refactor moved to the client, each called out where it happens in
`SlideContentService`:

1. **"Is this a presentation?"** — `/info` answers for any file type, so nothing server-side stops
   this app opening a spreadsheet and rendering an empty deck. `SlideFileInfo.isNativeDeck` is the check.
2. **Naive timestamps** — Drive serialises `2026-08-10T12:00:00` with no offset, meaning UTC.
   `DriveDate` reads a zone-less timestamp as UTC rather than local.
3. **A body that is not a deck** — a truncated upload opens as an empty deck rather than throwing.
   Unlike a spreadsheet's, a presentation's *seeded* body is already a real one-slide deck
   (`EMPTY_SLIDES_CONTENT`), so there is no second format to convert.

⸻

The rule that shapes the whole app: preserve what you cannot draw

A phone will always understand less of the format than the browser does. A deck saved on the web can
carry videos, diagram references, live sheet embeds and per-element animations this app cannot
render — and a decoder that only knew the fields it renders would drop every one of them on the
first mobile save, with nothing failing anywhere.

So:

* Every modelled type keeps an `UnknownFields` bag and writes it back verbatim.
* An element of an unmodelled *kind* is kept whole as `SlideElement.opaque`, drawn as a labelled
  placeholder at its real position, and can be moved and deleted but not restyled.
* Unrecognised enum-ish values — an alignment, a transition, a background type — round-trip as
  written and are mapped onto something drawable only at render time.

`PresentationCodecTests` is where that rule is enforced.

⸻

Phase 1 — shipped

| Epic | What | Where |
| --- | --- | --- |
| 1 | App shell: tabs, navigation stacks, empty states, Offline placeholder | `ContentView.swift` |
| 2 | Account: sign-in, registration, device registration, key vault unlock, key file and QR import | `neutrino_shared_ios`, `VaultUnlockView` |
| 3 | Drive integration: browse Home / Recent / Favorites / Shared / Trash, folders, create, rename, move, star, duplicate, trash and restore | `SlidesDriveService`, `SlideBrowserView` |
| 5 | The canvas: 16:9 rendering of backgrounds, text, shapes, lines and images, the thumbnail rail, speaker notes | `SlideCanvasView`, `SlideThumbnailRail` |
| 6 | Load and save: E2EE round trip, `expectedContentVersion` guard, 409 surfaced to the user | `SlideContentService`, `DeckEditorModel` |
| 7 | Editing: drag, resize with eight handles, snapping and alignment guides, text entry, add text / shape / line, z-order, duplicate, delete, undo/redo, autosave | `DeckEditorModel`, `SelectionOverlay` |
| 8 | Slides: add, duplicate, delete, reorder by drag, and the ten layouts | `DeckEditorModel`, `LayoutGalleryView` |
| 9 | Text formatting: the format bar and the format sheet | `ElementFormatBar` |
| 10 | Design: theme gallery, per-slide background (colour, preset and custom gradients, image URL), transitions, slide master | `ThemeGalleryView`, `BackgroundPickerView` |
| 12 | Presenter mode: full-screen playback, transitions, speaker notes, auto-advance, idle-timer hold; on an external display (AirPlay, cable) the slide goes to that screen and the device shows a presenter console | `PresenterView`, `ExternalDisplayService` |
| 22 | `.pptx` as the stored format: open any deck — the web's model when the package carries a trusted one, the slides themselves when it does not — and save a package PowerPoint opens with the model packed beside it | `Deck/OOXML/` (`PptxCodec`, `PptxReader`, `PptxWriter`) |
| 24 | App lock: Face ID / Touch ID, grace period, app-switcher redaction | `neutrino_shared_ios` |

Every epic above has a flag in `Config/FeatureFlags.swift`, defaulting to `true`, so a feature can be
switched off in a build without unpicking its wiring.

⸻

Phase 2 — next

| Epic | What | Why it is not in Phase 1 |
| --- | --- | --- |
| 13 | Sharing: manage who a deck is shared with, and the share sheet | Phase 1 *honours* roles (a read-only share opens a viewer) but does not grant them |
| 14 | Search across decks, using the same flattening `Slide.plainText` already does | Needs a local index to be worth having |
| 15 | Drive image resolution: download, unseal and decrypt `neutrino-drive:<id>` images | A second decrypt path with its own cache; today those images draw a labelled placeholder |
| 16 | Offline: cached decks, an edit queue and background sync | The Offline tab ships as an empty state so the tab set does not move later |
| 17 | Version history (`POST /versions`), and restoring one | Autosave deliberately does not snapshot |
| 18 | Element entrance animations in presenter mode | Modelled and preserved already; playing them is the work |

⸻

Phase 3 — later

| Epic | What | Notes |
| --- | --- | --- |
| 19 | Live sheet embeds and diagram elements rendered for real | Both are preserved today; rendering one means pulling in another app's format |
| 20 | Universal Links (`/open/slide/<id>`) | Router and entitlement are in place and tested; `FeatureFlags.appLinks` is off until the deployed `apple-app-site-association` routes `/open/slide/*` here instead of to Drive, sequenced with the App Store release |
| 21 | Creating and editing themes rather than only applying them | `SlideThemeService` reads `/api/v1/slides/themes`; writing is a web feature today |
| 23 | AI: authoring help, image search, autoformat | Needs the user's provider credentials on the device |
| 25 | Collaboration: presence and live co-editing | The web app buffers content until a peer joins; matching that is a project of its own |

⸻

Notes on decisions a reader will otherwise ask about

**Why is the thumbnail rail horizontal when the web app's is vertical?** The space under a phone's
canvas is wide and short. The web puts its rail down the side of a window that is tall and narrow
beside its canvas; both are the same decision about where the room is.

**Why is text edited in a sheet rather than on the canvas?** A text box on a phone-sized slide is
often a few millimetres tall and the keyboard covers the bottom half of the screen, so editing in
place would put the caret under the user's own thumb.

**Why does a gradient get stored under `type: "color"`?** Because that is what `applyTheme` in
`SlideEditor.tsx` writes and what the web renderer paints — both end up in a CSS `background`.
Writing `type: "gradient"` instead would produce decks the two clients disagree about. The renderer
here therefore decides how to paint a background from its *value*, not its declared type.

**Why is the shape catalog copied rather than redrawn?** A `"hexagon"` written on a phone has to be
the same hexagon on the web, and the only way to be sure is to draw from the same path data. The
parser under it is a deliberate subset — `M L H V C Q Z` — and refuses anything else rather than
drawing an outline that is subtly not the shape the user picked.

**Why do six of the twelve transitions play as something else?** Flip, cube, gallery, pixelate,
cover and wipe are 3D or filter effects with no SwiftUI equivalent worth a Metal pass on a phone
mid-presentation. Each falls back to the closest thing that keeps its feel, and the *stored* value is
untouched, so the deck still plays properly on the web.
