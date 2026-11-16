# Codex Notch

**[Download Codex Notch 1.0.0 for Mac (ZIP)](https://github.com/BornGamer23/codex-notch/releases/download/v1.0.0/Codex-Notch-1.0.0-macOS-arm64.zip)** · Apple silicon · macOS 13 or later

![Codex Notch animating through reading files, thinking, building, answering, and completion](https://raw.githubusercontent.com/BornGamer23/codex-notch/main/docs/codex-notch-demo.gif)

Unzip the download, move **Codex Notch.app** to Applications, and open it. No build tools required. This release is not Apple-notarized, so macOS may block the first launch.

A native, local-only macOS menu bar app inspired by the [hypnotizing UI reference](https://www.inspora.design/posts/hypnotizing-ui).

## Open

After you open the app, its glowing grid icon appears in the menu bar; the HUD sits at the top of the built-in notched display, or the primary display when no notch is present. Click the HUD or the grid menu → **Codex Notch…** to open its controls.

- **Play demo** cycles through reading, thinking, building, answering, and completion. Stop the demo to resume actual activity.
- **Pause activity** pauses the display of live activity.
- **Keep expanded**, **Hide when idle**, **Reduce motion**, and the **Glow** slider customize the HUD. Preferences persist on this Mac.
- **Sessions folder…** selects a different Codex `sessions` directory if needed.
- Use the menu bar → **Quit Codex Notch** to close the app and remove the overlay.

No API key, network connection, Accessibility permission, or screen recording is needed. This app displays what Codex is doing; continue asking questions and running tasks in Codex itself.

## Automatic startup

Automatic startup is optional and disabled by default. A small event-driven macOS LaunchAgent starts at login and opens Codex Notch in the background whenever Codex launches or becomes active. It also handles Codex already running at login. It does not bring the settings window forward, change Codex itself, or launch duplicate HUDs.

The installed app and helper live in `~/Library/Application Support/CodexNotch/`. The LaunchAgent is `~/Library/LaunchAgents/local.codexnotch.autostart.plist`. Keep those files in place; moving this source folder does not affect automatic startup. The helper observes application lifecycle notifications only.

To update or reinstall after building, run `bash install-autostart.sh`. To disable automatic startup, run `bash uninstall-autostart.sh`. This preserves the app and your preferences. Quitting the HUD closes it until Codex next launches or becomes active.

## Activity integration details

The app follows append-only JSONL activity records under `$CODEX_HOME/sessions`, defaulting to `~/.codex/sessions`. It reads the newest local activity across up to 16 recently modified tasks. It does **not** know which task is selected in the Codex window. Cloud-only tasks without local records are not supported.

Reading/building states are inferred from tool names and command metadata. Thinking and answering use recorded event types. The app shows only generic activity labels and file basenames, never message bodies, command output, or full paths. Data stays in memory and is not transmitted or copied to another log. It does not modify Codex settings, sessions, or authentication files.

Codex may buffer records, so the HUD can lag behind visible work. The local log format is not a stable integration API and future versions may need parser updates. After three minutes without a new event, it displays **Waiting** instead of continuing to claim activity. Completion returns to idle after eight seconds.

## Build and verify

Requires an Apple silicon Mac, macOS 13 or later, and Apple Command Line Tools. The app is compiled for Apple silicon and locally ad-hoc signed, not notarized for public distribution.

```sh
bash build.sh
```

This builds the `.app` and runs the event parser/tail reader checks. To run checks again:

```sh
"Codex Notch.app/Contents/MacOS/CodexNotch" --self-test
```

Launch arguments `--controls` and `--demo` open the controls or start a demo. All editable source is included in `Sources/`. The app is independent of and is not an official OpenAI product.
