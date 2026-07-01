import AppKit
import SwiftUI

public class FloatingPanelWindow: NSPanel {
    public init(contentRect: NSRect, config: AppConfig) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        
        self.isMovableByWindowBackground = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.keepAlwaysOnTop(config.alwaysOnTop)
    }
    
    public func keepAlwaysOnTop(_ alwaysOnTop: Bool) {
        self.level = alwaysOnTop ? .floating : .normal
    }
}
