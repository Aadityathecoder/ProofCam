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
    static let text = adaptive(0x202C38, 0xE7EDF3)
    static let secondary = adaptive(0x647587, 0x9DAEBF)
    /// Brand slate blue; primary button fill in both appearances.
    static let primary = adaptive(0x889EB5, 0x889EB5)
    /// Label color on `primary` fills.
    static let onPrimary = adaptive(0x202C38, 0x202C38)
    static let brandLight = adaptive(0xA8BBCD, 0xA8BBCD)
    static let brandPale = adaptive(0xDCE6EE, 0x2A3644)
    static let background = adaptive(0xF7F9FB, 0x12181F)
    static let atmosphere = adaptive(0xE8EEF3, 0x161E27)
    static let surface = adaptive(0xFFFFFF, 0x1A222B)
    static let surfaceMuted = adaptive(0xEFF3F6, 0x222C36)
    static let border = adaptive(0xDDE5EC, 0x2C3844)
    /// Controls, toggles and selected states.
    static let accent = adaptive(0x526A82, 0xA8BBCD)
    static let success = adaptive(0x397866, 0x6FB39E)
    static let warning = adaptive(0xB65A58, 0xE08A87)
    static let atmosphereGradient = LinearGradient(colors: [background, atmosphere], startPoint: .top, endPoint: .bottom)
    static let brandGradient = LinearGradient(colors: [Color(red: 0x88 / 255, green: 0x9E / 255, blue: 0xB5 / 255),
                                                       Color(red: 0xA8 / 255, green: 0xBB / 255, blue: 0xCD / 255)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Avenir Next for display moments, SF Pro for UI, SF Mono for technical values.
enum ProofCamType {
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("AvenirNext-DemiBold", size: size, relativeTo: style)
    }
    static let technical = Font.system(.footnote, design: .monospaced)
}

/// Print registration mark: the ProofCam symbol for an image and its proof lining up.
struct RegistrationMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) * 0.27
        path.addEllipse(in: CGRect(x: rect.midX - radius, y: rect.midY - radius, width: radius * 2, height: radius * 2))
        path.move(to: CGPoint(x: rect.midX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

struct ProofCamMark: View {
    var light = false
    var body: some View {
        HStack(spacing: 8) {
            RegistrationMark().stroke(light ? Color.white : ProofCamTheme.text, lineWidth: 1.5)
                .frame(width: 20, height: 20)
            Text("ProofCam").font(ProofCamType.display(19, relativeTo: .headline))
        }.accessibilityElement(children: .combine).accessibilityLabel("ProofCam")
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(ProofCamTheme.onPrimary)
            .background(configuration.isPressed ? ProofCamTheme.brandLight : ProofCamTheme.primary,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(ProofCamTheme.text)
            .background(configuration.isPressed ? ProofCamTheme.surfaceMuted : ProofCamTheme.surface,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ProofCamTheme.border) }
            .opacity(isEnabled ? 1 : 0.45)
    }
}

/// One label/value line in an evidence record.
struct RecordRow: View {
    let label: String
    let value: String
    var tone: Color = ProofCamTheme.text
    var monospaced = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label).foregroundStyle(ProofCamTheme.secondary)
            Spacer(minLength: 8)
            Text(value).font(monospaced ? ProofCamType.technical : .body.weight(.medium))
                .foregroundStyle(tone).multilineTextAlignment(.trailing)
        }
        .font(.subheadline).padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(ProofCamTheme.border).frame(height: 1) }
        .accessibilityElement(children: .combine)
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
    var tapHandler: ((CGPoint) -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        focusHandler?(preview.captureDevicePointConverted(fromLayerPoint: location))
        tapHandler?(location)
    }
}
private struct CameraPreview: UIViewRepresentable {
    let camera: CameraSession
    var onTap: (CGPoint) -> Void = { _ in }
    func makeUIView(context: Context) -> Viewfinder {
        let view = Viewfinder(); view.preview.session = camera.session; view.preview.videoGravity = .resizeAspectFill
        view.focusHandler = camera.focus
        view.tapHandler = onTap
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
                        .tabItem { Label("Capture", systemImage: "camera") }.tag(0)
                    VerifyScreen(provenance: provenance)
                        .tabItem { Label("Verify", systemImage: "scope") }.tag(1)
                    SettingsScreen()
                        .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }.tag(2)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var library = false
    @State private var focusPoint: CGPoint?
    @State private var focusToken = 0
    @AppStorage("proofcam.cameraGrid") private var showGrid = false
    @AppStorage("proofcam.shutterHaptics") private var shutterHaptics = true
    private var working: Bool { camera.takingPhoto || provenance.busy }
    private var canCapture: Bool { camera.ready && !working && SecureEnclave.isAvailable }
    private var captureReadiness: (text: String, ready: Bool) {
        if camera.ready && SecureEnclave.isAvailable { return ("Secure Enclave signing on", true) }
        if camera.message?.contains("physical iPhone") == true { return ("Physical iPhone required", false) }
        if !SecureEnclave.isAvailable { return ("Secure Enclave unavailable", false) }
        if camera.message != nil { return ("Camera access needed", false) }
        return ("Starting camera", false)
    }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    Button { camera.flash.toggle() } label: {
                        Image(systemName: camera.flash ? "bolt.fill" : "bolt.slash")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(camera.flash ? ProofCamTheme.accent : ProofCamTheme.text.opacity(0.8)).frame(width: 44, height: 44)
                    }.disabled(!camera.hasFlash || working).accessibilityLabel(camera.flash ? "Turn flash off" : "Turn flash on")
                    Spacer()
                    ProofCamMark()
                    Spacer()
                    Text("4:3").font(.footnote.weight(.semibold)).foregroundStyle(ProofCamTheme.secondary).frame(width: 44, height: 44)
                        .accessibilityLabel("Photo aspect ratio, four by three")
                }.padding(.horizontal, 12).frame(height: 48)
                ZStack {
                    CameraPreview(camera: camera) { point in
                        focusPoint = point; focusToken += 1
                        let token = focusToken
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { if focusToken == token { focusPoint = nil } }
                    }
                    if showGrid && camera.ready {
                        GeometryReader { grid in
                            Path { path in
                                for fraction in [CGFloat(1.0 / 3), CGFloat(2.0 / 3)] {
                                    path.move(to: CGPoint(x: grid.size.width * fraction, y: 0))
                                    path.addLine(to: CGPoint(x: grid.size.width * fraction, y: grid.size.height))
                                    path.move(to: CGPoint(x: 0, y: grid.size.height * fraction))
                                    path.addLine(to: CGPoint(x: grid.size.width, y: grid.size.height * fraction))
                                }
                            }.stroke(.white.opacity(0.4), lineWidth: 0.5)
                        }.allowsHitTesting(false)
                    }
                    if camera.ready { ViewfinderCorners().allowsHitTesting(false) }
                    if let focusPoint {
                        RoundedRectangle(cornerRadius: 4).stroke(Color(red: 0.95, green: 0.76, blue: 0.31), lineWidth: 1.5)
                            .frame(width: 72, height: 72).position(focusPoint)
                            .transition(reduceMotion ? .opacity : .scale(scale: 1.4).combined(with: .opacity))
                            .id(focusToken).allowsHitTesting(false).accessibilityHidden(true)
                    }
                    if !camera.ready {
                        Color(red: 0.07, green: 0.09, blue: 0.11)
                        VStack(spacing: 14) {
                            Image(systemName: "camera").font(.system(size: 36, weight: .light))
                            Text(camera.message ?? "Opening camera…").font(.callout).multilineTextAlignment(.center)
                            if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                                    .buttonStyle(PrimaryButtonStyle()).frame(width: 200)
                            }
                        }.foregroundStyle(.white.opacity(0.78)).padding(32)
                    }
                    if camera.ready { VStack {
                        Spacer()
                        HStack(spacing: 12) {
                            ForEach([1, 2], id: \.self) { value in
                                let selected = Int(camera.zoom.rounded()) == value
                                Button { camera.setZoom(CGFloat(value)) } label: {
                                    Text("\(value)×").font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(selected ? Color(red: 0.95, green: 0.76, blue: 0.31) : .white)
                                        .frame(width: 42, height: 42)
                                        .background(.black.opacity(selected ? 0.66 : 0.4), in: Circle())
                                }.disabled(!camera.ready || working).accessibilityLabel("Zoom \(value) times")
                                    .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }.padding(.bottom, 16)
                    } }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: focusToken)
                .frame(height: min(geometry.size.width * 4 / 3, max(220, geometry.size.height - 200)))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 12)
                VStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Circle().fill(captureReadiness.ready ? ProofCamTheme.success : ProofCamTheme.secondary).frame(width: 6, height: 6)
                        Text(working ? "Embedding proof and signing…" : captureReadiness.text)
                    }.font(.caption.weight(.medium)).foregroundStyle(ProofCamTheme.secondary)
                        .accessibilityElement(children: .combine)
                    HStack {
                        Button { library = true } label: {
                            Group {
                                if let latest = provenance.pending.first, let image = UIImage(contentsOfFile: latest.jpeg.path) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                } else {
                                    Image(systemName: "photo.on.rectangle").font(.title3).foregroundStyle(ProofCamTheme.secondary)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(ProofCamTheme.surfaceMuted)
                                }
                            }.frame(width: 50, height: 50).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .padding(3).background(ProofCamTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                                .rotationEffect(.degrees(-3))
                        }.accessibilityLabel("View captured photos")
                        Spacer()
                        Button {
                            if shutterHaptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                            camera.takePhoto { provenance.captured($0) }
                        } label: {
                            ZStack {
                                Circle().stroke(ProofCamTheme.text, lineWidth: 3).frame(width: 78, height: 78)
                                Circle().fill(ProofCamTheme.text.opacity(canCapture ? 1 : 0.32)).frame(width: 64, height: 64)
                                if working { ProgressView().tint(ProofCamTheme.background) }
                            }
                        }.buttonStyle(ShutterButtonStyle()).disabled(!canCapture).accessibilityLabel(working ? "Signing photo" : "Take signed photo")
                        Spacer()
                        Button { camera.switchCamera() } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera").font(.system(size: 20))
                                .foregroundStyle(ProofCamTheme.text).frame(width: 52, height: 52).background(ProofCamTheme.surface, in: Circle())
                                .overlay { Circle().stroke(ProofCamTheme.border) }
                        }.disabled(!camera.ready || working).accessibilityLabel("Switch camera")
                    }.padding(.horizontal, 32)
                }.padding(.top, 16)
                Spacer(minLength: 0)
            }.foregroundStyle(ProofCamTheme.text).background(ProofCamTheme.atmosphereGradient.ignoresSafeArea(edges: .top))
        }
        .task { if active { camera.start() } }
        .onChange(of: active) { _, value in if value && scenePhase == .active { camera.start() } else { camera.stop() } }
        .onChange(of: scenePhase) { _, value in if value == .active && active { camera.start() } else { camera.stop() } }
        .onDisappear { camera.stop() }
        .sheet(isPresented: $library) { CaptureLibrary(provenance: provenance) }
        .sheet(isPresented: Binding(get: { provenance.notice != nil }, set: { if !$0 { provenance.notice = nil } })) {
            CaptureOutcomeSheet(message: provenance.notice ?? "", latest: provenance.pending.first) {
                provenance.notice = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { library = true }
            } done: { provenance.notice = nil }
                .presentationDetents([.medium]).presentationDragIndicator(.visible)
        }
    }
}

private struct ShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct ViewfinderCorners: View {
    var body: some View {
        GeometryReader { box in
            let inset: CGFloat = 16, arm: CGFloat = 18
            Path { path in
                let w = box.size.width, h = box.size.height
                for (x, y, dx, dy) in [(inset, inset, 1.0, 1.0), (w - inset, inset, -1.0, 1.0), (inset, h - inset, 1.0, -1.0), (w - inset, h - inset, -1.0, -1.0)] {
                    path.move(to: CGPoint(x: x, y: y + dy * arm)); path.addLine(to: CGPoint(x: x, y: y)); path.addLine(to: CGPoint(x: x + dx * arm, y: y))
                }
            }.stroke(.white.opacity(0.8), lineWidth: 2)
        }.accessibilityHidden(true)
    }
}

/// Replaces the generic alert after a capture with the photo and its outcome.
private struct CaptureOutcomeSheet: View {
    let message: String
    let latest: PendingCapture?
    let viewPhotos: () -> Void
    let done: () -> Void
    private var succeeded: Bool { message.hasPrefix("Proof embedded") }
    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .center, spacing: 16) {
                Group {
                    if let latest, let image = UIImage(contentsOfFile: latest.jpeg.path) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else { ProofCamTheme.surfaceMuted }
                }.frame(width: 84, height: 112).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(4).background(ProofCamTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 3).rotationEffect(.degrees(-3))
                VStack(alignment: .leading, spacing: 6) {
                    Label(succeeded ? "Signed" : "Needs attention", systemImage: succeeded ? "checkmark.circle" : "exclamationmark.circle")
                        .font(.caption.weight(.medium)).foregroundStyle(succeeded ? ProofCamTheme.success : ProofCamTheme.warning)
                    Text(message).font(ProofCamType.display(20, relativeTo: .headline)).foregroundStyle(ProofCamTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 12) {
                Button("View photos", action: viewPhotos).buttonStyle(PrimaryButtonStyle())
                Button("Done", action: done).buttonStyle(SecondaryButtonStyle())
            }
        }.padding(24).frame(maxHeight: .infinity, alignment: .top).background(ProofCamTheme.background)
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
                        ProofDocumentIllustration().frame(height: 180)
                        Text("No captured photos").font(ProofCamType.display(26)).multilineTextAlignment(.center)
                        Text("Signed photos you take with ProofCam will be kept here on this iPhone.")
                            .font(.body).foregroundStyle(ProofCamTheme.secondary).multilineTextAlignment(.center)
                    }.padding(24).padding(.top, 32)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 20) {
                        ForEach(provenance.pending) { capture in
                            NavigationLink { CaptureDetail(capture: capture, provenance: provenance) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Color.clear.aspectRatio(0.75, contentMode: .fit)
                                        .overlay {
                                            if let image = UIImage(contentsOfFile: capture.jpeg.path) {
                                                Image(uiImage: image).resizable().scaledToFill()
                                            } else {
                                                ProofCamTheme.surfaceMuted.overlay(Image(systemName: "photo").foregroundStyle(ProofCamTheme.secondary))
                                            }
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    HStack(spacing: 4) {
                                        Circle().fill(capture.hasRequest ? ProofCamTheme.success : ProofCamTheme.warning).frame(width: 6, height: 6)
                                        Text(capture.hasRequest ? "Signed" : "Incomplete").font(.caption.weight(.medium))
                                            .foregroundStyle(capture.hasRequest ? ProofCamTheme.success : ProofCamTheme.warning)
                                    }
                                    Text(capture.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2.monospacedDigit()).foregroundStyle(ProofCamTheme.secondary)
                                }
                            }.buttonStyle(.plain)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Photo from \(capture.createdAt.formatted(date: .abbreviated, time: .shortened)), \(capture.hasRequest ? "signed" : "signing incomplete")")
                        }
                    }.padding(20)
                }
            }.background(ProofCamTheme.background).navigationTitle("Captured photos").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct CaptureDetail: View {
    let capture: PendingCapture
    @ObservedObject var provenance: CaptureProvenance
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let image = UIImage(contentsOfFile: capture.jpeg.path) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 440)
                        .background(Color.black)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Label(capture.hasRequest ? "Signed on this iPhone" : "Signing incomplete",
                          systemImage: capture.hasRequest ? "checkmark.circle" : "exclamationmark.circle")
                        .font(.footnote.weight(.medium)).foregroundStyle(capture.hasRequest ? ProofCamTheme.success : ProofCamTheme.warning)
                    Text(capture.createdAt.formatted(date: .long, time: .shortened)).font(ProofCamType.display(26))
                        .padding(.top, 6).padding(.bottom, 20)
                    if capture.hasRequest {
                        RecordRow(label: "Proof", value: "Embedded in JPEG")
                        RecordRow(label: "Signing key", value: "Secure Enclave")
                        RecordRow(label: "Photos", value: capture.savedToPhotos ? "Saved" : "Not saved",
                                  tone: capture.savedToPhotos ? ProofCamTheme.text : ProofCamTheme.secondary)
                        RecordRow(label: "Capture ID", value: String(capture.id.prefix(8)), monospaced: true)
                        VStack(spacing: 12) {
                            ShareLink(item: capture.jpeg) { Label("Share photo", systemImage: "square.and.arrow.up") }
                                .buttonStyle(PrimaryButtonStyle())
                            if !capture.savedToPhotos {
                                Button("Save to Photos") { Task { await provenance.saveToPhotos(capture) } }
                                    .buttonStyle(SecondaryButtonStyle()).disabled(provenance.savingIDs.contains(capture.id))
                            }
                            HStack(spacing: 20) {
                                if FileManager.default.fileExists(atPath: capture.receipt.path) {
                                    ShareLink(item: capture.receipt) { Text("Share signature file") }
                                }
                                ShareLink(item: capture.request) { Text("Export registration request") }
                            }.font(.footnote).tint(ProofCamTheme.accent).padding(.top, 4)
                        }.padding(.top, 24)
                        Text("The signed proof is embedded inside this JPEG, so it travels with the original. It does not prove that the scene itself is truthful.")
                            .font(.footnote).foregroundStyle(ProofCamTheme.secondary).padding(.top, 20)
                    } else {
                        Text("This photo was retained after an interrupted capture. It has not been saved to Photos as a signed image.")
                            .font(.subheadline).foregroundStyle(ProofCamTheme.secondary)
                    }
                }.padding(20)
            }
        }.background(ProofCamTheme.background).navigationBarTitleDisplayMode(.inline)
    }
}

/// A photo print with its proof slip tucked behind it.
struct ProofDocumentIllustration: View {
    var compact = false
    var symbol = "photo"
    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("SHA-256").font(.system(size: 10, weight: .semibold, design: .monospaced))
                Text("P-256 signature").font(.system(size: 10, design: .monospaced))
                Rectangle().fill(ProofCamTheme.border).frame(width: 60, height: 1)
            }
            .foregroundStyle(ProofCamTheme.text).padding(10)
            .background(ProofCamTheme.surface, in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(ProofCamTheme.border) }
            .rotationEffect(.degrees(5)).offset(x: compact ? 40 : 56, y: compact ? 14 : 20)
            Image(systemName: symbol).font(.system(size: compact ? 26 : 34, weight: .light))
                .foregroundStyle(ProofCamTheme.onPrimary)
                .frame(width: compact ? 84 : 112, height: compact ? 104 : 136)
                .background(ProofCamTheme.brandGradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(5).background(ProofCamTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                .rotationEffect(.degrees(-3)).offset(x: compact ? -20 : -28)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityHidden(true)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text).font(.footnote.weight(.medium)).foregroundStyle(ProofCamTheme.secondary)
    }
}
