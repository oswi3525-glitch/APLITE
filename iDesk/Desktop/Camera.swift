import AVFoundation
import Photos
import SwiftUI
import UIKit

/// The desktop camera window: a live preview with a shutter that saves to Files and Photos.
/// The external display gets no touches, so the shutter and flip rects are also exposed to
/// DesktopModel's hit testing — the buttons are real controls, not decoration.
final class CameraModel: ObservableObject {
    static let shared = CameraModel()

    @Published private(set) var authorization: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var isRunning = false
    @Published private(set) var flash = false
    @Published private(set) var lastImage: UIImage?

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private var configured = false
    private var flashWork: DispatchWorkItem?
    private static let fileDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return f
    }()
    let previewLayer = AVCaptureVideoPreviewLayer()

    private init() {
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
    }

    // MARK: Layout of the controls (window coordinates)

    func shutterRect(in frame: CGRect) -> CGRect {
        CGRect(x: frame.midX - 30, y: frame.maxY - 74, width: 60, height: 60)
    }

    func flipRect(in frame: CGRect) -> CGRect {
        CGRect(x: frame.maxX - 54, y: frame.minY + 46, width: 40, height: 34)
    }

    // MARK: Session

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startConfigured()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.authorization = AVCaptureDevice.authorizationStatus(for: .video)
                    if granted { self.startConfigured() }
                }
            }
        default:
            authorization = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    private func startConfigured() {
        if !configured {
            session.beginConfiguration()
            session.sessionPreset = .photo
            let position: AVCaptureDevice.Position = .front
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
               let candidate = try? AVCaptureDeviceInput(device: device), session.canAddInput(candidate) {
                session.addInput(candidate)
                input = candidate
            }
            if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
            session.commitConfiguration()
            configured = session.inputs.first != nil
        }
        guard configured, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async { self?.isRunning = true }
        }
    }

    func stop() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async { self?.isRunning = false }
        }
    }

    func flip() {
        guard let current = input else { return }
        let next: AVCaptureDevice.Position = current.device.position == .front ? .back : .front
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: next),
              let candidate = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.removeInput(current)
        if session.canAddInput(candidate) {
            session.addInput(candidate)
            input = candidate
        } else {
            session.addInput(current)
        }
        session.commitConfiguration()
    }

    // MARK: Capture

    func capture() {
        guard isRunning, session.outputs.contains(photoOutput) else { return }
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        photoOutput.capturePhoto(with: settings, delegate: CaptureDelegate.shared)
        flashWork?.cancel()
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.2)) { self?.flash = false }
        }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    fileprivate func received(_ image: UIImage) {
        lastImage = image
        let name = String(localized: "Camera") + " " + Self.fileDate.string(from: Date()) + ".jpg"
        let url = FileStore.uniqueURL(in: FileStore.downloads, name: name)
        try? image.jpegData(compressionQuality: 0.9)?.write(to: url)

        let model = DesktopModel.shared
        if let path = FileStore.relativePath(of: url) {
            withAnimation(.easeOut(duration: 0.25)) { model.screenshotPreview = ScreenshotPreview(image: image, path: path) }
            model.screenshotPreviewWork?.cancel()
            let work = DispatchWorkItem { [weak model] in
                withAnimation(.easeIn(duration: 0.25)) { model?.screenshotPreview = nil }
            }
            model.screenshotPreviewWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
        }
        model.showToast(String(localized: "Photo saved to Files"))
        DesktopModel.saveToPhotos(image) { saved in
            if saved { model.showToast(String(localized: "Photo saved to Photos and Files")) }
        }
    }
}

/// AVCapturePhotoOutput calls this on a background queue; hand the image back to the main actor.
private final class CaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    static let shared = CaptureDelegate()

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        let normalized: UIImage
        if image.imageOrientation != .up, let cg = image.cgImage {
            normalized = UIImage(cgImage: cg, scale: image.scale, orientation: .up)
        } else {
            normalized = image
        }
        DispatchQueue.main.async { CameraModel.shared.received(normalized) }
    }
}

/// Hosts the shared AVCaptureVideoPreviewLayer. The layer is never recreated, so rotating or
/// resizing the window does not interrupt the camera session.
private final class CameraPreviewUIView: UIView {
    let layerView = AVCaptureVideoPreviewLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layerView.session = CameraModel.shared.previewLayer.session
        layerView.videoGravity = .resizeAspectFill
        layer.addSublayer(layerView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layerView.frame = bounds
        CATransaction.setDisableActions(false)
        CATransaction.commit()
    }
}

struct CameraPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> CameraPreviewUIView { CameraPreviewUIView() }
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

/// The camera window's content. The shutter and flip glyphs are drawn here; clicks are handled by
/// DesktopModel using the same rects so they work on an external display and in preview mode.
struct CameraView: View {
    @ObservedObject private var camera = CameraModel.shared
    @ObservedObject var cursor: CursorModel
    let frame: CGRect

    var body: some View {
        let p = cursor.position
        let shutter = camera.shutterRect(in: frame)
        let flip = camera.flipRect(in: frame)
        ZStack {
            CameraPreview()
            if !camera.isRunning {
                VStack(spacing: 10) {
                    Image(systemName: camera.authorization == .denied ? "camera.slash" : "camera.fill")
                        .font(.system(size: 38))
                    Text(camera.authorization == .denied
                         ? String(localized: "Allow the camera in the iPhone's Settings.")
                         : String(localized: "Starting the camera…"))
                        .font(.system(size: 13))
                }
                .foregroundStyle(.white.opacity(0.8))
            }
            if camera.authorization == .authorized {
                Image(systemName: "camera.rotate")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: flip.width, height: flip.height)
                    .background(Circle().fill(Color.black.opacity(flip.contains(p) ? 0.55 : 0.32)))
                    .offset(x: flip.minX - frame.minX, y: flip.minY - frame.minY)

                ZStack {
                    Circle().fill(Color.white.opacity(0.22))
                    Circle().strokeBorder(Color.white, lineWidth: 3)
                    Circle().fill(Color.white).frame(width: 44, height: 44)
                }
                .frame(width: shutter.width, height: shutter.height)
                .scaleEffect(shutter.contains(p) ? 1.08 : 1)
                .animation(.easeOut(duration: 0.12), value: shutter.contains(p))
                .offset(x: shutter.minX - frame.minX, y: shutter.minY - frame.minY)
            }
            if camera.flash { Color.white.opacity(0.85) }
        }
        .clipped()
    }
}
