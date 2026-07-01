import Foundation
import CoreML

public class CoreMLASREngine: ASREngine {
    private var encoder: MLModel? = nil
    private var decoder: MLModel? = nil
    private var joint: MLModel? = nil
    private var tokenizer: Tokenizer? = nil
    private let melExtractor = MelExtractor()
    
    public var onTokenEmitted: ((String) -> Void)? = nil
    
    // Constants matching model shape definitions
    private let chunkSamples = 8960          // 560 ms @ 16 kHz
    private let encoderTimeIn = 65           // 56 hops in chunk + 9 cached frames
    private let preEncodeCacheFrames = 9
    private let nMels = 128
    private let encHidden = 1024
    private let encLayers = 24
    private let leftContext = 70
    private let convContext = 8
    private let encTimeOut = 7
    private let decLayers = 2
    private let decHidden = 640
    private let vocabSize = 1025
    private let blankId = 1024
    private let maxSymbolsPerStep = 10
    
    // Sliding audio buffer
    private var audioBuf: [Float] = []
    
    // Cached mel frames from previous chunk (size [nMels][preEncodeCacheFrames])
    private var melCache: [[Float]] = []
    private var melCachePrimed: Bool = false
    
    // Encoder states (persisted across chunks)
    private var cacheLastChannel: MLMultiArray!
    private var cacheLastTime: MLMultiArray!
    private var cacheLastChannelLen: MLMultiArray!
    
    // Decoder states (persisted across utterances)
    private var hState: MLMultiArray!
    private var cState: MLMultiArray!
    private var lastToken: Int = 1024
    
    public init() {
        resetStates()
    }
    
    public func loadModel(from directory: URL) async throws {
        // CoreML models can be dynamically compiled at runtime
        let encoderURL = directory.appendingPathComponent("Encoder.mlpackage")
        let decoderURL = directory.appendingPathComponent("Decoder.mlpackage")
        let jointURL = directory.appendingPathComponent("Joint.mlpackage")
        let vocabURL = directory.appendingPathComponent("vocab.txt")
        
        self.encoder = try await loadCompiledModel(at: encoderURL)
        self.decoder = try await loadCompiledModel(at: decoderURL)
        self.joint = try await loadCompiledModel(at: jointURL)
        self.tokenizer = try Tokenizer(vocabURL: vocabURL)
    }
    
    private func loadCompiledModel(at url: URL) async throws -> MLModel {
        let compiledURL: URL
        if url.pathExtension == "mlmodelc" {
            compiledURL = url
        } else {
            compiledURL = try await MLModel.compileModel(at: url)
        }
        
        let config = MLModelConfiguration()
        config.computeUnits = .all // Let Apple schedule on Neural Engine (ANE), GPU and CPU dynamically
        return try MLModel(contentsOf: compiledURL, configuration: config)
    }
    
    public func reset() {
        audioBuf.removeAll()
        melCachePrimed = false
        melCache = [[Float]](repeating: [Float](repeating: 0, count: preEncodeCacheFrames), count: nMels)
        lastToken = blankId
        resetStates()
    }
    
    private func resetStates() {
        // Pre-allocate state MLMultiArrays
        cacheLastChannel = try! MLMultiArray(shape: [1, encLayers as NSNumber, leftContext as NSNumber, encHidden as NSNumber], dataType: .float32)
        cacheLastTime = try! MLMultiArray(shape: [1, encLayers as NSNumber, encHidden as NSNumber, convContext as NSNumber], dataType: .float32)
        cacheLastChannelLen = try! MLMultiArray(shape: [1], dataType: .int32)
        
        hState = try! MLMultiArray(shape: [decLayers as NSNumber, 1, decHidden as NSNumber], dataType: .float32)
        cState = try! MLMultiArray(shape: [decLayers as NSNumber, 1, decHidden as NSNumber], dataType: .float32)
        
        // Zero them out
        zeroMultiArray(cacheLastChannel)
        zeroMultiArray(cacheLastTime)
        zeroMultiArray(cacheLastChannelLen)
        zeroMultiArray(hState)
        zeroMultiArray(cState)
    }
    
    public func pushAudio(_ samples: [Float]) {
        audioBuf.append(contentsOf: samples)
        
        while audioBuf.count >= chunkSamples {
            let chunk = Array(audioBuf.prefix(chunkSamples))
            audioBuf.removeFirst(chunkSamples)
            
            processChunk(chunk)
        }
    }
    
    private func processChunk(_ chunk: [Float]) {
        guard let encoder = encoder, let decoder = decoder, let joint = joint, let tokenizer = tokenizer else { return }
        
        let newFrames = chunkSamples / MelExtractor.hopLength // 56
        let newMels = melExtractor.compute(samples: chunk, frames: newFrames)
        
        // Form the input audio signal: [1, 65, 128]
        guard let audioSignal = try? MLMultiArray(shape: [1, encoderTimeIn as NSNumber, nMels as NSNumber], dataType: .float32) else { return }
        
        // Copy melCache (9 frames) and newMels (56 frames)
        for t in 0..<encoderTimeIn {
            for m in 0..<nMels {
                let val: Float
                if t < preEncodeCacheFrames {
                    val = melCachePrimed ? melCache[m][t] : 0.0
                } else {
                    val = newMels[m][t - preEncodeCacheFrames]
                }
                
                let index = [0, t, m] as [NSNumber]
                audioSignal[index] = val as NSNumber
            }
        }
        
        // Update mel cache with latest 9 frames
        for m in 0..<nMels {
            for t in 0..<preEncodeCacheFrames {
                melCache[m][t] = newMels[m][newFrames - preEncodeCacheFrames + t]
            }
        }
        melCachePrimed = true
        
        // Setup inputs for Encoder
        let length = try! MLMultiArray(shape: [1], dataType: .int32)
        length[0] = encoderTimeIn as NSNumber
        
        let encoderInputs = EncoderInput(
            audio_signal: audioSignal,
            length: length,
            cache_last_channel: cacheLastChannel,
            cache_last_time: cacheLastTime,
            cache_last_channel_len: cacheLastChannelLen
        )
        
        // Run Encoder
        guard let encoderOutputs = try? encoder.prediction(from: encoderInputs) else {
            print("Encoder prediction failed")
            return
        }
        
        // Save Encoder next states
        cacheLastChannel = encoderOutputs.featureValue(for: "cache_last_channel_next")?.multiArrayValue
        cacheLastTime = encoderOutputs.featureValue(for: "cache_last_time_next")?.multiArrayValue
        cacheLastChannelLen = encoderOutputs.featureValue(for: "cache_last_channel_len_next")?.multiArrayValue
        
        guard let outputs = encoderOutputs.featureValue(for: "outputs")?.multiArrayValue else { return }
        
        // Process each of the 7 encoder output time steps
        for t in 0..<encTimeOut {
            // Extract current encoder frame: [1, 1, 1024]
            guard let encFrame = try? MLMultiArray(shape: [1, 1, encHidden as NSNumber], dataType: .float32) else { continue }
            for k in 0..<encHidden {
                let outIdx = [0, t, k] as [NSNumber]
                let frameIdx = [0, 0, k] as [NSNumber]
                encFrame[frameIdx] = outputs[outIdx]
            }
            
            var symbols = 0
            while symbols < maxSymbolsPerStep {
                // Setup Decoder Inputs
                let targets = try! MLMultiArray(shape: [1, 1], dataType: .int32)
                targets[0] = lastToken as NSNumber
                
                let decoderInputs = DecoderInput(
                    targets: targets,
                    h_in: hState,
                    c_in: cState
                )
                
                // Run Decoder
                guard let decoderOutputs = try? decoder.prediction(from: decoderInputs) else { break }
                
                guard let decOutput = decoderOutputs.featureValue(for: "decoder_output")?.multiArrayValue,
                      let nextH = decoderOutputs.featureValue(for: "h_out")?.multiArrayValue,
                      let nextC = decoderOutputs.featureValue(for: "c_out")?.multiArrayValue else { break }
                
                // Setup Joint Inputs
                let jointInputs = JointInput(
                    encoder_output: encFrame,
                    decoder_output: decOutput
                )
                
                // Run Joint
                guard let jointOutputs = try? joint.prediction(from: jointInputs) else { break }
                guard let jointOut = jointOutputs.featureValue(for: "joint_output")?.multiArrayValue else { break }
                
                // Argmax to find best token
                let best = argmax(jointOut)
                
                if best == blankId {
                    break
                }
                
                // Commit states and emit token
                lastToken = best
                hState = nextH
                cState = nextC
                
                let piece = tokenizer.piece(id: best)
                onTokenEmitted?(piece)
                
                symbols += 1
            }
        }
    }
    
    private func zeroMultiArray(_ array: MLMultiArray) {
        let count = array.count
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: count)
        for i in 0..<count {
            ptr[i] = 0.0
        }
    }
    
    private func argmax(_ array: MLMultiArray) -> Int {
        var bestIndex = 0
        var bestValue: Float = -Float.greatestFiniteMagnitude
        let count = array.count
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: count)
        
        for i in 0..<count {
            if ptr[i] > bestValue {
                bestValue = ptr[i]
                bestIndex = i
            }
        }
        return bestIndex
    }
}

// Helpers for model inputs mapping
private class EncoderInput: MLFeatureProvider {
    var featureNames: Set<String> = ["audio_signal", "length", "cache_last_channel", "cache_last_time", "cache_last_channel_len"]
    
    let audio_signal: MLMultiArray
    let length: MLMultiArray
    let cache_last_channel: MLMultiArray
    let cache_last_time: MLMultiArray
    let cache_last_channel_len: MLMultiArray
    
    init(audio_signal: MLMultiArray, length: MLMultiArray, cache_last_channel: MLMultiArray, cache_last_time: MLMultiArray, cache_last_channel_len: MLMultiArray) {
        self.audio_signal = audio_signal
        self.length = length
        self.cache_last_channel = cache_last_channel
        self.cache_last_time = cache_last_time
        self.cache_last_channel_len = cache_last_channel_len
    }
    
    func featureValue(for featureName: String) -> MLFeatureValue? {
        switch featureName {
        case "audio_signal": return MLFeatureValue(multiArray: audio_signal)
        case "length": return MLFeatureValue(multiArray: length)
        case "cache_last_channel": return MLFeatureValue(multiArray: cache_last_channel)
        case "cache_last_time": return MLFeatureValue(multiArray: cache_last_time)
        case "cache_last_channel_len": return MLFeatureValue(multiArray: cache_last_channel_len)
        default: return nil
        }
    }
}

private class DecoderInput: MLFeatureProvider {
    var featureNames: Set<String> = ["targets", "h_in", "c_in"]
    
    let targets: MLMultiArray
    let h_in: MLMultiArray
    let c_in: MLMultiArray
    
    init(targets: MLMultiArray, h_in: MLMultiArray, c_in: MLMultiArray) {
        self.targets = targets
        self.h_in = h_in
        self.c_in = c_in
    }
    
    func featureValue(for featureName: String) -> MLFeatureValue? {
        switch featureName {
        case "targets": return MLFeatureValue(multiArray: targets)
        case "h_in": return MLFeatureValue(multiArray: h_in)
        case "c_in": return MLFeatureValue(multiArray: c_in)
        default: return nil
        }
    }
}

private class JointInput: MLFeatureProvider {
    var featureNames: Set<String> = ["encoder_output", "decoder_output"]
    
    let encoder_output: MLMultiArray
    let decoder_output: MLMultiArray
    
    init(encoder_output: MLMultiArray, decoder_output: MLMultiArray) {
        self.encoder_output = encoder_output
        self.decoder_output = decoder_output
    }
    
    func featureValue(for featureName: String) -> MLFeatureValue? {
        switch featureName {
        case "encoder_output": return MLFeatureValue(multiArray: encoder_output)
        case "decoder_output": return MLFeatureValue(multiArray: decoder_output)
        default: return nil
        }
    }
}
