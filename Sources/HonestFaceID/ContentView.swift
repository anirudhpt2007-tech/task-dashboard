import SwiftUI
import AVFoundation
import AppKit

struct ContentView: View {
    @Bindable var engine: FaceIDEngine
    @AppStorage("reduceMotion") private var reduceMotion = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var showSettings = false

    private var isActive: Bool {
        switch engine.state {
        case .idle, .ready, .cameraDenied, .success, .cancelled, .unavailable, .failed: false
        default: true
        }
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                header
                Spacer(minLength: 24)
                scanner
                Spacer(minLength: 24)
                status
                controls
                privacy
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(maxWidth: 680)
        }
        .foregroundStyle(.primary)
        .sheet(isPresented: $showSettings) {
            SettingsView(reduceMotion: $reduceMotion)
        }
        .onExitCommand {
            guard isActive else { return }
            engine.stop()
        }
        .accessibilityAction(named: "Cancel scan") {
            guard isActive else { return }
            engine.stop()
        }
    }

    private var background: some View {
        ZStack {
            (colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color(nsColor: .controlBackgroundColor))
            RadialGradient(
                colors: [Color.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.08), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 500
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "faceid")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Honest Face ID")
                    .font(.title2.weight(.bold))
                Text("A camera-guided sign-in experience")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel("Settings")
        }
    }

    private var scanner: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
                }
            if engine.capture.session.isRunning {
                CameraPreview(session: engine.capture.session)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .opacity(0.48)
            }
            FaceIDGlyph(state: glyphState, reduceMotion: reduceMotion)
                .frame(width: 170, height: 170)
                .accessibilityHidden(true)
            if let face = engine.observation, isActive {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.green, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .frame(
                        width: 120 + face.boundingBox.width * 85,
                        height: 145 + face.boundingBox.height * 35
                    )
                    .transition(.opacity)
            }
        }
        .frame(height: 285)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: engine.observation)
        .accessibilityLabel("Face scan preview")
        .accessibilityValue(statusText)
    }

    private var status: some View {
        VStack(spacing: 7) {
            Text(statusText)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(statusColor)
            if case .faceFound(let confidence) = engine.state {
                Text("\(Int(confidence * 100))% detection confidence — this is not identity verification")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(minHeight: 55)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 12) {
            switch engine.state {
            case .idle, .ready, .cameraDenied, .cancelled, .success, .unavailable, .failed:
                Button("Start scan", systemImage: "camera") { engine.start() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                if case .cameraDenied = engine.state {
                    Button("Open Camera Settings") { engine.openCameraSettings() }
                        .buttonStyle(.bordered)
                }
            case .faceFound:
                Button("Use system authentication", systemImage: "lock") { engine.authenticate() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                cancelButton
            case .authenticating:
                ProgressView()
                    .controlSize(.small)
                cancelButton
            default:
                cancelButton
            }
        }
        .padding(.top, 4)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: engine.state)
    }

    private var cancelButton: some View {
        Button("Cancel", systemImage: "xmark") { engine.stop() }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
    }

    private var privacy: some View {
        Text("Camera frames are processed on this Mac and are never saved or sent anywhere. Vision detects face rectangles to guide positioning; it does not identify you and is not Apple's secure Face ID.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 570)
            .padding(.top, 20)
            .accessibilityLabel("Privacy note. Camera frames stay on this Mac and are never saved or sent. Vision only detects face rectangles to guide positioning. It does not identify you and is not Apple's secure Face ID.")
    }

    private var glyphState: FaceIDGlyph.State {
        switch engine.state {
        case .success: .success
        case .failed, .cancelled, .cameraDenied, .unavailable: .failure
        case .positioning, .aligned, .noFace, .multipleFaces: .positioning
        case .scanning, .requestingCamera: .scanning
        case .authenticating: .authenticating
        default: .idle
        }
    }

    private var statusText: String {
        switch engine.state {
        case .idle, .ready: "Ready when you are"
        case .requestingCamera: "Requesting camera access…"
        case .cameraDenied: "Camera access is off. Enable it in System Settings."
        case .scanning: "Scanning — look toward the camera"
        case .positioning, .aligned, .noFace: "Move into view and center your face"
        case .multipleFaces: "Make sure only one person is visible"
        case .faceFound: "Face detected — continue with system authentication"
        case .authenticating: "Confirming with macOS…"
        case .success: "Authenticated by macOS"
        case .cancelled: "Authentication cancelled"
        case .unavailable(let message), .failed(let message): message
        }
    }

    private var statusColor: Color {
        switch engine.state {
        case .success: .green
        case .failed, .cameraDenied, .multipleFaces, .cancelled, .unavailable: .orange
        default: .primary
        }
    }

    struct CameraPreview: NSViewRepresentable {
        let session: AVCaptureSession
        func makeNSView(context: Context) -> PreviewView { PreviewView(session: session) }
        func updateNSView(_ nsView: PreviewView, context: Context) { nsView.preview.session = session }
    }

    final class PreviewView: NSView {
        let preview: AVCaptureVideoPreviewLayer
        init(session: AVCaptureSession) {
            preview = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            preview.videoGravity = .resizeAspectFill
            wantsLayer = true
            layer?.addSublayer(preview)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layout() { super.layout(); preview.frame = bounds }
    }
}

struct FaceIDGlyph: View {
    enum State: Equatable {
        case idle, scanning, positioning, authenticating, success, failure
    }

    let state: State
    let reduceMotion: Bool
    @SwiftUI.State private var pulse = false

    init(state: State, reduceMotion: Bool) {
        self.state = state
        self.reduceMotion = reduceMotion
    }

    var body: some View {
        ZStack {
            GlyphOutline()
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .scaleEffect(pulse ? 1.05 : 0.96)
            if state == .scanning || state == .authenticating {
                Capsule()
                    .fill(color.opacity(0.75))
                    .frame(width: 105, height: 2)
                    .offset(y: pulse ? 45 : -45)
            }
            if state == .success {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.green)
                    .background(Circle().fill(.regularMaterial))
            } else if state == .failure {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.orange)
                    .background(Circle().fill(.regularMaterial))
            }
        }
        .onAppear { startAnimation() }
        .onChange(of: state) { _, _ in startAnimation() }
        .accessibilityLabel("Face scan indicator")
        .accessibilityValue(stateDescription)
    }

    private var color: Color {
        switch state {
        case .success: .green
        case .failure: .orange
        case .positioning: .yellow
        default: .accentColor
        }
    }

    private var stateDescription: String {
        switch state {
        case .idle: "Ready"
        case .scanning: "Scanning"
        case .positioning: "Positioning"
        case .authenticating: "Authenticating with macOS"
        case .success: "Success"
        case .failure: "Not completed"
        }
    }

    private func startAnimation() {
        guard !reduceMotion, state == .scanning || state == .authenticating else {
            pulse = false
            return
        }
        withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }

    private struct GlyphOutline: Shape {
        func path(in rect: CGRect) -> Path {
            let r = rect.insetBy(dx: rect.width * 0.14, dy: rect.height * 0.14)
            let corner = min(28, r.width * 0.24)
            var path = Path()
            path.move(to: CGPoint(x: r.minX, y: r.minY + corner)); path.addLine(to: CGPoint(x: r.minX, y: r.minY)); path.addLine(to: CGPoint(x: r.minX + corner, y: r.minY))
            path.move(to: CGPoint(x: r.maxX - corner, y: r.minY)); path.addLine(to: CGPoint(x: r.maxX, y: r.minY)); path.addLine(to: CGPoint(x: r.maxX, y: r.minY + corner))
            path.move(to: CGPoint(x: r.minX, y: r.maxY - corner)); path.addLine(to: CGPoint(x: r.minX, y: r.maxY)); path.addLine(to: CGPoint(x: r.minX + corner, y: r.maxY))
            path.move(to: CGPoint(x: r.maxX - corner, y: r.maxY)); path.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - corner))
            path.addEllipse(in: CGRect(x: r.midX - 22, y: r.midY - 28, width: 44, height: 56))
            return path
        }
    }
}

struct FaceIDActivityView: View {
    let state: FaceIDGlyph.State
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 12) {
            FaceIDGlyph(state: state, reduceMotion: true).frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct SettingsView: View {
    @Binding var reduceMotion: Bool
    var body: some View {
        Form {
            Toggle("Reduce motion", isOn: $reduceMotion)
            Text("This app uses public camera, Vision, and LocalAuthentication APIs. It does not implement or imitate biometric matching.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(28).frame(width: 380)
        .navigationTitle("Settings")
    }
}
