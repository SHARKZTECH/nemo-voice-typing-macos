import Foundation
import AppKit
import AVFoundation

public struct PermissionManager {
    
    // 1. Microphone authorization check
    public static func checkMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
    
    // 2. Accessibility authorization check (Win32 equivalent for SendInput permissions)
    public static func isAccessibilityGranted() -> Bool {
        return AXIsProcessTrusted()
    }
    
    // 3. Request Accessibility by opening system preferences deep link
    public static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        
        // If prompts fail to show, deep link directly to settings
        if !isAccessibilityGranted() {
            let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
