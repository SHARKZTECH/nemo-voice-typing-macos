import AppKit
import Carbon
import HotKey

public class HotkeyManager {
    private var hotKey: HotKey? = nil
    
    public var onTrigger: (() -> Void)? = nil
    
    public init() {}
    
    public func register(hotkeyString: String) -> Bool {
        hotKey = nil // clear existing
        
        guard let (modifiers, key) = parse(hotkeyString),
              canRegister(key: key, modifiers: modifiers) else {
            return false
        }
        
        // Create the HotKey
        let newHotKey = HotKey(key: key, modifiers: modifiers)
        newHotKey.keyDownHandler = { [weak self] in
            self?.onTrigger?()
        }
        
        self.hotKey = newHotKey
        return true
    }
    
    private func parse(_ hotkeyStr: String) -> (NSEvent.ModifierFlags, Key)? {
        var modifiers: NSEvent.ModifierFlags = []
        var selectedKey: Key? = nil
        
        let parts = hotkeyStr.lowercased().split(separator: "+")
        for part in parts {
            let cleanPart = part.trimmingCharacters(in: .whitespacesAndNewlines)
            switch cleanPart {
            case "cmd", "command", "⌘":
                modifiers.insert(.command)
            case "alt", "option", "⌥":
                modifiers.insert(.option)
            case "ctrl", "control", "⌃":
                modifiers.insert(.control)
            case "shift", "⇧":
                modifiers.insert(.shift)
            default:
                if let key = mapKeyString(cleanPart) {
                    selectedKey = key
                }
            }
        }
        
        guard let selectedKey else { return nil }
        
        // If no modifiers specified, default to Command + Option
        if modifiers.isEmpty {
            modifiers = [.command, .option]
        }
        
        return (modifiers, selectedKey)
    }
    
    private func canRegister(key: Key, modifiers: NSEvent.ModifierFlags) -> Bool {
        let combo = KeyCombo(key: key, modifiers: modifiers)
        let hotKeyID = EventHotKeyID(signature: Self.eventHotKeySignature, id: 1)
        var eventHotKey: EventHotKeyRef?
        
        let status = RegisterEventHotKey(
            combo.carbonKeyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &eventHotKey
        )
        
        if let eventHotKey {
            UnregisterEventHotKey(eventHotKey)
        }
        
        return status == noErr
    }
    
    private static let eventHotKeySignature: UInt32 = {
        var result: UInt32 = 0
        for char in "NvHt".utf16 {
            result = (result << 8) + UInt32(char)
        }
        return result
    }()
    
    private func mapKeyString(_ keyStr: String) -> Key? {
        // Standard alphabetical keys
        switch keyStr {
        case "a": return .a
        case "b": return .b
        case "c": return .c
        case "d": return .d
        case "e": return .e
        case "f": return .f
        case "g": return .g
        case "h": return .h
        case "i": return .i
        case "j": return .j
        case "k": return .k
        case "l": return .l
        case "m": return .m
        case "n": return .n
        case "o": return .o
        case "p": return .p
        case "q": return .q
        case "r": return .r
        case "s": return .s
        case "t": return .t
        case "u": return .u
        case "v": return .v
        case "w": return .w
        case "x": return .x
        case "y": return .y
        case "z": return .z
        case "0": return .zero
        case "1": return .one
        case "2": return .two
        case "3": return .three
        case "4": return .four
        case "5": return .five
        case "6": return .six
        case "7": return .seven
        case "8": return .eight
        case "9": return .nine
        case "space": return .space
        case "return", "enter": return .return
        case "escape", "esc": return .escape
        default: return nil
        }
    }
}
