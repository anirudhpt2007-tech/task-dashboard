import SwiftUI
import AVFoundation

struct ContentView: View {
    @Bindable var engine: FaceIDEngine
    @AppStorage("reduceMotion") private var reduceMotion = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 24) {
            header
            scanner
            status
            controls
            privacy
        }
        .padding(32)
        .background(.black.gradient)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView(reduceMotion: $reduceMotion)
        }
    }

    private var header: some View {
        HStack {
            Text("Honest Face ID")
                .font(.title2.bold())
            Spacer()
            Button { showSettings = true } label: { Image(systemName: "gearshape").font(.title3) }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
        }
    }

    private var scanner: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28).fill(.white.opacity(0.08))
            CameraPreview(session: engine.capture.session)
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .opacity(engine.state == .idle || engine.state == .cameraDenied ? 0 : 0.55)
            FaceIDGlyph(isAnimating: !reduceMotion && engine.state == .scanning)
                .stroke(.cyan, lineWidth: 3).frame(width: 150, height: 150)
                .scaleEffect(!reduceMotion && engine.state == .scanning ? 1.06 : 1)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1).repeatForever(autoreverses: true),
                           value: engine.state == .scanning)
            if let face = engine.observation {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.green, lineWidth: 3)
                    .frame(width: 120 + face.boundingBox.width * 80, height: 150 + face.boundingBox.height * 30)
                    .transition(.opacity)
            }
        }
        .frame(height: 280)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: engine.observation)
    }

    private var status: some View {
        Text(statusText).font(.headline).multilineTextAlignment(.center).foregroundStyle(statusColor)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            if engine.state == .idle || engine.state == .cameraDenied || engine.state == .cancelled || engine.state == .success {
                Button("Start scan", systemImage: "camera") { engine.start() }.buttonStyle(.borderedProminent)
                if engine.state == .cameraDenied {
                    Button("Open Camera Settings") { engine.openCameraSettings() }.buttonStyle(.bordered)
                }
            } else if case .faceFound = engine.state {
                Button("Use system authentication", systemImage: "lock") { engine.authenticate() }.buttonStyle(.borderedProminent)
            } else {
                Button("Stop", systemImage: "stop.fill") { engine.stop() }.buttonStyle(.bordered)
            }
        }
    }

    private var privacy: some View {
        Text("Your camera frames are processed on this Mac and are never saved or sent anywhere. Face detection only helps guide the experience; it does not identify you.")
            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }

    private var statusText: String {
        switch engine.state {
        case .idle: "Ready when you are"
        case .ready: "Ready when you are"
        case .requestingCamera: "Requesting camera access…"
        case .cameraDenied: "Camera access is off. Enable it in System Settings."
        case .scanning: "Scanning…"
        case .positioning: "Move into view"
        case .aligned: "Center your face"
        case .noFace: "Move into view"
        case .multipleFaces: "Make sure only one person is visible"
        case .faceFound: "Face detected — continue with system authentication"
        case .authenticating: "Confirming with macOS…"
        case .success: "Authenticated by macOS"
        case .cancelled: "Authentication cancelled"
        case .unavailable(let message): message
        case .failed(let message): message
        }
    }
    private var statusColor: Color {
        switch engine.state { case .failed, .cameraDenied, .multipleFaces, .cancelled, .unavailable: .orange; case .success: .green; default: .white }
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

    struct FaceIDGlyph: Shape {
        var isAnimating: Bool
        var animatableData: CGFloat {
            get { isAnimating ? 1 : 0 }
            set {}
        }
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let inset = rect.width * 0.14
            let r = rect.insetBy(dx: inset, dy: inset)
            path.move(to: CGPoint(x: r.minX, y: r.minY + 28)); path.addLine(to: CGPoint(x: r.minX, y: r.minY)); path.addLine(to: CGPoint(x: r.minX + 28, y: r.minY))
            path.move(to: CGPoint(x: r.maxX - 28, y: r.minY)); path.addLine(to: CGPoint(x: r.maxX, y: r.minY)); path.addLine(to: CGPoint(x: r.maxX, y: r.minY + 28))
            path.move(to: CGPoint(x: r.minX, y: r.maxY - 28)); path.addLine(to: CGPoint(x: r.minX, y: r.maxY)); path.addLine(to: CGPoint(x: r.minX + 28, y: r.maxY))
            path.move(to: CGPoint(x: r.maxX - 28, y: r.maxY)); path.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 28))
            path.addEllipse(in: CGRect(x: r.midX - 22, y: r.midY - 28, width: 44, height: 56))
            return path
        }
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
