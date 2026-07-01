# Walkthrough: Nemo Voice Typing macOS Port (ONNX-first)

We have completed the native macOS port of [nemo-voice-typing](https://github.com/Garnet-Owl/nemo-voice-typing) in Swift. The app runs on ONNX Runtime directly using native Swift SPM bindings, meaning it requires **zero Python runtime dependencies** to convert or package models.

---

## 🛠️ Key Accomplishments

### 1. App Shell & System Integrations (Phase 1)
- Created **`NemoVoiceTypingApp.swift`** and **`AppDelegate.swift`** setting up a status-bar-only daemon (no Dock icon, `LSUIElement = true`).
- Created **`MenuBarController`** providing system menu bar integration (template mic icon, left-click toggle, right-click context menu).
- Implemented **`FloatingPanelWindow`** (`NSPanel` subclass) with `.nonactivatingPanel` and `.hudWindow` styles so it floats globally without stealing keyboard focus from active text fields.
- Developed a gorgeous **`FloatingPanelView`** (SwiftUI) with frosted glassmorphism, pulsing state, and animated sound level bars.
- Integrated **`HotkeyManager`** using the global HotKey SPM library, defaulting to `⌘⌥A` (Command + Option + A).

### 2. Low-Latency Audio Pipeline (Phase 2)
- Implemented **`AudioCapture`** wrapping `AVAudioEngine` to tap microphone buffers at native sample rate, and `AVAudioConverter` to downsample to 16kHz mono Float32 in real time.
- Integrated Accelerate framework's **`vDSP_measqv`** for instant, vectorized RMS level calculations.
- Developed **`MelExtractor`** using Accelerate's **`vDSP.FFT`** (zero heap allocations in hot path) and vectorized matrix products for log-mel spectrogram extraction.

### 3. ASR ONNX Runtime Inference Engine (Phase 3)
- Integrated the official **`onnxruntime`** Swift Package Manager package dependency, linking directly to high-performance precompiled binaries.
- Developed **`OnnxASREngine`** to run streaming RNN-T inference directly on the original Hugging Face ONNX models (`encoder.onnx`, `decoder.onnx`, `joint.onnx`), maintaining hidden LSTM states natively.
- Developed **`Tokenizer`** to decode SentencePiece vocab indices.

### 4. Text Output & Processors (Phase 4)
- Implemented **`TextInjector`** using **`CGEvent`** key inputs. By setting UTF-16 code units directly on `keyboardSetUnicodeString`, we type emoji, accents, and symbols directly without layout conversion or copy-pasting.
- Implemented **`DictationProcessor`** handling capitalisation, period-after-pause, layout spacing ("new line", "new paragraph"), and command undos ("scratch that").
- Created **`PermissionManager`** wrapping System Accessibility (`AXIsProcessTrusted`) and Microphone authorizations with system deep-link preferences.

### 5. Downloads & Distribution (Phase 5)
- Implemented **`ModelManager`** downloading raw ONNX models asynchronously from Hugging Face with progress callbacks.
- Setup **`StartupManager`** using modern `SMAppService` to register the app to run at login.
- Wrote **`create_dmg.sh`** script that builds, copies assets, signs, and packages the binary into a compressed `.dmg` disk image.

---

## 🚀 How to Run & Verify

### 1. Build and Package the Application
Run the automated packaging script from the repository root:
```bash
./tools/create_dmg.sh
```
This will compile the package in release mode, bundle it as a standard `.app`, codesign it, and output a ready-to-run disk image named:
`NemoVoiceTyping-1.0.dmg`

### 2. Install
1. Double-click the generated `NemoVoiceTyping-1.0.dmg`.
2. Drag `Nemo Voice Typing.app` to your Applications folder.
3. Open `Applications` and double-click the app to launch it.
4. An icon with a microphone will appear in your top-right Menu Bar.

### 3. Test Dictation
1. Press `⌘⌥A` (Command + Option + A) or click the menu bar icon.
2. The first time you run it, the app will request Microphone permission. Click **OK**.
3. It will also request Accessibility permissions (required to type text into other applications). Click **Open System Settings**, check the box next to `Nemo Voice Typing`, and restart the app.
4. Model files will download to your `~/Library/Application Support/NemoVoiceTyping/models/v3/` folder.
5. Once loaded, click `⌘⌥A` and speak! The visualizer will bounce with your voice, and text will type where your cursor is.
