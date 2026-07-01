import AppKit

public class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    
    public var onLeftClick: (() -> Void)? = nil
    public var onToggleDictation: (() -> Void)? = nil
    public var onStartupToggle: ((Bool) -> Void)? = nil
    public var onExit: (() -> Void)? = nil
    
    private var startupMenuItem: NSMenuItem? = nil
    private var progressMenuItem: NSMenuItem? = nil
    
    public init(config: AppConfig) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.menu = NSMenu()
        
        super.init()
        
        setupButton()
        setupMenu(config: config)
    }
    
    private func setupButton() {
        guard let button = statusItem.button else { return }
        
        // System status bar icon (microphone template image)
        let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Nemo Voice Typing")
        image?.isTemplate = true // Ensures matching light/dark macOS themes
        button.image = image
        
        button.target = self
        button.action = #selector(statusBarButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    
    private func setupMenu(config: AppConfig) {
        let progressItem = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")
        progressItem.isEnabled = false
        self.progressMenuItem = progressItem
        menu.addItem(progressItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let toggleItem = NSMenuItem(title: "Toggle Dictation", action: #selector(toggleDictationClicked), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        let showPanelItem = NSMenuItem(title: "Show/Hide Panel", action: #selector(showPanelClicked), keyEquivalent: "")
        showPanelItem.target = self
        menu.addItem(showPanelItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let startupItem = NSMenuItem(title: "Start with macOS", action: #selector(startupToggleClicked), keyEquivalent: "")
        startupItem.target = self
        startupItem.state = config.runAtStartup ? .on : .off
        self.startupMenuItem = startupItem
        menu.addItem(startupItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit Nemo Voice Typing", action: #selector(quitClicked), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    public func setStartupState(enabled: Bool) {
        startupMenuItem?.state = enabled ? .on : .off
    }
    
    public func setProgressStatus(_ text: String?, loading: Bool) {
        let title = text?.isEmpty == false ? text! : "Ready"
        progressMenuItem?.title = loading ? "Model: \(title)" : title
        statusItem.button?.toolTip = title
    }
    
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            // Remove menu after click so left-clicks continue to trigger the button action
            statusItem.menu = nil
        } else {
            onLeftClick?()
        }
    }
    
    @objc private func toggleDictationClicked() {
        onToggleDictation?()
    }
    
    @objc private func showPanelClicked() {
        onLeftClick?()
    }
    
    @objc private func startupToggleClicked() {
        guard let item = startupMenuItem else { return }
        let newState = item.state == .on ? false : true
        onStartupToggle?(newState)
    }
    
    @objc private func quitClicked() {
        onExit?()
    }
}
