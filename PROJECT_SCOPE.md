# Media DL — Project Scope

**App Name:** Media DL
**Organization:** com.crylo
**License:** GPL-3.0
**Status:** Always Free, Open Source, No Monetization

A cross-platform Flutter UI for **yt-dlp** (primary) and **gallery-dl** (secondary).

---

## Target Platforms

| Platform | Supported                    |
| -------- | ---------------------------- |
| Android  | Yes                          |
| macOS    | Yes                          |
| Linux    | Yes                          |
| Windows  | Yes                          |
| iOS      | No — will never be supported |

---

## Core Features (yt-dlp)

### Download Management

- Single video/audio downloads with real-time progress (percentage, speed, ETA)
- Pause and resume downloads
- Download queue with concurrent download limits
- Cancel and retry failed downloads
- Persistent download history

### Media Format Options

- List and select available formats (video, audio, resolution, codec)
- Preset quality profiles (best, good, audio-only, etc.)
- Custom format selection via yt-dlp format strings
- Container format selection (mp4, mkv, webm, etc.)
- Audio extraction with codec choice (mp3, opus, flac, aac, etc.)

### Playlist Support

- Full playlist downloads
- Per-item progress within a playlist
- Overall playlist progress
- Selective item download (pick specific items from a playlist)
- Playlist metadata display (title, uploader, item count)

### Post-Processing

- Thumbnail embedding
- Metadata/tag embedding
- Subtitle download and embedding
- SponsorBlock integration (skip/mark/remove segments)
- Merging video + audio streams (via bundled ffmpeg)

### Configuration

- Output path and filename template configuration
- Network settings (proxy, rate limiting, source address)
- Cookie import (browser extraction or file)
- Custom yt-dlp arguments passthrough
- Per-site authentication (username/password, OAuth where supported)

---

## Secondary Features (gallery-dl)

- Image/gallery downloads from supported sites
- Download progress tracking
- Basic configuration (output path, filename templates)
- Cookie and authentication support

gallery-dl integration will follow yt-dlp and will be a lower priority.

---

## Binary Management

- Latest yt-dlp and gallery-dl binaries are **bundled with the app**
- ffmpeg bundled for post-processing (or use system-installed ffmpeg)
- In-app update check against GitHub Releases (yt-dlp, gallery-dl)
- One-tap binary update: fetch latest release directly from GitHub
- Version display for all bundled tools

---

## General App Features

- Clean, native-feeling Material 3 UI
- Light and dark theme support
- Download output directory picker
- Clipboard monitoring / auto-paste URL detection
- Share intent handling on Android (receive URLs from other apps)
- Notification support for download progress and completion
- Localization-ready structure (English first)

---

## Will NOT Implement — Ever

| Item                                               | Reason                                                 |
| -------------------------------------------------- | ------------------------------------------------------ |
| iOS support                                        | Platform restrictions make it impractical              |
| Monetization, ads, donations, paywalls             | This is a free and open-source project, always         |
| Analytics, telemetry, tracking, crash reporting    | No data collection of any kind                         |
| User accounts or cloud sync                        | No server-side components                              |
| Built-in media player                              | Out of scope — use the device's media player           |
| Streaming or casting                               | Out of scope — this is a download tool                 |
| Content recommendation or discovery                | Not a content platform                                 |
| DRM circumvention tooling                          | Only standard yt-dlp/gallery-dl capabilities           |
| Google Play Store publishing (if policy conflicts) | Will not compromise features to satisfy store policies |
| Custom yt-dlp/gallery-dl forks                     | Always use upstream official releases                  |
| Social features (comments, sharing, feeds)         | Not a social app                                       |

---

## Future / Maybe

These are features that may be considered after core functionality is stable:

- Scheduled/recurring downloads
- Watch-later queue that auto-downloads
- Browser extension companion (send URLs to app)
- CLI/headless mode for power users
- Custom themes beyond light/dark
- Archive mode (track already-downloaded URLs to avoid re-downloading)
- Batch import from text file or clipboard (list of URLs)
- Integration with local media servers (Jellyfin, Plex) for auto-organizing

---

## Distribution

- **GitHub Releases** — primary distribution channel (APK, macOS, Linux, Windows)
- **F-Droid** — if feasible
- **Flathub / Snap** — if feasible for Linux
- **Google Play Store** — only if policies allow the app as-is; will not modify the app to comply

---

## Non-Goals

- This project does not host, index, or link to any copyrighted content.
- This project is a UI wrapper; all download functionality comes from yt-dlp and gallery-dl.
- This project does not encourage or facilitate piracy.
