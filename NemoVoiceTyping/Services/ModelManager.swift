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
    
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter
    }()
    
    public func isModelDownloaded() -> Bool {
        let cacheDir = defaultCacheDir
        
        for file in Self.requiredFiles {
            let fileURL = cacheDir.appendingPathComponent(file)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let fileSize = attributes[.size] as? NSNumber,
                  fileSize.int64Value > 0 else {
                return false
            }
        }
        return true
    }
    
    public func ensureModel(progressHandler: @escaping (String) -> Void) async throws -> URL {
        let cacheDir = defaultCacheDir
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true, attributes: nil)
        progressHandler("Checking speech model...")
        
        if isModelDownloaded() {
            progressHandler("Speech model ready")
            return cacheDir
        }
        
        // Download missing files from Hugging Face
        let session = URLSession(configuration: .default)
        
        for (index, fileName) in Self.requiredFiles.enumerated() {
            let destinationURL = cacheDir.appendingPathComponent(fileName)
            if isUsableModelFile(destinationURL) {
                continue
            }
            
            let urlString = "https://huggingface.co/\(Self.defaultRepo)/resolve/main/\(fileName)"
            guard let url = URL(string: urlString) else {
                throw NSError(domain: "ModelManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Hugging Face URL for file \(fileName)"])
            }
            
            let fileNumber = index + 1
            progressHandler("Starting \(fileName) (\(fileNumber)/\(Self.requiredFiles.count))")
            
            try await downloadFile(from: url, to: destinationURL, session: session, progressHandler: { bytesWritten, totalBytes in
                let received = Self.byteFormatter.string(fromByteCount: bytesWritten)
                if totalBytes > 0 {
                    let total = Self.byteFormatter.string(fromByteCount: totalBytes)
                    let percentage = Int((Double(bytesWritten) / Double(totalBytes)) * 100)
                    progressHandler("\(fileName) \(percentage)% (\(received)/\(total))")
                } else {
                    progressHandler("\(fileName) \(received) downloaded")
                }
            })
            
            progressHandler("Finished \(fileName) (\(fileNumber)/\(Self.requiredFiles.count))")
        }
        
        progressHandler("Speech model ready")
        return cacheDir
    }
    
    private func isUsableModelFile(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber else {
            return false
        }
        return fileSize.int64Value > 0
    }
    
    private func downloadFile(from url: URL, to destination: URL, session: URLSession, progressHandler: @escaping (Int64, Int64) -> Void) async throws {
        let tempURL = destination.appendingPathExtension("part")
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        let delegate = ModelDownloadDelegate(progressHandler: progressHandler)
        let progressSession = URLSession(configuration: session.configuration, delegate: delegate, delegateQueue: nil)
        defer {
            progressSession.invalidateAndCancel()
        }
        
        let (location, response) = try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            progressSession.downloadTask(with: url).resume()
        }
        
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

private final class ModelDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    var continuation: CheckedContinuation<(URL, URLResponse?), Error>? = nil
    private let progressHandler: (Int64, Int64) -> Void
    
    init(progressHandler: @escaping (Int64, Int64) -> Void) {
        self.progressHandler = progressHandler
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        progressHandler(totalBytesWritten, totalBytesExpectedToWrite)
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        continuation?.resume(returning: (location, downloadTask.response))
        continuation = nil
    }
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error, let continuation else { return }
        continuation.resume(throwing: error)
        self.continuation = nil
    }
}
