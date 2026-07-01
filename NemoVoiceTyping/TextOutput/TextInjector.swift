import Foundation
import CoreGraphics

public struct TextInjector {
    private static let source = CGEventSource(stateID: .combinedSessionState)
    
    public static func type(_ text: String) {
        guard !text.isEmpty else { return }
        
        let utf16Array = Array(text.utf16)
        
        // Post key down event
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        keyDown?.keyboardSetUnicodeString(stringLength: utf16Array.count, unicodeString: utf16Array)
        keyDown?.post(tap: .cghidEventTap)
        
        // Post key up event
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        keyUp?.keyboardSetUnicodeString(stringLength: utf16Array.count, unicodeString: utf16Array)
        keyUp?.post(tap: .cghidEventTap)
    }
    
    public static func backspace(count: Int) {
        guard count > 0 else { return }
        
        // Backspace keycode on macOS is 51
        let backspaceKey: CGKeyCode = 51
        
        for _ in 0..<count {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: backspaceKey, keyDown: true)
            keyDown?.post(tap: .cghidEventTap)
            
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: backspaceKey, keyDown: false)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
    
    public static func pressEnter() {
        // Return keycode on macOS is 36
        let returnKey: CGKeyCode = 36
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: true)
        keyDown?.post(tap: .cghidEventTap)
        
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: false)
        keyUp?.post(tap: .cghidEventTap)
    }
}
