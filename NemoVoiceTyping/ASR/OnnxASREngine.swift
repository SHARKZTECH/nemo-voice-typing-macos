import Foundation

public class OnnxASREngine: ASREngine {
    public var onTokenEmitted: ((String) -> Void)? = nil
    
    public init() {}
    
    public func loadModel(from directory: URL) async throws {
        // Dynamic ONNX Runtime fallback stub
        print("ONNX Runtime Fallback loaded (Stub)")
    }
    
    public func pushAudio(_ samples: [Float]) {
        // Stub implementation
        print("ONNX ASR Engine received audio chunk (Stub)")
    }
    
    public func reset() {
        print("ONNX ASR Engine reset (Stub)")
    }
}
