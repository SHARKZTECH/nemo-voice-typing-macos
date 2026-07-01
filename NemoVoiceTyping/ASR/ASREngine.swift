import Foundation

public protocol ASREngine {
    var onTokenEmitted: ((String) -> Void)? { get set }
    var onDebugStatus: ((String) -> Void)? { get set }
    
    func loadModel(from directory: URL) async throws
    func pushAudio(_ samples: [Float])
    func reset()
}
