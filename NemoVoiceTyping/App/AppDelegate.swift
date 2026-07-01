import AppKit

public class AppDelegate: NSObject, NSApplicationDelegate {
    private var config: AppConfig!
    private var menuBar: MenuBarController!
    private var panelController: FloatingPanelController!
    private var hotkeyManager: HotkeyManager!
    
    private let audio = AudioCapture()
    private var isRecording: Bool = false
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Single Instance check
        guard isSingleInstance() else {
            let alert = NSAlert()
            alert.messageText = "Nemo Voice Typing is already running."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        
        // 2. Load Config
        config = AppConfig.load()
        
        // 3. Setup Floating Panel Controller
        panelController = FloatingPanelController(config: config)
        panelController.onMicTapped = { [weak self] in
            self?.toggleRecording()
        }
        panelController.onHideTapped = { [weak self] in
            self?.panelController.hide()
        }
        panelController.onExitTapped = {
            NSApp.terminate(nil)
        }
        
        // 4. Setup Menu Bar Item
        menuBar = MenuBarController(config: config)
        menuBar.onLeftClick = { [weak self] in
            self?.togglePanelVisibility()
        }
        menuBar.onToggleDictation = { [weak self] in
            self?.toggleRecording()
        }
        menuBar.onStartupToggle = { [weak self] enabled in
            self?.toggleStartup(enabled)
        }
        menuBar.onExit = {
            NSApp.terminate(nil)
        }
        
        // 5. Setup Hotkey Manager
        hotkeyManager = HotkeyManager()
        hotkeyManager.onTrigger = { [weak self] in
            self?.toggleRecording()
        }
        
        if !hotkeyManager.register(hotkeyString: config.hotkey) {
            let alert = NSAlert()
            alert.messageText = "Could not register hotkey '\(config.hotkey)'. It may already be in use by another application."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        
        // 6. Bind Audio Capture Levels
        audio.onLevel = { [weak self] level in
            DispatchQueue.main.async {
                self?.panelController.pushAudioLevel(level)
            }
        }
        
        // On launch, the floating panel is created hidden. We show it on toggle.
    }
    
    private func isSingleInstance() -> Bool {
        guard let bundleId = Bundle.main.bundleIdentifier else { return true }
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        return runningApps.count <= 1
    }
    
    private func togglePanelVisibility() {
        if panelController.isVisible {
            panelController.hide()
        } else {
            panelController.show()
        }
    }
    
    private func toggleRecording() {
        if isRecording {
            audio.stop()
            isRecording = false
            panelController.setListening(false)
        } else {
            do {
                try audio.start()
                isRecording = true
                
                // Show panel if it's currently hidden
                if !panelController.isVisible {
                    panelController.show()
                }
                panelController.setListening(true)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Could not start audio recording: \(error.localizedDescription)"
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    private func toggleStartup(_ enabled: Bool) {
        config.runAtStartup = enabled
        config.save()
        menuBar.setStartupState(enabled: enabled)
        
        // We will wire actual LaunchAgent setup in StartupManager in Phase 5
        print("Startup toggled: \(enabled)")
    }
}
