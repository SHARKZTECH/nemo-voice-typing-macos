import Foundation
import Accelerate

public class MelExtractor {
    public static let sampleRate = 16000
    public static let nFft = 512
    public static let hopLength = 160
    public static let winLength = 400
    public static let nMels = 128
    public static let preemphasis: Float = 0.97
    private static let logEps: Float = 1e-10
    
    private let window: [Float]
    private var melFilterbank: [[Float]] // [nMels][nFft/2 + 1]
    
    // vDSP FFT setup
    private let fftSetup: vDSP.FFT<DSPSplitComplex>
    private let log2N = vDSP_Length(log2(Double(nFft)))
    
    public init() {
        // 1. Build Hann Window
        var win = [Float](repeating: 0, count: Self.winLength)
        vDSP_hann_window(&win, vDSP_Length(Self.winLength), Int32(vDSP_HANN_NORM))
        self.window = win
        
        // 2. Setup FFT
        self.fftSetup = vDSP.FFT(log2n: log2N, radix: .radix2, ofType: DSPSplitComplex.self)!
        
        // 3. Build Mel Filterbank
        self.melFilterbank = [[Float]]()
        buildMelFilterbank()
    }
    
    deinit {
        // vDSP.FFT automatically cleans up memory on Apple platforms in Swift
    }
    
    /// Computes log-mel spectrogram for given samples
    /// Output layout: [nMels][frames]
    public func compute(samples: [Float], frames: Int) -> [[Float]] {
        var spectrogram = [[Float]](repeating: [Float](repeating: 0, count: frames), count: Self.nMels)
        let specBins = Self.nFft / 2 + 1
        
        // Temporary buffers
        var windowedFrame = [Float](repeating: 0, count: Self.nFft)
        var realBuffer = [Float](repeating: 0, count: Self.nFft / 2)
        var imagBuffer = [Float](repeating: 0, count: Self.nFft / 2)
        var powerSpectrum = [Float](repeating: 0, count: specBins)
        
        for t in 0..<frames {
            let center = t * Self.hopLength
            
            // Apply Reflect Padding and Pre-emphasis into windowedFrame
            fillFrame(samples: samples, center: center, destination: &windowedFrame)
            
            // Perform FFT
            realBuffer.withUnsafeMutableBufferPointer { realPtr in
                imagBuffer.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                    
                    windowedFrame.withUnsafeBufferPointer { framePtr in
                        // Convert real array to even/odd split complex representation for vDSP real FFT
                        framePtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.nFft / 2) { complexPtr in
                            vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(Self.nFft / 2))
                        }
                    }
                    
                    // Forward FFT
                    fftSetup.forward(input: splitComplex, output: &splitComplex)
                    
                    // Calculate power spectrum: real^2 + imag^2
                    // For packed real FFT, the first element represents DC component,
                    // and splitComplex.imagp[0] represents Nyquist frequency.
                    let dc = splitComplex.realp[0] * splitComplex.realp[0]
                    let nyquist = splitComplex.imagp[0] * splitComplex.imagp[0]
                    powerSpectrum[0] = dc
                    powerSpectrum[specBins - 1] = nyquist
                    
                    // Rest of components
                    for i in 1..<(Self.nFft / 2) {
                        let r = splitComplex.realp[i]
                        let im = splitComplex.imagp[i]
                        powerSpectrum[i] = r * r + im * im
                    }
                }
            }
            
            // Project power spectrum to Mel scale and compute Log
            for m in 0..<Self.nMels {
                let filter = melFilterbank[m]
                var sum: Float = 0.0
                vDSP_dotpr(filter, 1, powerSpectrum, 1, &sum, vDSP_Length(specBins))
                
                spectrogram[m][t] = log(sum + Self.logEps)
            }
        }
        
        return spectrogram
    }
    
    private func fillFrame(samples: [Float], center: Int, destination: inout [Float]) {
        let half = Self.winLength / 2
        let start = center - half
        
        // Zero out destination
        for i in 0..<Self.nFft {
            destination[i] = 0.0
        }
        
        // Apply Hann window and pre-emphasis
        for i in 0..<Self.winLength {
            let idx = start + i
            let x = reflect(samples, idx)
            let prev = reflect(samples, idx - 1)
            let preemphasized = x - Self.preemphasis * prev
            destination[i] = preemphasized * window[i]
        }
    }
    
    private func reflect(_ s: [Float], _ i: Int) -> Float {
        let n = s.count
        if n == 0 { return 0.0 }
        
        var idx = i
        if idx < 0 {
            idx = -idx
        }
        if idx >= n {
            idx = 2 * (n - 1) - idx
        }
        if idx < 0 || idx >= n {
            return 0.0
        }
        return s[idx]
    }
    
    private func buildMelFilterbank() {
        let specBins = Self.nFft / 2 + 1
        var freqs = [Float](repeating: 0, count: specBins)
        for k in 0..<specBins {
            freqs[k] = Float(k * Self.sampleRate) / Float(Self.nFft)
        }
        
        let melMin = hzToMel(0.0)
        let melMax = hzToMel(Float(Self.sampleRate) / 2.0)
        
        var melPoints = [Float](repeating: 0, count: Self.nMels + 2)
        for i in 0..<(Self.nMels + 2) {
            let faction = Float(i) / Float(Self.nMels + 1)
            melPoints[i] = melToHz(melMin + (melMax - melMin) * faction)
        }
        
        for m in 0..<Self.nMels {
            var filter = [Float](repeating: 0, count: specBins)
            let left = melPoints[m]
            let center = melPoints[m + 1]
            let right = melPoints[m + 2]
            
            let lWidth = center - left
            let rWidth = right - center
            
            for k in 0..<specBins {
                let f = freqs[k]
                var w: Float = 0.0
                if f >= left && f <= center && lWidth > 0 {
                    w = (f - left) / lWidth
                } else if f > center && f <= right && rWidth > 0 {
                    w = (right - f) / rWidth
                }
                filter[k] = max(0.0, w)
            }
            melFilterbank.append(filter)
        }
    }
    
    private func hzToMel(_ hz: Float) -> Float {
        return 2595.0 * log10(1.0 + hz / 700.0)
    }
    
    private func melToHz(_ mel: Float) -> Float {
        return 700.0 * (pow(10.0, mel / 2595.0) - 1.0)
    }
}
