import AppKit

public final class TargetApplicationTracker {
    public static let shared = TargetApplicationTracker()
    
    private var lastTargetApplication: NSRunningApplication?
    private let lock = NSLock()
    
    private init() {
        remember(application: NSWorkspace.shared.frontmostApplication)
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }
    
    public func restoreLastTargetApplication() {
        lock.lock()
        let app = lastTargetApplication
        lock.unlock()
        
        guard let app, !app.isTerminated else { return }
        app.activate(options: [])
    }
    
    @objc private func activeApplicationChanged(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        remember(application: app)
    }
    
    private func remember(application: NSRunningApplication?) {
        guard let application else { return }
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        guard application.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        
        lock.lock()
        lastTargetApplication = application
        lock.unlock()
    }
}
