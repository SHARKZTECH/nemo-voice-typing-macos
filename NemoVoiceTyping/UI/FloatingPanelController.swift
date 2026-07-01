import AppKit
import SwiftUI

public class FloatingPanelController: NSObject, NSWindowDelegate {
    public let window: FloatingPanelWindow
    public var view: FloatingPanelView
    private var config: AppConfig
    
    public var onMicTapped: (() -> Void)? = nil {
        didSet { updateHostingView() }
    }
    
    public var onHideTapped: (() -> Void)? = nil {
        didSet { updateHostingView() }
    }
    
    public var onExitTapped: (() -> Void)? = nil {
        didSet { updateHostingView() }
    }
    
    public init(config: AppConfig) {
        self.config = config
        self.view = FloatingPanelView()
        
        let initialRect = NSRect(x: 0, y: 0, width: 160, height: 44)
        self.window = FloatingPanelWindow(contentRect: initialRect, config: config)
        
        super.init()
        self.window.delegate = self
        
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = initialRect
        hostingView.autoresizingMask = [.width, .height]
        
        self.window.contentView = hostingView
        self.window.setContentSize(NSSize(width: 160, height: 44))
        
        setupPosition()
    }
    
    private func setupPosition() {
        if let left = config.panelLeft, let top = config.panelTop {
            window.setFrameOrigin(NSPoint(x: left, y: top))
        } else {
            // Default: middle of the right edge of the main screen
            if let screen = NSScreen.main {
                let visibleFrame = screen.visibleFrame
                let x = visibleFrame.maxX - 180
                let y = visibleFrame.midY - 22
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }
    }
    
    public func persistPosition() {
        let frame = window.frame
        config.panelLeft = Double(frame.origin.x)
        config.panelTop = Double(frame.origin.y)
        config.save()
    }
    
    public func windowDidMove(_ notification: Notification) {
        persistPosition()
    }
    
    public func show() {
        window.makeKeyAndOrderFront(nil)
    }
    
    public func hide() {
        window.orderOut(nil)
    }
    
    public var isVisible: Bool {
        window.isVisible
    }
    
    public func setListening(_ listening: Bool) {
        view.isListening = listening
        updateHostingView()
    }
    
    public func setLoading(_ loading: Bool) {
        view.isLoading = loading
        if !loading {
            view.loadingText = ""
        }
        updateHostingView()
    }
    
    public func setLoadingText(_ text: String) {
        view.loadingText = text
        updateHostingView()
    }
    
    public func pushAudioLevel(_ level: Double) {
        // level comes in as 0..1, map to array values
        let scaled = CGFloat(level)
        var levels = view.audioLevels
        
        // Simple smoothing/wobbling logic for visual effect
        for i in 0..<levels.count {
            let offset = CGFloat(i - 2) * 0.15
            let shaped = max(0.05, scaled - abs(offset))
            levels[i] = shaped
        }
        view.audioLevels = levels
        updateHostingView()
    }
    
    private func updateHostingView() {
        if let hostingView = window.contentView as? NSHostingView<FloatingPanelView> {
            var updatedView = view
            updatedView.onMicTapped = onMicTapped
            updatedView.onHideTapped = onHideTapped
            updatedView.onExitTapped = onExitTapped
            hostingView.rootView = updatedView
            
            // Dynamically adjust width if loading
            let width: CGFloat = view.isLoading ? 460 : 160
            let frame = window.frame
            window.setFrame(NSRect(x: frame.origin.x, y: frame.origin.y, width: width, height: 44), display: true, animate: false)
        }
    }
}
