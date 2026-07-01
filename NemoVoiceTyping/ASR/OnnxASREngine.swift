import Foundation
import OnnxRuntimeBindings

public class OnnxASREngine: ASREngine {
    private var env: ORTEnv!
    private var encoder: ORTSession? = nil
    private var decoder: ORTSession? = nil
    private var joint: ORTSession? = nil
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
    
    // Cached mel frames from previous chunk
    private var melCache: [[Float]] = []
    private var melCachePrimed: Bool = false
    
    // Encoder states (persisted across chunks)
    private var cacheLastChannel: [Float] = []
    private var cacheLastTime: [Float] = []
    private var cacheLastChannelLen: [Int64] = [0]
    
    // Decoder states (persisted across utterances)
    private var hState: [Float] = []
    private var cState: [Float] = []
    private var lastToken: Int64 = 1024
    
    public init() {
        self.env = try! ORTEnv(loggingLevel: .warning)
        resetStates()
    }
    
    public func loadModel(from directory: URL) async throws {
        let encoderURL = directory.appendingPathComponent("encoder.onnx")
        let decoderURL = directory.appendingPathComponent("decoder.onnx")
        let jointURL = directory.appendingPathComponent("joint.onnx")
        let vocabURL = directory.appendingPathComponent("vocab.txt")
        
        let so = try ORTSessionOptions()
        try so.setIntraOpNumThreads(Int32(max(1, ProcessInfo.processInfo.activeProcessorCount / 2)))
        
        self.encoder = try ORTSession(env: env, modelPath: encoderURL.path, sessionOptions: so)
        self.decoder = try ORTSession(env: env, modelPath: decoderURL.path, sessionOptions: so)
        self.joint = try ORTSession(env: env, modelPath: jointURL.path, sessionOptions: so)
        self.tokenizer = try Tokenizer(vocabURL: vocabURL)
    }
    
    public func reset() {
        audioBuf.removeAll()
        melCachePrimed = false
        melCache = [[Float]](repeating: [Float](repeating: 0, count: preEncodeCacheFrames), count: nMels)
        lastToken = Int64(blankId)
        resetStates()
    }
    
    private func resetStates() {
        cacheLastChannel = [Float](repeating: 0.0, count: 1 * encLayers * leftContext * encHidden)
        cacheLastTime = [Float](repeating: 0.0, count: 1 * encLayers * encHidden * convContext)
        cacheLastChannelLen = [0]
        
        hState = [Float](repeating: 0.0, count: decLayers * 1 * decHidden)
        cState = [Float](repeating: 0.0, count: decLayers * 1 * decHidden)
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
        var audioSignal = [Float](repeating: 0, count: 1 * encoderTimeIn * nMels)
        for t in 0..<encoderTimeIn {
            for m in 0..<nMels {
                let val: Float
                if t < preEncodeCacheFrames {
                    val = melCachePrimed ? melCache[m][t] : 0.0
                } else {
                    val = newMels[m][t - preEncodeCacheFrames]
                }
                
                // Flat layout: [batch, time, mel] -> [0, t, m]
                let idx = t * nMels + m
                audioSignal[idx] = val
            }
        }
        
        // Update mel cache with latest 9 frames
        for m in 0..<nMels {
            for t in 0..<preEncodeCacheFrames {
                melCache[m][t] = newMels[m][newFrames - preEncodeCacheFrames + t]
            }
        }
        melCachePrimed = true
        
        // Create input ORTValues
        var lengthVal: Int64 = Int64(encoderTimeIn)
        
        let audioSignalData = NSMutableData(bytes: &audioSignal, length: audioSignal.count * MemoryLayout<Float>.size)
        let lengthData = NSMutableData(bytes: &lengthVal, length: MemoryLayout<Int64>.size)
        let cacheChannelData = NSMutableData(bytes: &cacheLastChannel, length: cacheLastChannel.count * MemoryLayout<Float>.size)
        let cacheTimeData = NSMutableData(bytes: &cacheLastTime, length: cacheLastTime.count * MemoryLayout<Float>.size)
        let cacheChannelLenData = NSMutableData(bytes: &cacheLastChannelLen, length: cacheLastChannelLen.count * MemoryLayout<Int64>.size)
        
        guard let audioSignalValue = try? ORTValue(tensorData: audioSignalData, elementType: .float, shape: [1, encoderTimeIn as NSNumber, nMels as NSNumber]),
              let lengthValue = try? ORTValue(tensorData: lengthData, elementType: .int64, shape: [1]),
              let cacheChannelValue = try? ORTValue(tensorData: cacheChannelData, elementType: .float, shape: [1, encLayers as NSNumber, leftContext as NSNumber, encHidden as NSNumber]),
              let cacheTimeValue = try? ORTValue(tensorData: cacheTimeData, elementType: .float, shape: [1, encLayers as NSNumber, encHidden as NSNumber, convContext as NSNumber]),
              let cacheChannelLenValue = try? ORTValue(tensorData: cacheChannelLenData, elementType: .int64, shape: [1]) else {
            return
        }
        
        let encoderInputs = [
            "audio_signal": audioSignalValue,
            "length": lengthValue,
            "cache_last_channel": cacheChannelValue,
            "cache_last_time": cacheTimeValue,
            "cache_last_channel_len": cacheChannelLenValue
        ]
        
        // Run Encoder
        guard let encoderOutputs = try? encoder.run(withInputs: encoderInputs, outputNames: ["outputs", "cache_last_channel_next", "cache_last_time_next", "cache_last_channel_len_next"], runOptions: nil) else {
            print("ONNX Encoder run failed")
            return
        }
        
        // Update states from Encoder outputs
        if let nextChannelTensor = encoderOutputs["cache_last_channel_next"],
           let nextTimeTensor = encoderOutputs["cache_last_time_next"],
           let nextChannelLenTensor = encoderOutputs["cache_last_channel_len_next"] {
            
            cacheLastChannel = extractFloatArray(from: nextChannelTensor)
            cacheLastTime = extractFloatArray(from: nextTimeTensor)
            cacheLastChannelLen = extractInt64Array(from: nextChannelLenTensor)
        }
        
        guard let outputsTensor = encoderOutputs["outputs"] else { return }
        let outputs = extractFloatArray(from: outputsTensor) // Flat size [1, 7, 1024]
        
        // Process each of the 7 encoder output time steps
        for t in 0..<encTimeOut {
            // Extract current encoder frame: [1, 1, 1024]
            var encFrame = [Float](repeating: 0, count: encHidden)
            for k in 0..<encHidden {
                let flatIdx = t * encHidden + k
                encFrame[k] = outputs[flatIdx]
            }
            
            var symbols = 0
            while symbols < maxSymbolsPerStep {
                // Setup Decoder Inputs
                var targetsVal = lastToken
                let targetsData = NSMutableData(bytes: &targetsVal, length: MemoryLayout<Int64>.size)
                let hData = NSMutableData(bytes: &hState, length: hState.count * MemoryLayout<Float>.size)
                let cData = NSMutableData(bytes: &cState, length: cState.count * MemoryLayout<Float>.size)
                
                guard let targetsValue = try? ORTValue(tensorData: targetsData, elementType: .int64, shape: [1, 1]),
                      let hValue = try? ORTValue(tensorData: hData, elementType: .float, shape: [decLayers as NSNumber, 1, decHidden as NSNumber]),
                      let cValue = try? ORTValue(tensorData: cData, elementType: .float, shape: [decLayers as NSNumber, 1, decHidden as NSNumber]) else {
                    break
                }
                
                let decoderInputs = [
                    "targets": targetsValue,
                    "h_in": hValue,
                    "c_in": cValue
                ]
                
                // Run Decoder
                guard let decoderOutputs = try? decoder.run(withInputs: decoderInputs, outputNames: ["decoder_output", "h_out", "c_out"], runOptions: nil) else { break }
                
                guard let decOutputTensor = decoderOutputs["decoder_output"],
                      let nextHTensor = decoderOutputs["h_out"],
                      let nextCTensor = decoderOutputs["c_out"] else { break }
                
                // Setup Joint Inputs
                let encFrameData = NSMutableData(bytes: &encFrame, length: encFrame.count * MemoryLayout<Float>.size)
                guard let encFrameValue = try? ORTValue(tensorData: encFrameData, elementType: .float, shape: [1, 1, encHidden as NSNumber]) else { break }
                
                let decoderForJoint = decoderOutputForJoint(from: decOutputTensor)
                let decoderForJointData = NSMutableData(bytes: decoderForJoint, length: decoderForJoint.count * MemoryLayout<Float>.size)
                guard let decoderForJointValue = try? ORTValue(tensorData: decoderForJointData, elementType: .float, shape: [1, 1, decHidden as NSNumber]) else { break }
                
                let jointInputs = [
                    "encoder_output": encFrameValue,
                    "decoder_output": decoderForJointValue
                ]
                
                // Run Joint
                guard let jointOutputs = try? joint.run(withInputs: jointInputs, outputNames: ["joint_output"], runOptions: nil) else { break }
                guard let jointOutTensor = jointOutputs["joint_output"] else { break }
                
                let logits = extractFloatArray(from: jointOutTensor) // Size [1025]
                
                // Argmax to find best token
                let best = argmax(logits)
                
                if best == blankId {
                    break
                }
                
                // Commit states and emit token
                lastToken = Int64(best)
                hState = extractFloatArray(from: nextHTensor)
                cState = extractFloatArray(from: nextCTensor)
                
                let piece = tokenizer.piece(id: best)
                onTokenEmitted?(piece)
                
                symbols += 1
            }
        }
    }
    
    private func extractFloatArray(from tensor: ORTValue) -> [Float] {
        guard let data = try? tensor.tensorData() else { return [] }
        let swiftData = data as Data
        return swiftData.withUnsafeBytes { rawBuffer in
            let floatPtr = rawBuffer.bindMemory(to: Float.self)
            return Array(floatPtr)
        }
    }
    
    private func decoderOutputForJoint(from tensor: ORTValue) -> [Float] {
        let decoderOutput = extractFloatArray(from: tensor)
        guard decoderOutput.count == decHidden else { return decoderOutput }
        return decoderOutput
    }
    
    private func extractInt64Array(from tensor: ORTValue) -> [Int64] {
        guard let data = try? tensor.tensorData() else { return [] }
        let swiftData = data as Data
        return swiftData.withUnsafeBytes { rawBuffer in
            let intPtr = rawBuffer.bindMemory(to: Int64.self)
            return Array(intPtr)
        }
    }
    
    private func argmax(_ array: [Float]) -> Int {
        var bestIndex = 0
        var bestValue: Float = -Float.greatestFiniteMagnitude
        for (i, val) in array.enumerated() {
            if val > bestValue {
                bestValue = val
                bestIndex = i
            }
        }
        return bestIndex
    }
}
