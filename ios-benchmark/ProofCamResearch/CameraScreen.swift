import SwiftUI
import AVFoundation
import UIKit
import CryptoKit

enum ProofCamTheme {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static let text = adaptive(0x18212D, 0xE6EBF2)
    static let primary = adaptive(0x233F60, 0x304F73)
    static let background = adaptive(0xF2F4F7, 0x0D131C)
    static let surface = adaptive(0xFFFFFF, 0x17212E)
    static let border = adaptive(0xD9DFE7, 0x303D4D)
    static let accent = adaptive(0x264C77, 0xA6C2E2)
    static let success = adaptive(0x216E51, 0x8CC7AC)
    static let warning = adaptive(0xA14B27, 0xE1A27E)
}

struct ProofCamMark: View {
    var light = false
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "viewfinder")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(light ? Color.white : ProofCamTheme.text)
                .frame(width: 30, height: 30)
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(light ? Color.white.opacity(0.3) : ProofCamTheme.border) }
            Text("ProofCam").font(.system(size: 18, weight: .semibold)).tracking(-0.4)
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
                            .foregroundStyle(camera.flash ? ProofCamTheme.warning : ProofCamTheme.text.opacity(0.75)).frame(width: 44, height: 44)
                    }.disabled(!camera.hasFlash || working).accessibilityLabel(camera.flash ? "Turn flash off" : "Turn flash on")
                    Spacer()
                    ProofCamMark()
                    Spacer()
                    Text("4:3").font(.system(size: 13, weight: .medium, design: .default)).foregroundStyle(ProofCamTheme.text.opacity(0.72)).frame(width: 44, height: 44)
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
                                    .tint(ProofCamTheme.accent)
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
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 12)
                .clipped()
                VStack(spacing: 15) {
                    Label(captureReadinessLabel, systemImage: "lock.fill")
                        .font(.system(size: 10, weight: .bold, design: .default)).tracking(1.1).foregroundStyle(ProofCamTheme.accent)
                    HStack {
                        Button { library = true } label: {
                            Group {
                                if let latest = provenance.pending.first, let image = UIImage(contentsOfFile: latest.jpeg.path) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                } else { Image(systemName: "photo.on.rectangle").font(.title2).foregroundStyle(ProofCamTheme.text.opacity(0.7)) }
                            }.frame(width: 50, height: 50).background(ProofCamTheme.surface).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ProofCamTheme.border) }
                        }.accessibilityLabel("View captured photos")
                        Spacer()
                        Button {
                            if shutterHaptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                            camera.takePhoto { provenance.captured($0) }
                        } label: {
                            ZStack {
                                Circle().stroke(ProofCamTheme.text, lineWidth: 3).frame(width: 76, height: 76)
                                Circle().fill(ProofCamTheme.text.opacity(canCapture ? 1 : 0.38)).frame(width: 62, height: 62)
                                if working { ProgressView().tint(ProofCamTheme.background) }
                            }
                        }.disabled(!canCapture).accessibilityLabel(working ? "Signing photo" : "Take signed photo")
                        Spacer()
                        Button { camera.switchCamera() } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera").font(.system(size: 21))
                                .foregroundStyle(ProofCamTheme.text).frame(width: 50, height: 50).background(ProofCamTheme.surface, in: Circle())
                                .overlay { Circle().stroke(ProofCamTheme.border) }
                        }.disabled(!camera.ready || working).accessibilityLabel("Switch camera")
                    }.padding(.horizontal, 30)
                    Text(working ? "Embedding proof and signing…" : "When capture completes, its proof stays inside the JPEG.")
                        .font(.footnote).foregroundStyle(ProofCamTheme.text.opacity(0.65)).multilineTextAlignment(.center)
                }.padding(.top, 15)
                Spacer(minLength: 0)
            }.foregroundStyle(ProofCamTheme.text).background(ProofCamTheme.background)
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
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(ProofCamTheme.surface)
                            ProofDocumentIllustration().padding(12)
                        }.frame(height: 180)
                        SectionLabel(text: "Photo library")
                        Text("No captured photos").font(.system(.title, design: .default).weight(.bold)).multilineTextAlignment(.center)
                        Text("Signed photos you take with ProofCam will be kept here on this iPhone.")
                            .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(24).padding(.top, 24)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(text: "Saved on this iPhone")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 10) {
                            ForEach(provenance.pending) { capture in
                                NavigationLink { CaptureDetail(capture: capture, provenance: provenance) } label: {
                                    GeometryReader { geometry in
                                        Group {
                                            if let image = UIImage(contentsOfFile: capture.jpeg.path) {
                                                Image(uiImage: image).resizable().scaledToFill()
                                            } else {
                                                ProofCamTheme.text.overlay(Image(systemName: "photo").foregroundStyle(ProofCamTheme.surface))
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
            }.background(ProofCamTheme.background).navigationTitle("Your photos").navigationBarTitleDisplayMode(.inline)
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
                        .background(ProofCamTheme.text).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Label(capture.hasRequest ? "Signed on this iPhone" : "Signing incomplete", systemImage: capture.hasRequest ? "signature" : "exclamationmark.triangle")
                    .font(.headline).foregroundStyle(capture.hasRequest ? ProofCamTheme.success : ProofCamTheme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(ProofCamTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        }.background(ProofCamTheme.background).navigationTitle(capture.createdAt.formatted(date: .abbreviated, time: .shortened)).navigationBarTitleDisplayMode(.inline)
    }
}

/// A restrained representation of a photo and its accompanying signed record.
struct ProofDocumentIllustration: View {
    var compact = false
    var symbol = "photo"
    var body: some View {
        HStack(spacing: compact ? 20 : 28) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol).font(.system(size: compact ? 28 : 38, weight: .light))
                    .foregroundStyle(ProofCamTheme.accent)
                Text("ORIGINAL").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1)
                    .foregroundStyle(.secondary)
            }.frame(width: compact ? 82 : 108, height: compact ? 86 : 112)
                .background(ProofCamTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(ProofCamTheme.border) }
            Image(systemName: "link").font(.system(size: 17, weight: .regular)).foregroundStyle(ProofCamTheme.accent)
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "signature").font(.system(size: compact ? 25 : 32, weight: .light))
                Rectangle().fill(ProofCamTheme.border).frame(width: compact ? 40 : 60, height: 1)
                Text("SIGNED").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1)
                    .foregroundStyle(.secondary)
            }.foregroundStyle(ProofCamTheme.text)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityHidden(true)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.3)
            .foregroundStyle(.secondary)
    }
}
