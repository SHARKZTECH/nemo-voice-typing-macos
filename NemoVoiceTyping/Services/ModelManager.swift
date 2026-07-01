import Foundation

public class ModelManager {
    public static let shared = ModelManager()
    
    public static let defaultRepo = "Garnet-Owl/nemo-voice-typing-asr"
    
    // Core files required by ASR engine
    public static let requiredFiles = [
        "encoder.onnx", "encoder.onnx.data",
        "decoder.onnx", "decoder.onnx.data",
        "joint.onnx", "joint.onnx.data",
        "vocab.txt",
        "genai_config.json", "audio_processor_config.json"
    ]
    
    public var defaultCacheDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("NemoVoiceTyping/models/v3", isDirectory: true)
    }
    
    private init() {}
    
    public func isModelDownloaded() -> Bool {
        let cacheDir = defaultCacheDir
        
        // On macOS with CoreML, we first check if the compiled CoreML models exist
        let coremlDownloaded = ["Encoder.mlpackage", "Decoder.mlpackage", "Joint.mlpackage", "vocab.txt"].allSatisfy {
            FileManager.default.fileExists(atPath: cacheDir.appendingPathComponent($0).path)
        }
        if coremlDownloaded {
            return true
        }
        
        // Fallback: check if raw ONNX files are downloaded
        for file in Self.requiredFiles {
            let fileURL = cacheDir.appendingPathComponent(file)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                return false
            }
        }
        return true
    }
    
    public func ensureModel(progressHandler: @escaping (String) -> Void) async throws -> URL {
        let cacheDir = defaultCacheDir
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true, attributes: nil)
        
        if isModelDownloaded() {
            return cacheDir
        }
        
        // Download missing files from Hugging Face
        let session = URLSession(configuration: .default)
        
        for (index, fileName) in Self.requiredFiles.enumerated() {
            let destinationURL = cacheDir.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                continue
            }
            
            let urlString = "https://huggingface.co/\(Self.defaultRepo)/resolve/main/\(fileName)"
            guard let url = URL(string: urlString) else {
                throw NSError(domain: "ModelManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Hugging Face URL for file \(fileName)"])
            }
            
            progressHandler("Downloading model file \(index + 1)/\(Self.requiredFiles.count)...")
            
            try await downloadFile(from: url, to: destinationURL, session: session, progressHandler: { bytesWritten, totalBytes in
                let percentage = totalBytes > 0 ? Int((Double(bytesWritten) / Double(totalBytes)) * 100) : 0
                progressHandler("Downloading \(fileName) (\(percentage)%)")
            })
        }
        
        return cacheDir
    }
    
    private func downloadFile(from url: URL, to destination: URL, session: URLSession, progressHandler: @escaping (Int64, Int64) -> Void) async throws {
        let tempURL = destination.appendingPathExtension("part")
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        let (location, response) = try await session.download(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "ModelManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to download \(url.lastPathComponent) from Hugging Face."])
        }
        
        // Move downloaded file to final destination
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: location, to: destination)
    }
}
