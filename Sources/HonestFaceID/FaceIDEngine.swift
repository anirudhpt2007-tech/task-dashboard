import AVFoundation
import AppKit
import CoreImage
import Foundation
import LocalAuthentication
import Observation
import OSLog
import Vision

enum FaceIDState: Equatable {
    case idle
    case ready
    case requestingCamera
    case cameraDenied
    case scanning
    case positioning
    case aligned
    case noFace
    case multipleFaces
    case faceFound(confidence: Float)
    case authenticating
    case success
    case cancelled
    case unavailable(String)
    case failed(String)
}

struct FaceObservation: Equatable {
    var boundingBox: CGRect
    var confidence: Float
}

@MainActor
@Observable final class FaceIDEngine: NSObject {
    private(set) var state: FaceIDState = .idle
    private(set) var observation: FaceObservation?
    private(set) var sessionGeneration = UUID()
    let capture = CameraCapture()
    private let logger = Logger(subsystem: "com.example.HonestFaceID", category: "engine")
    private var visionTask: Task<Void, Never>?
    private var smoothing = FaceSmoother()

    func start() {
        let generation = UUID()
        sessionGeneration = generation
        visionTask?.cancel()
        smoothing.reset()
        observation = nil
        state = .requestingCamera
        capture.start { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.sessionGeneration == generation else { return }
                switch result {
                case .success(let image):
                    self.process(image, generation: generation)
                case .failure(let error):
                    self.capture.stop()
                    self.state = error == .denied ? .cameraDenied : .unavailable(error.localizedDescription)
                }
            }
        }
        state = .scanning
        logger.info("Started camera session")
    }

    func stop() {
        sessionGeneration = UUID()
        visionTask?.cancel()
        capture.stop()
        observation = nil
        state = .idle
        logger.info("Stopped camera session")
    }

    func openCameraSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else {
            logger.error("Could not create the Camera privacy settings URL")
            return
        }
        NSWorkspace.shared.open(url)
    }

    func authenticate() {
        guard case .faceFound = state else { return }
        let generation = sessionGeneration
        state = .authenticating
        let context = LAContext()
        context.localizedReason = "Confirm it’s you to continue"
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: context.localizedReason) { [weak self] success, error in
            Task { @MainActor [weak self] in
                guard let self, self.sessionGeneration == generation else { return }
                if success {
                    self.capture.stop()
                    self.state = .success
                    self.logger.info("System authentication succeeded")
                } else {
                    self.capture.stop()
                    self.state = (error as? LAError)?.code == .userCancel ? .cancelled : .failed(error?.localizedDescription ?? "Authentication failed")
                    self.logger.warning("System authentication failed")
                }
            }
        }
    }

    private func process(_ image: CGImage, generation: UUID) {
        visionTask?.cancel()
        visionTask = Task { [weak self] in
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
            do {
                try handler.perform([request])
                let faces = (request.results ?? []).map {
                    FaceObservation(boundingBox: $0.boundingBox, confidence: $0.confidence)
                }
                await MainActor.run {
                    guard let self, self.sessionGeneration == generation else { return }
                    self.apply(faces)
                }
            } catch {
                await MainActor.run {
                    guard let self, self.sessionGeneration == generation else { return }
                    self.capture.stop()
                    self.state = .unavailable("Face detection is unavailable")
                }
            }
        }
    }

    private func apply(_ faces: [FaceObservation]) {
        switch faces.count {
        case 0:
            observation = nil
            state = .positioning
        case 2...:
            observation = nil
            state = .multipleFaces
        default:
            let face = smoothing.add(faces[0])
            observation = face
            let centered = abs(face.boundingBox.midX - 0.5) < 0.18 &&
                abs(face.boundingBox.midY - 0.5) < 0.18
            let appropriateDistance = face.boundingBox.width >= 0.18 && face.boundingBox.width <= 0.72
            state = centered && appropriateDistance
                ? .faceFound(confidence: face.confidence)
                : .positioning
        }
    }
}

enum CameraError: Error, LocalizedError, Equatable {
    case denied
    case unavailable
    case interrupted
    case disconnected
    var errorDescription: String? {
        switch self {
        case .denied: "Camera access was denied"
        case .unavailable: "No camera is available"
        case .interrupted: "Camera was interrupted"
        case .disconnected: "Camera disconnected"
        }
    }
}

final class CameraCapture: NSObject, ObservableObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.frames", qos: .userInitiated)
    private var handler: (@Sendable (Result<CGImage, CameraError>) -> Void)?
    private var configured = false
    private let context = CIContext()
    private var lastFrameTime = CACurrentMediaTime()

    func start(handler: @escaping @Sendable (Result<CGImage, CameraError>) -> Void) {
        self.handler = handler
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: AVCaptureSession.wasInterruptedNotification, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(runtimeError), name: AVCaptureSession.runtimeErrorNotification, object: session)
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { handler(.failure(.denied)); return }
                self?.configureAndRun()
            }
        default: handler(.failure(.denied))
        }
    }

    func stop() {
        if session.isRunning { session.stopRunning() }
        handler = nil
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func interrupted() { handler?(.failure(.interrupted)) }
    @objc private func runtimeError() { handler?(.failure(.disconnected)) }

    private func configureAndRun() {
        guard !configured else { session.startRunning(); return }
        guard let device = AVCaptureDevice.default(for: .video) else {
            handler?(.failure(.unavailable)); return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            guard session.canAddInput(input), session.canAddOutput(output) else {
                session.commitConfiguration(); handler?(.failure(.unavailable)); return
            }
            session.addInput(input)
            output.setSampleBufferDelegate(self, queue: queue)
            output.alwaysDiscardsLateVideoFrames = true
            session.addOutput(output)
            session.commitConfiguration()
            configured = true
            session.startRunning()
        } catch { handler?(.failure(.unavailable)) }
    }
}

extension CameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let image = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = CACurrentMediaTime()
        guard now - lastFrameTime >= 0.15 else { return }
        lastFrameTime = now
        let ci = CIImage(cvPixelBuffer: image)
        guard let cg = context.createCGImage(ci, from: ci.extent) else { return }
        handler?(.success(cg))
    }
}

struct FaceSmoother {
    private var previous: FaceObservation?

    mutating func reset() {
        previous = nil
    }

    mutating func add(_ next: FaceObservation) -> FaceObservation {
        guard let previous else { self.previous = next; return next }
        let alpha: CGFloat = 0.22
        let box = previous.boundingBox.interpolate(to: next.boundingBox, amount: alpha)
        let result = FaceObservation(boundingBox: box, confidence: previous.confidence + (next.confidence - previous.confidence) * Float(alpha))
        self.previous = result
        return result
    }
}

private extension CGRect {
    func interpolate(to other: CGRect, amount: CGFloat) -> CGRect {
        CGRect(x: minX + (other.minX - minX) * amount, y: minY + (other.minY - minY) * amount,
               width: width + (other.width - width) * amount, height: height + (other.height - height) * amount)
    }
}
