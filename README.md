# Nemo Voice Typing for macOS

Native macOS voice typing app inspired by the Windows project [Garnet-Owl/nemo-voice-typing](https://github.com/Garnet-Owl/nemo-voice-typing).

This port is built in Swift and runs the Nemo ASR ONNX models locally through ONNX Runtime. Audio stays on your Mac. No Python runtime is required to use the packaged app.

## Features

- Menu bar app with a floating recorder pill.
- Global toggle hotkey: `Command + Option + A`.
- Local ONNX speech recognition.
- Automatic model download on first launch.
- Direct text insertion into the focused app.
- Spoken punctuation and editing commands such as `comma`, `period`, `new line`, `new paragraph`, `scratch that`, and `delete last`.

## Download

Download the latest `NemoVoiceTyping-1.0.dmg` from the [GitHub Releases page](https://github.com/SHARKZTECH/nemo-voice-typing-macos/releases).

## Install

1. Open `NemoVoiceTyping-1.0.dmg`.
2. Drag `Nemo Voice Typing.app` into `/Applications`.
3. Launch `Nemo Voice Typing` from `/Applications`.
4. Grant Microphone permission when macOS asks.
5. Grant Accessibility permission in `System Settings -> Privacy & Security -> Accessibility`.
6. Quit and reopen the app after enabling Accessibility.

The first launch downloads the speech model files to:

```text
~/Library/Application Support/NemoVoiceTyping/models/v3/
```

## Usage

- Press `Command + Option + A` to start or stop dictation.
- Click the floating microphone button to toggle recording.
- Right-click the menu bar icon for the app menu.
- The floating recorder shows recognition status such as `Listening...`, `Heard: ...`, and `Typed: ...`.

## macOS Security Notes

Release builds may still show a Gatekeeper warning unless the DMG is signed and notarized with an Apple Developer ID. If macOS blocks the app, open `System Settings -> Privacy & Security` and choose to allow it, or right-click the app and choose `Open`.

Accessibility permission is tied to the app bundle identity and signing identity. If you run different builds from the DMG volume, from the repo, and from `/Applications`, macOS may treat them as different apps. Install one copy in `/Applications`, enable that copy, then run that same copy.

## Build Locally

Requirements:

- macOS 14 or newer
- Xcode command line tools
- Swift 5.9 or newer

Build a debug executable:

```bash
swift build
```

Create a signed DMG:

```bash
./tools/create_dmg.sh
```

For stable local Accessibility permissions, use a persistent signing identity:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./tools/create_dmg.sh
```

If no signing identity is available, the script falls back to ad-hoc signing.

## GitHub Releases

This repository includes a GitHub Actions workflow that publishes a DMG when a version tag is pushed.

Create a release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The workflow builds the app on `macos-14`, creates `NemoVoiceTyping-1.0.dmg`, and uploads it to the GitHub Release for that tag.

## Credits

- Inspired by [Garnet-Owl/nemo-voice-typing](https://github.com/Garnet-Owl/nemo-voice-typing).
- Speech model files are downloaded from [Garnet-Owl/nemo-voice-typing-asr](https://huggingface.co/Garnet-Owl/nemo-voice-typing-asr).
- ONNX inference uses Microsoft's ONNX Runtime Swift package.
