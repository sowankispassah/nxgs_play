---
name: nxgs-streaming-guard
description: Protect NXGS Gaming's Chiaki-derived settings pages and streaming stack. Use before modifying NXGS files related to SettingsDialog.qml, StreamView.qml, stream/video/audio/wifi/remote settings, bitrate, resolution, codec, decoder, renderer, controller input, PSN registration, connection/session behavior, packet handling, frame queues, libplacebo rendering, or any rental/session feature that might touch remote play launch or streaming.
---

# NXGS Streaming Guard

## Required Rule

Treat the Chiaki remote-play stack as protected. Do not modify settings UI, stream quality, bitrate, resolution, codec, decoder, renderer, controller input, PSN registration, packet handling, or connection behavior unless the user explicitly asks for that exact streaming/settings change.

Rental, payment, store, controller-admin, and session features must be implemented as a layer above existing remote play. They may choose a registered host and call the existing session launch path, but they must not change the streaming pipeline.

## Protected Files

Pause and inspect before editing any of these:

```text
gui/src/qml/SettingsDialog.qml
gui/src/qml/StreamView.qml
gui/src/qmlmainwindow.cpp
gui/include/qmlmainwindow.h
gui/src/streamsession.cpp
gui/include/streamsession.h
gui/src/settings.cpp
gui/include/settings.h
gui/src/qmlsettings.cpp
gui/include/qmlsettings.h
lib/src/session.c
lib/src/videoreceiver.c
lib/src/streamconnection.c
lib/src/reorderqueue.c
lib/src/frameprocessor.c
lib/src/ffmpegdecoder.c
```

Also treat related headers/resources as protected when they affect these behaviors.

## Settings Baseline

The NXGS Settings page must keep the older Chiaki-style settings surface unless the user explicitly asks to change it.

Required visible shape:

- Tabs: `General`, `Video`, `Stream`, `Audio/Wifi`, `Consoles`, `Keys`, `Config`.
- No standalone settings tabs named `Controllers` or `Remote`.
- General includes `PS5 Features`.
- Video page stops at the original-style controls: hardware decoder, window type, render preset.
- Stream uses text bitrate fields with `Automatic (%1)`, not bitrate sliders.
- 1080p automatic bitrate display remains `30000` unless the user explicitly requests a different default.
- Audio/Wifi uses `Buffer Size` text field with `Default (5760)`, not the newer 50 ms slider.
- Do not surface zero-copy, frame mixer, renderer backend, Vulkan deferred swap, request-IDR, or stream-stats controls in the main Settings page unless explicitly requested.
- Keep NXGS branding and attribution text intact.

Useful baseline for comparison:

```powershell
git show 3ba0ff38^:gui/src/qml/SettingsDialog.qml
```

## Streaming Baseline

Before changing stream behavior, check whether the change touches:

- bitrate defaults or saved-setting migrations
- FPS/resolution/codec selection
- decoder selection or hardware decoder behavior
- libplacebo queue depth, pending frames, frame mixer, VSync, swapchain, zero-copy, or renderer backend
- audio buffer and audio queue behavior
- packet loss, FEC, IDR, reorder queues, congestion, MTU, Takion/RUDP, or stream connection logic
- controller input, haptics, DualSense, keyboard/mouse, or PSN registration

If the user did not explicitly request a streaming change, do not make the edit.

## Required Workflow

1. Run `git status --short` and identify existing user changes.
2. If a planned edit touches protected files, state why the file is needed.
3. Compare against the protected baseline before editing settings UI:

```powershell
git diff 3ba0ff38^ -- gui/src/qml/SettingsDialog.qml
```

Audit every restored control's value contract, not only its visible label:

- Compare each QML combo-box model with the current C++ enum values.
- Use explicit QML value maps when newer hidden enum members exist.
- Verify every `Chiaki.settings.*` binding still exists as a `Q_PROPERTY` or invokable.
- Confirm displayed defaults match runtime defaults, especially bitrate and audio buffer size.
- Check saved `QSettings` values for migrations when a previous mismatch may have persisted the wrong value.

4. For stream lag or quality bugs, inspect the latest NXGS session log first:

```powershell
Get-ChildItem "$env:APPDATA\NXGS Studio\NXGS Gaming\log" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
```

Search the log for `latency`, `drop`, `packet`, `loss`, `queue`, `swap`, `decoder`, `bitrate`, `fec`, and `idr`.

5. Keep feature code outside `StreamView.qml` unless the user explicitly asks for stream overlay UI. Rental timers, payment UI, grace periods, and admin screens must not run inside the stream view.
6. After edits, run targeted searches proving the protected UI did not drift:

```powershell
rg -n "Controllers|Zero-Copy|Frame Mixer|Renderer Backend|Vulkan Deferred|Request IDR|Show Stream Stats|Audio Buffer Size|Rumble Haptics" gui/src/qml/SettingsDialog.qml
rg -n "PS5 Features|Automatic \(%1\)|Buffer Size:" gui/src/qml/SettingsDialog.qml
rg -n "rental|Extend Session|Session Time|Chiaki\.rental|grace|heartbeat" gui/src/qml/StreamView.qml
```

The first and third searches should normally return no matches, except `Remote` as the Stream tab column label is acceptable.

7. Run the NXGS build-validation skill after source changes.

## Reporting

In the final response, explicitly report:

- whether protected settings UI changed
- whether any streaming files changed, and why
- whether `SettingsDialog.qml` still matches the protected settings surface
- whether `StreamView.qml` remains free of rental/session overlays
- build result and release EXE path
