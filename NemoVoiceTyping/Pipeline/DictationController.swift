import Foundation
import AppKit

public class DictationController {
    private let config: AppConfig
    private let panelController: FloatingPanelController
    
    private let audio = AudioCapture()
    private let processor = DictationProcessor()
    private var asr: ASREngine? = nil
    
    private var isRunning: Bool = false
    private var isLoading: Bool = false
    private var timer: DispatchSourceTimer? = nil
    
    private let queue = DispatchQueue(label: "com.nemo.dictation.pipeline", qos: .userInteractive)
    
    public init(config: AppConfig, panelController: FloatingPanelController) {
        self.config = config
        self.panelController = panelController
        
        setupAudioCallbacks()
    }
    
    private func setupAudioCallbacks() {
        audio.onSamples = { [weak self] samples in
            self?.queue.async {
                self?.asr?.pushAudio(samples)
            }
        }
        
        audio.onLevel = { [weak self] level in
            DispatchQueue.main.async {
                self?.panelController.pushAudioLevel(level)
            }
        }
    }
    
    public func toggle() {
        guard !isLoading else { return }
        
        if isRunning {
            stop()
        } else {
            Task {
                await start()
            }
        }
    }
    
    @MainActor
    private func start() async {
        // 1. Verify Accessibility Permissions
        if !PermissionManager.isAccessibilityGranted() {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Accessibility Permissions Required"
            alert.informativeText = "Nemo Voice Typing needs Accessibility permissions to insert text directly into other applications.\n\nPlease enable it in System Settings and restart dictation."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                PermissionManager.requestAccessibilityPermission()
            }
            return
        }
        
        // 2. Verify Microphone Permissions
        let micGranted = await PermissionManager.checkMicrophonePermission()
        guard micGranted else {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Microphone Access Denied"
            alert.informativeText = "Please allow microphone access in System Settings -> Privacy & Security -> Microphone."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        
        // 3. Lazy download/compile models
        if asr == nil {
            isLoading = true
            panelController.setLoading(true)
            
            do {
                // Ensure model folder assets are downloaded (we'll implement ModelManager in Phase 5)
                let modelDir = try await ModelManager.shared.ensureModel(progressHandler: { [weak self] text in
                    DispatchQueue.main.async {
                        self?.panelController.setLoadingText(text)
                    }
                })
                
                // Initialize ASREngine (using ONNX Runtime directly)
                var engine: ASREngine = OnnxASREngine()
                
                try await engine.loadModel(from: modelDir)
                
                engine.onTokenEmitted = { [weak self] piece in
                    self?.queue.async {
                        self?.processor.push(piece: piece)
                    }
                }
                
                self.asr = engine
            } catch {
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = "Failed to load speech engine"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
                
                isLoading = false
                panelController.setLoading(false)
                return
            }
            
            isLoading = false
            panelController.setLoading(false)
        }
        
        // 4. Start pipeline
        asr?.reset()
        processor.reset()
        isRunning = true
        
        // Start Tick Timer (cadence of 100ms for buffer flush timeouts)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(100))
        t.setEventHandler { [weak self] in
            self?.processor.tick()
        }
        t.resume()
        self.timer = t
        
        do {
            try audio.start()
            panelController.setListening(true)
        } catch {
            stop()
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Failed to start microphone capture"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        
        audio.stop()
        
        timer?.cancel()
        timer = nil
        
        queue.sync {
            // Drain remaining tokens, flush commands
            processor.flushBuffer()
            processor.tick()
        }
        
        panelController.setListening(false)
    }
}
