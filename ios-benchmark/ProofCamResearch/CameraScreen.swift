import SwiftUI
import AVFoundation
import UIKit
import CryptoKit

enum ProofCamTheme {
    static let ink = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.92, green: 0.90, blue: 0.83, alpha: 1) : UIColor(red: 0.12, green: 0.16, blue: 0.14, alpha: 1) })
    static let blue = Color(red: 0.30, green: 0.39, blue: 0.31)
    static let canvas = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.10, green: 0.12, blue: 0.11, alpha: 1) : UIColor(red: 0.95, green: 0.93, blue: 0.87, alpha: 1) })
    static let line = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.17) : UIColor(red: 0.26, green: 0.25, blue: 0.20, alpha: 0.16) })
    static let accent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.69, green: 0.79, blue: 0.62, alpha: 1) : UIColor(red: 0.30, green: 0.39, blue: 0.31, alpha: 1) })
    static let success = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.58, green: 0.78, blue: 0.62, alpha: 1) : UIColor(red: 0.22, green: 0.39, blue: 0.29, alpha: 1) })
    static let paper = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.16, green: 0.18, blue: 0.16, alpha: 1) : UIColor(red: 0.99, green: 0.98, blue: 0.94, alpha: 1) })
    static let illustrationPaper = Color(red: 0.99, green: 0.98, blue: 0.94)
    static let clay = Color(red: 0.74, green: 0.37, blue: 0.24)
    static let straw = Color(red: 0.83, green: 0.69, blue: 0.40)
}

struct ProofCamMark: View {
    var light = false
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(light ? ProofCamTheme.paper : ProofCamTheme.ink)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(light ? ProofCamTheme.ink : ProofCamTheme.paper)
                    }
            }
            Text("proofcam").font(.system(size: 17, weight: .semibold, design: .serif)).tracking(-0.5)
        }
    }
}

final class CameraSession: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "ProofCam.camera")
    private let output = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private var wanted = false
    private var completion: ((UIImage) -> Void)?
    @Published var ready = false
    @Published var takingPhoto = false
    @Published var message: String?
    @Published var zoom: CGFloat = 1
    @Published var flash = false
    @Published var hasFlash = false

    func start() {
        queue.async { self.wanted = true }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { self.configure() }
                else { DispatchQueue.main.async { self.message = "Allow camera access in Settings to take photos." } }
            }
        default: message = "Allow camera access in Settings to take photos."
        }
    }
    private func configure() {
        queue.async {
            guard self.wanted else { return }
            do {
                if self.input == nil {
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                        DispatchQueue.main.async { self.message = "Camera preview requires a physical iPhone." }; return
                    }
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .photo
                    let input = try AVCaptureDeviceInput(device: device)
                    guard self.session.canAddInput(input), self.session.canAddOutput(self.output) else {
                        self.session.commitConfiguration(); throw CaptureKey.Failure.unavailable
                    }
                    self.session.addInput(input); self.session.addOutput(self.output); self.input = input
                    self.output.maxPhotoQualityPrioritization = .quality
                    self.session.commitConfiguration()
                }
                if !self.session.isRunning { self.session.startRunning() }
                DispatchQueue.main.async {
                    self.ready = true; self.message = nil; self.hasFlash = self.input?.device.hasFlash == true
                }
            } catch { DispatchQueue.main.async { self.message = "The camera couldn’t start. Try opening Capture again." } }
        }
    }
    func stop() {
        queue.async {
            self.wanted = false
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.ready = false }
        }
    }
    func switchCamera() {
        guard !takingPhoto else { return }
        queue.async {
            guard let old = self.input,
                  let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: old.device.position == .back ? .front : .back),
                  let next = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration(); self.session.removeInput(old)
            if self.session.canAddInput(next) { self.session.addInput(next); self.input = next }
            else { self.session.addInput(old) }
            self.session.commitConfiguration()
            DispatchQueue.main.async { self.zoom = 1; self.flash = false; self.hasFlash = self.input?.device.hasFlash == true }
        }
    }
    func setZoom(_ value: CGFloat) {
        queue.async {
            guard let device = self.input?.device else { return }
            do {
                try device.lockForConfiguration()
                let applied = min(max(value, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
                device.videoZoomFactor = applied
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.zoom = applied }
            } catch { }
        }
    }
    func focus(_ point: CGPoint) {
        queue.async {
            guard let device = self.input?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) { device.focusPointOfInterest = point; device.focusMode = .autoFocus }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.continuousAutoExposure) { device.exposurePointOfInterest = point; device.exposureMode = .continuousAutoExposure }
                device.unlockForConfiguration()
            } catch { }
        }
    }
    func takePhoto(_ completed: @escaping (UIImage) -> Void) {
        guard ready, !takingPhoto, SecureEnclave.isAvailable else { return }
        completion = completed; takingPhoto = true
        let flash = self.flash
        queue.async {
            guard self.session.isRunning else { DispatchQueue.main.async { self.takingPhoto = false; self.completion = nil }; return }
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.photoQualityPrioritization = .quality
            if self.output.supportedFlashModes.contains(flash ? .on : .off) { settings.flashMode = flash ? .on : .off }
            if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        guard error != nil else { return }
        DispatchQueue.main.async {
            self.takingPhoto = false; self.completion = nil
            self.message = "Photo capture failed. Please try again."
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = error == nil ? photo.fileDataRepresentation().flatMap(UIImage.init(data:)) : nil
        DispatchQueue.main.async {
            self.takingPhoto = false
            let completed = self.completion; self.completion = nil
            if let image { completed?(image) }
            else { self.message = "Photo capture failed. Please try again." }
        }
    }
}

private final class Viewfinder: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var focusHandler: ((CGPoint) -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        focusHandler?(preview.captureDevicePointConverted(fromLayerPoint: gesture.location(in: self)))
    }
}
private struct CameraPreview: UIViewRepresentable {
    let camera: CameraSession
    func makeUIView(context: Context) -> Viewfinder {
        let view = Viewfinder(); view.preview.session = camera.session; view.preview.videoGravity = .resizeAspectFill
        view.focusHandler = camera.focus
        return view
    }
    func updateUIView(_ view: Viewfinder, context: Context) {
        if let connection = view.preview.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}

struct CameraRootView: View {
    @StateObject private var provenance = CaptureProvenance()
    @AppStorage("proofcam.introductionCompleted") private var introductionCompleted = false
    @State private var tab = 0
    var body: some View {
        Group {
            if introductionCompleted {
                TabView(selection: $tab) {
                    CaptureScreen(provenance: provenance, active: tab == 0)
                        .tabItem { Label("Capture", systemImage: "camera.fill") }.tag(0)
                    VerifyScreen(provenance: provenance)
                        .tabItem { Label("Verify", systemImage: "checkmark.shield") }.tag(1)
                    SettingsScreen()
                        .tabItem { Label("Settings", systemImage: "gearshape") }.tag(2)
                }
            } else {
                IntroductionScreen { introductionCompleted = true }
            }
        }.tint(ProofCamTheme.accent)
    }
}

struct CaptureScreen: View {
    @ObservedObject var provenance: CaptureProvenance
    let active: Bool
    @StateObject private var camera = CameraSession()
    @Environment(\.scenePhase) private var scenePhase
    @State private var library = false
    @AppStorage("proofcam.cameraGrid") private var showGrid = false
    @AppStorage("proofcam.shutterHaptics") private var shutterHaptics = true
    private var working: Bool { camera.takingPhoto || provenance.busy }
    private var canCapture: Bool { camera.ready && !working && SecureEnclave.isAvailable }
    private var captureReadinessLabel: String {
        if camera.ready && SecureEnclave.isAvailable { return "SECURE ENCLAVE SIGNING" }
        if camera.message?.contains("physical iPhone") == true { return "PHYSICAL IPHONE REQUIRED" }
        if !SecureEnclave.isAvailable { return "SECURE ENCLAVE UNAVAILABLE" }
        if camera.message != nil { return "CAMERA ACCESS NEEDED" }
        return "STARTING CAMERA"
    }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    Button { camera.flash.toggle() } label: {
                        Image(systemName: camera.flash ? "bolt.fill" : "bolt.slash")
                            .foregroundStyle(camera.flash ? ProofCamTheme.clay : ProofCamTheme.ink.opacity(0.75)).frame(width: 44, height: 44)
                    }.disabled(!camera.hasFlash || working).accessibilityLabel(camera.flash ? "Turn flash off" : "Turn flash on")
                    Spacer()
                    ProofCamMark()
                    Spacer()
                    Text("4:3").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(ProofCamTheme.ink.opacity(0.72)).frame(width: 44, height: 44)
                        .accessibilityLabel("Photo aspect ratio, four by three")
                }.padding(.horizontal, 14).frame(height: 48)
                ZStack {
                    CameraPreview(camera: camera)
                    if showGrid && camera.ready {
                        GeometryReader { grid in
                            Path { path in
                                for fraction in [CGFloat(1.0 / 3), CGFloat(2.0 / 3)] {
                                    path.move(to: CGPoint(x: grid.size.width * fraction, y: 0))
                                    path.addLine(to: CGPoint(x: grid.size.width * fraction, y: grid.size.height))
                                    path.move(to: CGPoint(x: 0, y: grid.size.height * fraction))
                                    path.addLine(to: CGPoint(x: grid.size.width, y: grid.size.height * fraction))
                                }
                            }.stroke(.white.opacity(0.35), lineWidth: 0.5)
                        }.allowsHitTesting(false)
                    }
                    if !camera.ready {
                        Color(white: 0.075)
                        VStack(spacing: 14) {
                            Image(systemName: "camera").font(.system(size: 38, weight: .light))
                            Text(camera.message ?? "Opening camera…").font(.callout).multilineTextAlignment(.center)
                            if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                                    .tint(.yellow)
                            }
                        }.foregroundStyle(.white.opacity(0.7)).padding(32)
                    }
                    VStack {
                        Spacer()
                        HStack(spacing: 14) {
                            ForEach([1, 2], id: \.self) { value in
                                Button { camera.setZoom(CGFloat(value)) } label: {
                                    Text("\(value)×").font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 42, height: 42)
                                        .background(Int(camera.zoom.rounded()) == value ? .white.opacity(0.28) : .black.opacity(0.46), in: Circle())
                                }.disabled(!camera.ready || working).accessibilityLabel("Zoom \(value) times")
                            }
                        }.padding(.bottom, 18)
                    }
                }
                .frame(height: min(geometry.size.width * 4 / 3, max(220, geometry.size.height - 225)))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 12)
                .clipped()
                VStack(spacing: 15) {
                    Label(captureReadinessLabel, systemImage: "lock.fill")
                        .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.1).foregroundStyle(ProofCamTheme.accent)
                    HStack {
                        Button { library = true } label: {
                            Group {
                                if let latest = provenance.pending.first, let image = UIImage(contentsOfFile: latest.jpeg.path) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                } else { Image(systemName: "photo.on.rectangle").font(.title2).foregroundStyle(ProofCamTheme.ink.opacity(0.7)) }
                            }.frame(width: 50, height: 50).background(ProofCamTheme.paper).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ProofCamTheme.line) }
                        }.accessibilityLabel("View captured photos")
                        Spacer()
                        Button {
                            if shutterHaptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                            camera.takePhoto { provenance.captured($0) }
                        } label: {
                            ZStack {
                                Circle().stroke(ProofCamTheme.ink, lineWidth: 3).frame(width: 76, height: 76)
                                Circle().fill(ProofCamTheme.blue.opacity(canCapture ? 1 : 0.38)).frame(width: 62, height: 62)
                                if working { ProgressView().tint(.black) }
                            }
                        }.disabled(!canCapture).accessibilityLabel(working ? "Signing photo" : "Take signed photo")
                        Spacer()
                        Button { camera.switchCamera() } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera").font(.system(size: 21))
                                .foregroundStyle(ProofCamTheme.ink).frame(width: 50, height: 50).background(ProofCamTheme.paper, in: Circle())
                                .overlay { Circle().stroke(ProofCamTheme.line) }
                        }.disabled(!camera.ready || working).accessibilityLabel("Switch camera")
                    }.padding(.horizontal, 30)
                    Text(working ? "Embedding proof and signing…" : "When capture completes, its proof stays inside the JPEG.")
                        .font(.footnote).foregroundStyle(ProofCamTheme.ink.opacity(0.65)).multilineTextAlignment(.center)
                }.padding(.top, 15)
                Spacer(minLength: 0)
            }.foregroundStyle(ProofCamTheme.ink).background(ProofCamTheme.canvas)
        }
        .task { if active { camera.start() } }
        .onChange(of: active) { _, value in if value && scenePhase == .active { camera.start() } else { camera.stop() } }
        .onChange(of: scenePhase) { _, value in if value == .active && active { camera.start() } else { camera.stop() } }
        .onDisappear { camera.stop() }
        .sheet(isPresented: $library) { CaptureLibrary(provenance: provenance) }
        .alert("Photo status", isPresented: Binding(get: { provenance.notice != nil }, set: { if !$0 { provenance.notice = nil } })) {
            Button("OK", role: .cancel) { provenance.notice = nil }
        } message: { Text(provenance.notice ?? "") }
    }
}

struct CaptureLibrary: View {
    @ObservedObject var provenance: CaptureProvenance
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                if provenance.pending.isEmpty {
                    VStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ProofCamTheme.paper)
                            ProofWorkshopIllustration().padding(12)
                        }.frame(height: 230)
                        WorkshopEyebrow(text: "Your archive")
                        Text("The first frame is still ahead.").font(.system(.title, design: .serif).weight(.bold)).multilineTextAlignment(.center)
                        Text("Signed photos you take with ProofCam will be kept here on this iPhone.")
                            .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(24).padding(.top, 24)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        WorkshopEyebrow(text: "Saved on this iPhone")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 10) {
                            ForEach(provenance.pending) { capture in
                                NavigationLink { CaptureDetail(capture: capture, provenance: provenance) } label: {
                                    GeometryReader { geometry in
                                        Group {
                                            if let image = UIImage(contentsOfFile: capture.jpeg.path) {
                                                Image(uiImage: image).resizable().scaledToFill()
                                            } else {
                                                ProofCamTheme.ink.overlay(Image(systemName: "photo").foregroundStyle(ProofCamTheme.paper))
                                            }
                                        }
                                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                                        .overlay(alignment: .bottomLeading) {
                                            VStack(alignment: .leading, spacing: 5) {
                                                Label(capture.hasRequest ? "Signed" : "Needs attention", systemImage: capture.hasRequest ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                                    .font(.caption2.weight(.semibold))
                                                Text(capture.createdAt.formatted(date: .abbreviated, time: .shortened))
                                                    .font(.caption2.monospacedDigit())
                                            }.foregroundStyle(.white).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                                .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom), alignment: .bottom)
                                        }
                                }
                                    .aspectRatio(0.82, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }.buttonStyle(.plain)
                                    .accessibilityLabel("Photo from \(capture.createdAt.formatted(date: .abbreviated, time: .shortened)), \(capture.hasRequest ? "signed" : "needs attention")")
                            }
                        }
                    }.padding(18)
                }
            }.background(ProofCamTheme.canvas).navigationTitle("Your photos").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
struct CaptureDetail: View {
    let capture: PendingCapture
    @ObservedObject var provenance: CaptureProvenance
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if let image = UIImage(contentsOfFile: capture.jpeg.path) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 430)
                        .background(ProofCamTheme.ink).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Label(capture.hasRequest ? "Signed on this iPhone" : "Signing incomplete", systemImage: capture.hasRequest ? "signature" : "exclamationmark.triangle")
                    .font(.headline).foregroundStyle(capture.hasRequest ? ProofCamTheme.success : ProofCamTheme.clay)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(ProofCamTheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                if capture.hasRequest {
                    if !capture.savedToPhotos {
                        Button("Save to Photos") { Task { await provenance.saveToPhotos(capture) } }.buttonStyle(.borderedProminent).disabled(provenance.savingIDs.contains(capture.id))
                    }
                    HStack(spacing: 24) {
                        ShareLink(item: capture.jpeg) { Label("Share photo", systemImage: "square.and.arrow.up") }
                        if FileManager.default.fileExists(atPath: capture.receipt.path) {
                            ShareLink(item: capture.receipt) { Label("Share signature", systemImage: "signature") }
                        }
                    }.font(.subheadline)
                    ShareLink(item: capture.request) { Text("Export registration request") }.font(.caption)
                    Text("The signed proof is embedded inside this JPEG, so it travels with the original. It does not prove that the scene itself is truthful.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                } else { Text("This photo was retained after an interrupted capture. It has not been saved to Photos as a signed image.").font(.footnote).foregroundStyle(.secondary) }
            }.padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 24)
        }.background(ProofCamTheme.canvas).navigationTitle(capture.createdAt.formatted(date: .abbreviated, time: .shortened)).navigationBarTitleDisplayMode(.inline)
    }
}

/// A small original, vector-drawn still-life used as the workshop's visual signature.
struct ProofWorkshopIllustration: View {
    var compact = false
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Circle().fill(ProofCamTheme.straw.opacity(0.42))
                    .frame(width: size.height * 0.78, height: size.height * 0.78)
                    .offset(x: size.width * 0.15, y: -size.height * 0.02)
                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.81))
                    path.addQuadCurve(to: CGPoint(x: size.width * 0.93, y: size.height * 0.81),
                                      control: CGPoint(x: size.width * 0.52, y: size.height * 0.70))
                    path.addLine(to: CGPoint(x: size.width * 0.90, y: size.height * 0.93))
                    path.addQuadCurve(to: CGPoint(x: size.width * 0.11, y: size.height * 0.93),
                                      control: CGPoint(x: size.width * 0.48, y: size.height * 0.99))
                    path.closeSubpath()
                }.fill(ProofCamTheme.clay)
                // A folded archive print: one corner lifts as if the photograph were freshly filed.
                RoundedRectangle(cornerRadius: size.height * 0.045, style: .continuous)
                    .fill(ProofCamTheme.illustrationPaper)
                    .frame(width: size.width * 0.49, height: size.height * 0.63)
                    .overlay(alignment: .top) {
                        ZStack {
                            RoundedRectangle(cornerRadius: size.height * 0.025, style: .continuous)
                                .fill(Color(red: 0.74, green: 0.79, blue: 0.65))
                                .frame(width: size.width * 0.40, height: size.height * 0.36)
                            Path { path in
                                path.move(to: CGPoint(x: size.width * 0.30, y: size.height * 0.50))
                                path.addCurve(to: CGPoint(x: size.width * 0.65, y: size.height * 0.50),
                                              control1: CGPoint(x: size.width * 0.39, y: size.height * 0.37),
                                              control2: CGPoint(x: size.width * 0.51, y: size.height * 0.62))
                            }.stroke(ProofCamTheme.blue.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: size.height * 0.07))
                                .foregroundStyle(ProofCamTheme.straw)
                                .offset(x: size.width * 0.14, y: -size.height * 0.10)
                        }.padding(.top, size.height * 0.045)
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 3) {
                            Capsule().fill(ProofCamTheme.ink.opacity(0.55)).frame(width: size.width * 0.20, height: 2)
                            Capsule().fill(ProofCamTheme.ink.opacity(0.25)).frame(width: size.width * 0.14, height: 2)
                        }.padding(.leading, size.width * 0.045).padding(.bottom, size.height * 0.055)
                    }
                    .overlay { RoundedRectangle(cornerRadius: size.height * 0.045).stroke(ProofCamTheme.ink.opacity(0.12), lineWidth: 1) }
                    .rotationEffect(.degrees(-7))
                    .offset(x: -size.width * 0.02, y: -size.height * 0.05)
                if !compact {
                    Image(systemName: "seal.fill")
                        .font(.system(size: size.height * 0.22))
                        .foregroundStyle(ProofCamTheme.blue)
                        .overlay { Image(systemName: "checkmark").font(.system(size: size.height * 0.075, weight: .bold)).foregroundStyle(.white) }
                        .rotationEffect(.degrees(12))
                        .offset(x: size.width * 0.30, y: size.height * 0.30)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
    }
}

struct WorkshopEyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.6)
            .foregroundStyle(ProofCamTheme.clay)
    }
}
