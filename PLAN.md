# Media DL — Implementation Plan

Backbone setup and basic download functionality, broken into phases.
Each phase ends with a testable milestone.

**Guiding principle:** Use Flutter/Dart built-ins wherever possible. Minimize external dependencies.

---

## Phase 1 — Project Scaffold & App Shell ✅

**Goal:** Flutter project created, builds and runs on macOS and Android with an empty shell.

- [x] `flutter create` with org `com.crylo`, app name `media_dl`, platforms: android, macos, linux, windows
- [x] Remove iOS target directory entirely
- [x] Set up project structure (`lib/`, `core/`, `features/`, `services/`)
- [x] Basic `MaterialApp` with Material 3, light/dark theme toggle
- [x] Bottom navigation with placeholder pages: **Downloads**, **Settings**
- [x] Verify builds: macOS and Android

**Milestone:** ✅ App launches showing a URL text field and empty download list.

---

## Phase 2 — Binary Management (yt-dlp only) ✅

**Goal:** App can locate yt-dlp and report its version.

- [x] `BinaryManager` service: resolve binary path, run `--version`, expose to UI
- [x] `BinaryResolver`: app-support dir → system PATH → well-known paths (`/opt/homebrew/bin`, `/usr/local/bin`)
- [x] Settings page shows detected yt-dlp version (or "not found")
- [x] "Check for update" button via GitHub Releases API (`dart:io` HttpClient)

**Milestone:** ✅ Settings page displays yt-dlp version. Update check works.

---

## Phase 3 — Process Runner & Output Parsing ✅

**Goal:** Run yt-dlp as a subprocess, capture stdout/stderr in real time, parse progress lines.

- [x] `ProcessRunner` service: `Process.start` with streaming stdout/stderr, kill support
- [x] `YtDlpOutputParser`: parse progress, destination, error, warning, merging, post-process lines
- [x] `DownloadProgress` model: percent, totalSize, speed, ETA
- [x] Unit tests for parser (16 tests) and process runner (6 tests)

**Milestone:** ✅ Parser extracts progress data. ProcessRunner can start/stream/kill.

---

## Phase 4 — Basic Download (End-to-End) ✅

**Goal:** Paste a URL, tap download, see real-time progress, get a file on disk.

- [x] `DownloadTask` model with status, progress, filename, output path, error
- [x] `DownloadManager` service: accept URL → run yt-dlp → update task state
- [x] Download page: URL input, progress card with bar/speed/ETA, cancel button
- [x] Default output to `~/Downloads/MediaDL/`
- [x] Disabled macOS app sandbox for subprocess + file access
- [x] Snackbar feedback when yt-dlp not found

**Milestone:** ✅ User pastes URL, watches real-time progress, file saved to disk.

---

## Phase 5 — Download Queue & Multiple Downloads ✅

**Goal:** Support queued downloads and show download history.

- [x] Download queue with configurable concurrency limit (default: 1)
- [x] Auto-start next queued download when slot opens
- [x] Retry button for failed/cancelled downloads
- [x] Clear completed button
- [x] JSON persistence: save/restore history across app restarts

**Milestone:** ✅ Queue multiple downloads. History persists across restarts.

---

## Phase 6 — URL Metadata & Format Selection ✅

**Goal:** Before downloading, fetch video info and let the user pick a format.

- [x] `YtDlpInfoExtractor`: run `yt-dlp -j` to get metadata, parse `MediaInfo` + `MediaFormat`
- [x] Format selection bottom sheet: thumbnail, title, duration, grouped formats (Video+Audio, Audio Only, Video Only)
- [x] Quick download button (bolt icon) to skip info fetch
- [x] In-memory cache for probe results (survives sheet dismissal)
- [x] `--embed-thumbnail` and `--embed-metadata` by default on all downloads

**Milestone:** ✅ User sees video info with formats, selects one, download starts.

---

## Phase 7 — Playlist Support ✅

**Goal:** Full playlist downloads with per-item progress and selective downloading.

- [x] `PlaylistInfo`, `PlaylistEntry` models
- [x] `PlaylistDownloadTask` with child `DownloadTask` per item
- [x] Sealed `DownloadEntry` base class (`DownloadTask` | `PlaylistDownloadTask`)
- [x] Auto-detect playlist vs single video via `--flat-playlist` probe
- [x] Playlist selection sheet: checkboxes, select all, item count
- [x] Expandable playlist card: overall progress + per-item breakdown
- [x] Selective download via `--playlist-items`
- [x] Parser for `[download] Downloading item X of Y` lines

**Milestone:** ✅ Paste a playlist URL, select items, download with per-item progress.

---

## Phase 8 — Output & Settings Customization ✅

**Goal:** Let users configure download directory and filename templates.

- [x] `SettingsNotifier` persisted to `settings.json` (theme, output dir, templates)
- [x] Configurable download directory with edit dialog
- [x] Filename template with presets (Title only, Title + ID, Uploader - Title, etc.)
- [x] Playlist template with presets
- [x] yt-dlp variable reference in template editor
- [x] DownloadManager reads settings at download time (immediate effect)

**Milestone:** ✅ Users can customize where and how files are named.

---

## Upcoming — Not Yet Implemented

Prioritized by impact. Items from PROJECT_SCOPE.md.

### High Priority

- [x] **Cookie file import** — `--cookies` support for age-restricted/private content, configurable in Settings
- [x] **Post-processing options UI** — SponsorBlock, subtitles, audio extraction, thumbnail/metadata toggles
- [ ] **Pause/resume** — re-run yt-dlp to resume partial downloads, track temp file state

### Medium Priority

- [x] **Notifications** — desktop notifications on download complete/failed (macOS, Linux, Windows)
- [ ] **Share intent handling (Android)** — receive URLs from other apps
- [x] **Network settings** — proxy, rate limiting, source address
- [ ] **Binary auto-update** — download + replace from GitHub Releases (check already exists)

### Lower Priority

- [ ] **gallery-dl integration** — secondary tool support per PROJECT_SCOPE.md
- [ ] **Clipboard monitoring / auto-paste** — detect URLs on clipboard
- [ ] **Localization-ready structure** — English first, l10n scaffolding

---

## Dependency Summary

| Package | Purpose                                                                    | Status                |
| ------- | -------------------------------------------------------------------------- | --------------------- |
| None    | Everything uses `dart:io`, `dart:async`, `dart:convert`, Flutter built-ins | ✅ Zero external deps |

`path_provider` and `permission_handler` were avoided by using platform-specific env vars and known paths.

---

## Architecture

```
┌──────────────────────────────────┐
│            UI Layer              │
│  (Screens, Widgets, Dialogs)    │
│  State: ChangeNotifier/         │
│         ListenableBuilder        │
└──────────┬───────────────────────┘
           │ listens to
┌──────────▼───────────────────────┐
│        Service Layer             │
│  DownloadManager                 │
│  BinaryManager                   │
│  YtDlpInfoExtractor             │
│  SettingsNotifier                │
└──────────┬───────────────────────┘
           │ uses
┌──────────▼───────────────────────┐
│         Core Layer               │
│  ProcessRunner (dart:io Process) │
│  YtDlpOutputParser              │
│  Models (DownloadEntry, sealed)  │
│  Storage (JSON file persistence) │
└──────────────────────────────────┘
```

No dependency injection framework. Services created in `main.dart` and passed down via constructors.
