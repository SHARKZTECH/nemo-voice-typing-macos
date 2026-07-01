import Foundation
import AppKit
import CoreGraphics

public struct TextInjector {
    private static let source = CGEventSource(stateID: .combinedSessionState)
    
    public static func type(_ text: String) {
        guard !text.isEmpty else { return }
        
        if Thread.isMainThread {
            paste(text)
        } else {
            DispatchQueue.main.sync {
                paste(text)
            }
        }
    }
    
    private static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let savedItems = savePasteboardItems(from: pasteboard)
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        pressKey(9, flags: .maskCommand)
        
        // Give the focused app a window to consume the pasteboard before
        // restoring it. Some Electron/WebKit fields read paste data asynchronously.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            restorePasteboardItems(savedItems, to: pasteboard, injectedText: text)
        }
    }
    
    public static func backspace(count: Int) {
        guard count > 0 else { return }
        
        // Backspace keycode on macOS is 51
        let backspaceKey: CGKeyCode = 51
        
        for _ in 0..<count {
            pressKey(backspaceKey)
        }
    }
    
    public static func pressEnter() {
        // Return keycode on macOS is 36
        let returnKey: CGKeyCode = 36
        
        pressKey(returnKey)
    }
    
    private static func pressKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags
        keyDown?.post(tap: .cgSessionEventTap)
        
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = flags
        keyUp?.post(tap: .cgSessionEventTap)
    }
    
    private static func savePasteboardItems(from pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        pasteboard.pasteboardItems?.map { item in
            var saved: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    saved[type] = data
                }
            }
            return saved
        } ?? []
    }
    
    private static func restorePasteboardItems(
        _ savedItems: [[NSPasteboard.PasteboardType: Data]],
        to pasteboard: NSPasteboard,
        injectedText: String
    ) {
        // Avoid overwriting a clipboard change the user made while we were typing.
        guard pasteboard.string(forType: .string) == injectedText else { return }
        
        pasteboard.clearContents()
        let restoredItems = savedItems.map { savedTypes in
            let item = NSPasteboardItem()
            for (type, data) in savedTypes {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}
