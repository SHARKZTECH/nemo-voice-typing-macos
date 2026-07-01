import SwiftUI

@main
struct NemoVoiceTypingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Return Settings scene (standard way in SwiftUI to avoid creating a default window)
        Settings {
            EmptyView()
        }
    }
}
