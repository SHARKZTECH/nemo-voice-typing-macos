import AppKit

public class AppDelegate: NSObject, NSApplicationDelegate {
    private var config: AppConfig!
    private var menuBar: MenuBarController!
    private var panelController: FloatingPanelController!
    private var hotkeyManager: HotkeyManager!
    private var dictationController: DictationController!
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Single Instance check
        guard isSingleInstance() else {
            NSApp.activate(ignoringOtherApps: true)
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
        
        // 4. Setup Dictation Controller
        dictationController = DictationController(config: config, panelController: panelController)
        
        panelController.onMicTapped = { [weak self] in
            self?.dictationController.toggle()
        }
        panelController.onHideTapped = { [weak self] in
            self?.panelController.hide()
        }
        panelController.onExitTapped = {
            NSApp.terminate(nil)
        }
        
        // 5. Setup Menu Bar Item
        menuBar = MenuBarController(config: config)
        menuBar.onLeftClick = { [weak self] in
            self?.togglePanelVisibility()
        }
        menuBar.onToggleDictation = { [weak self] in
            self?.dictationController.toggle()
        }
        menuBar.onStartupToggle = { [weak self] enabled in
            self?.toggleStartup(enabled)
        }
        menuBar.onExit = {
            NSApp.terminate(nil)
        }
        
        // 6. Setup Hotkey Manager
        hotkeyManager = HotkeyManager()
        hotkeyManager.onTrigger = { [weak self] in
            self?.dictationController.toggle()
        }
        
        if !hotkeyManager.register(hotkeyString: config.hotkey) {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Could not register hotkey '\(config.hotkey)'. It may already be in use by another application."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
        
        // On launch, the floating panel is created hidden. We show it on toggle.
        
        // 7. Verify and sync login item startup state
        menuBar.setStartupState(enabled: StartupManager.isEnabled())
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
    
    private func toggleStartup(_ enabled: Bool) {
        config.runAtStartup = enabled
        config.save()
        menuBar.setStartupState(enabled: enabled)
        StartupManager.setEnabled(enabled)
    }
}
