# Media DL — Implementation Plan

Backbone setup and basic download functionality, broken into phases.
Each phase ends with a testable milestone.

**Guiding principle:** Use Flutter/Dart built-ins wherever possible. Minimize external dependencies.

---

## Phase 1 — Project Scaffold & App Shell

**Goal:** Flutter project created, builds and runs on macOS and Android with an empty shell.

- [ ] `flutter create` with org `com.crylo`, app name `media_dl`, platforms: android, macos, linux, windows
- [ ] Remove iOS target directory entirely
- [ ] Set up project structure:
  ```
  lib/
    main.dart
    app.dart
    core/           # shared utilities, constants, models
    features/
      download/     # download-related screens & logic
      settings/     # settings screen & logic
    services/       # process runner, binary manager, etc.
  ```
- [ ] Basic `MaterialApp` with Material 3, light/dark theme toggle
- [ ] Bottom navigation or tab layout with placeholder pages: **Home** (URL input + downloads), **Settings**
- [ ] Verify builds: `flutter run -d macos` and `flutter run -d android` (or emulator)

**External dependencies:** None

**Milestone:** App launches on macOS and Android showing a URL text field and empty download list.

---

## Phase 2 — Binary Management (yt-dlp only)

**Goal:** App can locate or bundle yt-dlp and report its version.

- [ ] `BinaryManager` service:
  - Resolve binary path per platform (app bundle location, or PATH fallback)
  - Run `yt-dlp --version` via `dart:io` `Process.run` and parse output
  - Expose version info to UI
- [ ] Platform-specific bundling strategy:
  - **macOS/Linux/Windows:** Ship yt-dlp binary in assets, copy to app-support dir on first run, set executable permission
  - **Android:** Bundle yt-dlp + Python (via platform-specific approach — document this as a known hard problem, use system `yt-dlp` as fallback for now; Phase 2 focuses on desktop)
- [ ] Settings page shows detected yt-dlp version (or "not found" with guidance)
- [ ] Wire up a simple "Check for update" button (compare local version string against GitHub Releases latest tag via `dart:io` `HttpClient` — no external HTTP package)

**External dependencies:** None (`dart:io` Process + HttpClient)

**Milestone:** Settings page displays yt-dlp version. "Check for update" reports if a newer version exists.

---

## Phase 3 — Process Runner & Output Parsing

**Goal:** Run yt-dlp as a subprocess, capture stdout/stderr in real time, parse progress lines.

- [ ] `ProcessRunner` service:
  - Start yt-dlp with given arguments using `Process.start` (not `Process.run` — we need streaming)
  - Stream stdout and stderr line-by-line
  - Support cancellation via `Process.kill`
  - Return exit code
- [ ] `YtDlpOutputParser`:
  - Parse yt-dlp's `[download]` progress lines: percentage, total size, speed, ETA
  - Parse `[info]` lines for metadata extraction
  - Parse error/warning lines
  - Output structured `DownloadProgress` objects
- [ ] Unit-test the parser against sample yt-dlp output strings (no network needed)
- [ ] Simple integration test: run `yt-dlp --version` through `ProcessRunner`, verify output captured

**External dependencies:** None (`dart:io`, `dart:async` Stream)

**Milestone:** Parser correctly extracts progress data from real yt-dlp output. ProcessRunner can start/stream/kill a process.

---

## Phase 4 — Basic Download (End-to-End)

**Goal:** Paste a URL, tap download, see real-time progress, get a file on disk.

- [ ] `DownloadTask` model:
  - URL, status (queued/downloading/paused/completed/failed/cancelled), progress, speed, ETA, output path, error message
- [ ] `DownloadManager` service:
  - Accept a URL → create a `DownloadTask`
  - Run yt-dlp via `ProcessRunner` with default format (best) and output to a configured directory
  - Update `DownloadTask` state from parsed output via `ChangeNotifier` or `ValueNotifier`
  - Handle completion, failure, and cancellation
- [ ] Home screen UI:
  - URL text field + "Download" button
  - Active download card showing: title (filename), progress bar, percentage, speed, ETA
  - Cancel button on active download
- [ ] Default output directory:
  - Desktop: `~/Downloads/MediaDL/`
  - Android: app-specific external storage (for now)
- [ ] State management: `ChangeNotifier` + `ListenableBuilder` (Flutter built-in, no provider/riverpod/bloc)

**External dependencies:** None

**Milestone:** User can paste a YouTube URL, tap download, watch progress update in real time, and find the file on disk.

---

## Phase 5 — Download Queue & Multiple Downloads

**Goal:** Support queued downloads and show download history.

- [ ] `DownloadManager` improvements:
  - Maintain a list of all `DownloadTask`s (active + completed + failed)
  - Configurable concurrent download limit (default: 1)
  - Queue: when a new download is added and limit is reached, it waits
  - Auto-start next queued download when a slot opens
- [ ] Home screen improvements:
  - Scrollable list of all downloads grouped by status (active → queued → completed → failed)
  - Each card shows relevant info per state
  - Cancel button for active/queued, retry button for failed
  - Clear completed downloads from list
- [ ] Basic persistence:
  - Save download history to JSON file in app-support directory using `dart:convert` + `dart:io`
  - Restore on app launch

**External dependencies:** None (`dart:convert` for JSON serialization)

**Milestone:** Can queue multiple downloads. They execute in order. History persists across app restarts.

---

## Phase 6 — URL Metadata & Format Selection

**Goal:** Before downloading, fetch video info and let the user pick a format.

- [ ] `YtDlpInfoExtractor` service:
  - Run `yt-dlp -j <url>` to get JSON metadata
  - Parse into a `MediaInfo` model: title, thumbnail URL, duration, uploader, available formats
  - `Format` model: format ID, extension, resolution, filesize, codec, audio/video flags
- [ ] Pre-download flow:
  - User pastes URL → app fetches info → shows a bottom sheet or dialog with:
    - Video title, uploader, duration, thumbnail (loaded via `Image.network`)
    - Format picker: grouped by quality (best video+audio, video-only, audio-only)
    - "Download" button to confirm
  - Quick-download shortcut: long-press or setting to skip info fetch and download with default format
- [ ] Pass selected format ID to yt-dlp via `-f <format_id>`

**External dependencies:** None

**Milestone:** User pastes a URL, sees video info with format options, selects a format, and download starts.

---

## Dependency Summary

| Package              | Purpose                      | Phase |
| -------------------- | ---------------------------- | ----- |
| `path_provider`      | App-support & documents dir  | 2     |
| `permission_handler` | Storage permission (Android) | 4     |

That's it. Everything else uses `dart:io`, `dart:async`, `dart:convert`, and Flutter's built-in widgets and state management.

If `path_provider` can be avoided by using platform-specific env vars / known paths, we will. Same for `permission_handler` — if scoped storage APIs suffice, we skip it.

---

## Out of Scope for This Plan

These are real features from PROJECT_SCOPE.md that come **after** the above foundation is proven:

- Pause/resume (requires yt-dlp `--download-sections` or temp file management)
- Playlist support (parse playlist JSON, manage child tasks)
- Post-processing options (thumbnail, subtitle, SponsorBlock)
- gallery-dl integration
- Binary auto-update (download + replace)
- Notifications
- Share intent handling
- Cookie / authentication management
- Output template customization
- Network settings (proxy, rate limit)

---

## Architecture Notes

```
┌──────────────────────────────────┐
│            UI Layer              │
│  (Screens, Widgets, Dialogs)    │
│  State: ChangeNotifier/         │
│         ValueNotifier            │
└──────────┬───────────────────────┘
           │ listens to
┌──────────▼───────────────────────┐
│        Service Layer             │
│  DownloadManager                 │
│  BinaryManager                   │
│  YtDlpInfoExtractor             │
└──────────┬───────────────────────┘
           │ uses
┌──────────▼───────────────────────┐
│         Core Layer               │
│  ProcessRunner (dart:io Process) │
│  YtDlpOutputParser              │
│  Models (DownloadTask, Format…) │
│  Storage (JSON file persistence)│
└──────────────────────────────────┘
```

No dependency injection framework. Services are created in `main.dart` and passed down via constructor or `InheritedWidget`.
