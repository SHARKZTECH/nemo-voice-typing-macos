import SwiftUI

public struct FloatingPanelView: View {
    // UI State
    @State public var isListening: Bool = false
    @State public var isLoading: Bool = false
    @State public var loadingText: String = ""
    @State public var audioLevels: [CGFloat] = [0.1, 0.1, 0.1, 0.1, 0.1]
    
    // Callbacks
    public var onMicTapped: (() -> Void)? = nil
    public var onHideTapped: (() -> Void)? = nil
    public var onExitTapped: (() -> Void)? = nil
    
    // Pulse animation state
    @State private var pulseScale: CGFloat = 1.0
    @State private var loadingPhase: Double = 0.0
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 12) {
            // Drag Indicator Handle
            VStack(spacing: 3) {
                ForEach(0..<3) { _ in
                    Circle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 3, height: 3)
                }
            }
            .frame(width: 8)
            .padding(.leading, 4)
            
            // Microphone Button
            Button(action: {
                onMicTapped?()
            }) {
                ZStack {
                    Circle()
                        .fill(
                            isListening
                            ? RadialGradient(colors: [Color(red: 1.0, green: 0.2, blue: 0.3), Color(red: 0.8, green: 0.0, blue: 0.1)], center: .center, startRadius: 0, endRadius: 18)
                            : RadialGradient(colors: [Color.secondary.opacity(0.3), Color.secondary.opacity(0.15)], center: .center, startRadius: 0, endRadius: 18)
                        )
                        .frame(width: 32, height: 32)
                        .scaleEffect(isListening ? pulseScale : 1.0)
                    
                    Image(systemName: isListening ? "mic.fill" : "mic.slash.fill")
                        .foregroundColor(isListening ? .white : .primary.opacity(0.7))
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .buttonStyle(.plain)
            .help("Toggle Voice Typing (⌘⌥A)")
            
            if isLoading {
                // Loading Text with micro pulsing dots
                HStack(spacing: 6) {
                    Text(loadingText.isEmpty ? "Loading..." : loadingText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.primary.opacity(0.8))
                        .lineLimit(1)
                    
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                }
                .transition(.opacity.combined(with: .scale))
            } else {
                // Audio Levels Visualizer
                HStack(spacing: 3) {
                    ForEach(0..<audioLevels.count, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                isListening
                                ? LinearGradient(colors: [Color.orange, Color.pink], startPoint: .bottom, endPoint: .top)
                                : LinearGradient(colors: [Color.primary.opacity(0.2)], startPoint: .bottom, endPoint: .top)
                            )
                            .frame(width: 4, height: isListening ? audioLevels[index] * 22 + 4 : 4)
                            .animation(.easeOut(duration: 0.1), value: audioLevels[index])
                    }
                }
                .frame(width: 36)
                .transition(.opacity)
            }
            
            // Exit/Close buttons context triggers or a small drop down
            Menu {
                Button("Hide Pill", action: { onHideTapped?() })
                Button("Quit Nemo", action: { onExitTapped?() })
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .foregroundColor(.primary.opacity(0.4))
                    .font(.system(size: 14))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 16)
            .padding(.trailing, 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .frame(width: isLoading ? 340 : 160, height: 44)
        .onAppear {
            if isListening {
                startPulsing()
            }
        }
        .onChange(of: isListening) { listening in
            if listening {
                startPulsing()
            } else {
                pulseScale = 1.0
            }
        }
    }
    
    private func startPulsing() {
        withAnimation(Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            pulseScale = 1.15
        }
    }
}
