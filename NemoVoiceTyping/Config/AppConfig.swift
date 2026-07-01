import Foundation

public struct AppConfig: Codable {
    public var modelDirectory: String = ""
    public var hotkey: String = "cmd+alt+a"
    public var runAtStartup: Bool = false
    public var panelLeft: Double? = nil
    public var panelTop: Double? = nil
    public var alwaysOnTop: Bool = true
    public var preferCoreML: Bool = true

    private static var configURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("NemoVoiceTyping", isDirectory: true)
        // Ensure folder exists
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true, attributes: nil)
        return appFolder.appendingPathComponent("config.json")
    }

    public static func load() -> AppConfig {
        do {
            let data = try Data(contentsOf: configURL)
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            return AppConfig()
        }
    }

    public func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(self)
            try data.write(to: Self.configURL, options: .atomic)
        } catch {
            print("Failed to save config: \(error)")
        }
    }
}
