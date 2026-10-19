# Glimpse

A macOS app for catching the things you see and think about during the day, then letting Claude organize them.

Two gestures, both global hotkeys that work from any app:

| Hotkey | What happens |
|---|---|
| ⌥⇧S | The native crosshair screenshot picker appears. Drag a region. A floating card shows the shot and lets you add a note. |
| ⌥⇧N | A floating card appears. Type a note. |

While the card is open:

| Key | Action |
|---|---|
| ↩ | Save |
| ⇧↩ | New line |
| ⌘1 … ⌘6 | Set category: To-do, Follow Up, Important, Thought, Idea, Reference |
| ⌘0 | Clear category and let Claude pick |
| esc | Cancel |

After saving, Claude gets the screenshot and note and returns a title, a summary, a suggested category, tags, the text visible in the screenshot, and any action items. If you didn't pick a category, Claude's suggestion is applied. If you did, yours wins and Claude's suggestion is shown as a hint.

The main window has a timeline grouped by day and a sidebar of categories, each sorted by time added. Search covers notes, titles, summaries, tags, and extracted screenshot text.

## Build and run

Requires macOS 14 or later and the Swift toolchain (Command Line Tools are enough, Xcode is not required).

```sh
./build.sh --run
```

This compiles with SwiftPM, wraps the binary in `build/Glimpse.app`, ad-hoc signs it, and launches it. Use `--debug` for a debug build.

## Setup

1. Open Settings from the menu bar icon or ⌘, and paste your Anthropic API key. It is stored in your login Keychain. The `ANTHROPIC_API_KEY` environment variable works as a fallback.
2. Take a first screenshot with ⌥⇧S. macOS will ask for Screen Recording permission. Grant it to Glimpse under System Settings → Privacy & Security → Screen Recording, then try again.

## Claude integration

Anthropic has no official Swift SDK, so `ClaudeService.swift` calls the Messages API over HTTPS directly. Notable choices:

- Default model is `claude-fable-5-1`, switchable to Opus 5, Sonnet 5, or Haiku 4.5 in Settings.
- Responses use structured outputs (`output_config.format` with a JSON schema), so parsing never depends on prose.
- Effort is set to `low` to keep captures snappy.
- Screenshots are downscaled to 1568px on the long edge and sent as JPEG.
- On Fable, server-side refusal fallbacks are enabled so a safety-classifier decline reruns on another model instead of failing the capture.
- Captures that were pending when the app quit are retried on next launch.

## Data

Everything lives in `~/Library/Application Support/Glimpse/`: `captures.json` plus an `Images/` folder of PNGs. Delete the folder to start fresh.

## Layout

```
Sources/Glimpse/
  GlimpseApp.swift          App entry, menu bar extra, hotkey registration
  Models/Capture.swift      Capture, Category, AIEnrichment
  Store/CaptureStore.swift  JSON persistence, image files, day grouping
  Services/
    ClaudeService.swift     Messages API client and prompt
    Enricher.swift          Background enrichment queue
    HotkeyManager.swift     Carbon global hotkeys
    ScreenshotService.swift Wraps /usr/sbin/screencapture -i -s
    AppSettings.swift       Model, toggles, API key resolution
    Keychain.swift
  Capture/
    CaptureFlow.swift       Screenshot and note entry points
    CapturePanel.swift      Floating non-activating NSPanel and draft state
    CaptureView.swift       Card UI and the Return/Escape-aware text view
  Views/
    MainView.swift          Split view, timeline, category lists, rows
    CaptureDetailView.swift Detail pane with category override and Claude results
    SettingsView.swift
    Shared.swift            Chips, badges, thumbnails, date labels
```
