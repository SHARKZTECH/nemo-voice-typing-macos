import AVFoundation
import Accelerate

public class AudioCapture {
    public static let sampleRate: Double = 16000
    
    private let audioEngine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    private var converter: AVAudioConverter? = nil
    
    public var onSamples: (([Float]) -> Void)? = nil
    public var onLevel: ((Double) -> Void)? = nil
    
    public private(set) var isRunning: Bool = false
    private let audioQueue = DispatchQueue(label: "com.nemo.audiocapture.queue", qos: .userInteractive)
    
    public init() {}
    
    public func start() throws {
        guard !isRunning else { return }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "AudioCapture", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid microphone input format."])
        }
        
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        
        // 20ms buffer size: target is 16kHz, so 20ms is 320 frames
        // Let's compute buffer size relative to hardware sample rate
        let bufferSize = AVAudioFrameCount(inputFormat.sampleRate * 0.02)
        
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            self?.audioQueue.async {
                self?.processAudio(buffer: buffer)
            }
        }
        
        try audioEngine.start()
        isRunning = true
    }
    
    public func stop() {
        guard isRunning else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRunning = false
        converter = nil
    }
    
    private func processAudio(buffer: AVAudioPCMBuffer) {
        guard let converter = converter else { return }
        
        // Compute output frame capacity
        let ratio = Self.sampleRate / buffer.format.sampleRate
        let targetCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetCapacity) else { return }
        
        var error: NSError? = nil
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
        
        if let err = error {
            print("Audio conversion error: \(err)")
            return
        }
        
        guard let floatData = outBuffer.floatChannelData?[0] else { return }
        let frameCount = Int(outBuffer.frameLength)
        guard frameCount > 0 else { return }
        
        // Extract samples into a Swift Array
        let samples = Array(UnsafeBufferPointer(start: floatData, count: frameCount))
        onSamples?(samples)
        
        // Calculate volume level / RMS using Accelerate framework (vDSP_measqv)
        var meanSquare: Float = 0.0
        vDSP_measqv(floatData, 1, &meanSquare, vDSP_Length(frameCount))
        let rms = sqrt(meanSquare)
        
        // Map -45 dBFS .. -5 dBFS to 0..1 (same as C# NAudio implementation)
        let db = 20.0 * log10(Double(rms) + 1e-9)
        let level = (db + 45.0) / 40.0
        let clampedLevel = max(0.0, min(1.0, level))
        
        onLevel?(clampedLevel)
    }
}
