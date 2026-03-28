# Plan: Bundle Python + yt-dlp on Android via youtubedl-android

## Context

yt-dlp can't run on Android natively — it's a Python app with no standalone Android binary. The youtubedl-android library (used by Seal app, millions of downloads) bundles Python 3.8 + yt-dlp + ffmpeg as native libraries, extracted at runtime. This also enables future gallery-dl support since it shares the same Python environment.

## Approach

Wrap youtubedl-android via MethodChannel + EventChannel. Create an `AndroidProcessRunner` that implements the same interface as `ProcessRunner`, so `DownloadManager` works unchanged on both desktop and Android.

## Files to Create (2)

1. **`lib/services/android_process_runner.dart`** — `AndroidProcessRunner` + `AndroidRunningProcess`
   - Uses MethodChannel to start yt-dlp execution on Kotlin side
   - Uses EventChannel (one per process) to stream output lines back to Dart
   - `kill()` calls `destroyProcessById` on Kotlin side
   - `exitCode` completes when Kotlin sends exit event

## Files to Modify (7)

2. **`lib/services/process_runner.dart`** — Make `RunningProcess` abstract
   - Extract current implementation into `NativeRunningProcess`
   - `RunningProcess` becomes abstract with `stdout`, `stderr`, `pid`, `kill()`, `exitCode`
   - `ProcessRunner.start()` returns `NativeRunningProcess`

3. **`android/app/build.gradle.kts`** — Add dependencies
   - `io.github.junkfood02.youtubedl-android:library:0.18.1`
   - `io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1`
   - `kotlinx-coroutines-android:1.9.0`
   - Set `minSdk = 24` (required by library)

4. **`android/app/src/main/AndroidManifest.xml`**
   - Add `android:extractNativeLibs="true"` to `<application>` (required by library)
   - Add `<uses-permission android:name="android.permission.INTERNET"/>`

5. **`android/app/src/main/kotlin/.../MainActivity.kt`** — Add ytdlp MethodChannel
   - `init` — calls `YoutubeDL.getInstance().init()` + `FFmpeg.getInstance().init()`
   - `execute` — starts yt-dlp on IO coroutine, streams output via EventChannel
   - `executeSync` — runs yt-dlp and returns full stdout/stderr (for info extraction)
   - `destroy` — cancels running process by ID
   - `version` — returns yt-dlp version string
   - `updateYtDlp` — updates via library's built-in updater

6. **`lib/services/binary_manager.dart`** — Android-specific detect/update
   - `detect()` on Android: calls `init` + `version` via MethodChannel
   - `updateYtDlp()` on Android: calls library's built-in updater instead of downloading binary

7. **`lib/services/ytdlp_info_extractor.dart`** — Android-specific command execution
   - Add `_run()` helper: uses MethodChannel `executeSync` on Android, `Process.run` on desktop
   - Replace 3 direct `Process.run` calls with `_run()`

8. **`lib/main.dart`** — Inject correct ProcessRunner
   - `Platform.isAndroid ? AndroidProcessRunner() : ProcessRunner()`
   - Pass explicitly to `DownloadManager`

## Key Design Decisions

- **EventChannel per process**: Each execution gets a unique processId and EventChannel. Events are tagged `{type: "stdout"|"exit", data: ...}`. Clean lifecycle — `endOfStream()` on completion.
- **Threading**: Kotlin uses `Dispatchers.IO` for blocking `execute()`. EventSink calls posted to main thread via `Handler`.
- **stderr**: youtubedl-android doesn't expose separate stderr. All output comes via the callback's raw line parameter. The existing parser handles both streams identically, so this is fine.
- **No DownloadManager changes**: The ProcessRunner abstraction means DownloadManager code is completely unchanged.
- **youtubedl-android API**: Maven Central `io.github.junkfood02.youtubedl-android`, requires `minSdk = 24`, `extractNativeLibs = true`. Execute is blocking (use coroutines), callback signature: `(Float progress, Long eta, String rawLine)`. Cancel via `destroyProcessById(processId)`. Update via `updateYoutubeDL(context, UpdateChannel.STABLE)`.

## Verification

1. `flutter analyze` — zero errors
2. `flutter test` — all 27 existing tests pass (ProcessRunner refactor is backward-compatible)
3. `flutter build apk` — builds successfully with new dependencies
4. On Android device/emulator: Settings shows yt-dlp version, downloads work with real-time progress
