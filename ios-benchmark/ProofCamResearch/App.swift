import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import CryptoKit
import Security
import Darwin

private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
private func recover(_ image: RGBImage,candidate: String) throws -> Recovery {
    if candidate==AdaptiveCandidate.name { return try AdaptiveCandidate.extract(image) }
    if candidate==TiledCandidate.name { return try TiledCandidate.extract(image) }
    return try RegisteredCandidate.extract(image)
}
struct ExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct Sample: Codable { let embedJPEGMilliseconds: Double; let extractMilliseconds: Double; let recovery: Recovery }
struct ScreenshotResult: Codable { let sha256: String; let width: Int; let height: Int; let rectangle: [Int]?; let operatorAttestedOSCapture: Bool; let recovery: Recovery }
struct Report: Codable {
    let hardwareModel: String; let executableSHA256: String?
    let inputWidth: Int; let inputHeight: Int
    var embedP95Milliseconds: Double { ResearchUtilities.p95(samples.map(\.embedJPEGMilliseconds)) ?? 0 }
    var extractP95Milliseconds: Double { ResearchUtilities.p95(samples.map(\.extractMilliseconds)) ?? 0 }
    let candidate: String; let createdAt: Date; let operatingSystem: String; let runtime: String
    let sourceSHA256: String; let markedSHA256: String; let expectedID: String
    let warmups: Int; let samples: [Sample]; var screenshots: [ScreenshotResult]
    var memoryMeasurement: String = "not_measured"
}
@MainActor final class Model: ObservableObject {
    @Published var status = "Import a JPEG or PNG from Files. Research use only."
    @Published var busy = false
    @Published var candidateVersion = 3
    @Published var marked: Data?
    @Published var report: Report?
    func load(_ url: URL, screenshot: Bool, rectangle: String, attested: Bool) {
        guard !busy else { return }; busy = true
        if !screenshot { report = nil; marked = nil }
        let prior = report
        let version = candidateVersion
        let tiled = version != 1
        let candidate = version == 3 ? AdaptiveCandidate.name : tiled ? TiledCandidate.name : RegisteredCandidate.name
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { () -> (Data?, Report) in
                    let accessed = url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                    let data = try ResearchUtilities.readBounded(limit: 25*1024*1024) { try handle.read(upToCount: $0) ?? Data() }
                    let original = try AppleImageCodec.decode(data)
                    if screenshot {
                        guard var current = prior else { throw ResearchError.invalidID }
                        let box = try ResearchUtilities.rectangle(rectangle)
                        let region = try box.map { try original.cropped($0) } ?? original
                        let recovered = try recover(region,candidate:current.candidate)
                        current.screenshots.append(ScreenshotResult(sha256: sha(data), width: original.width, height: original.height, rectangle: box, operatorAttestedOSCapture: attested, recovery: recovered))
                        return (nil, current)
                    }
                    let input = try original.atLongEdge(1024, upscale: tiled)
                    var random = [UInt8](repeating: 0, count: 16)
                    guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else { throw ResearchError.invalidID }
                    let id = random.map { String(format: "%02x", $0) }.joined()
                    var samples = [Sample](), output = Data()
                    for iteration in 0..<23 {
                        try autoreleasepool {
                        let start = DispatchTime.now().uptimeNanoseconds
                        let markedImage = try version == 3 ? AdaptiveCandidate.embed(input,id:id) : tiled ? TiledCandidate.embed(input,id:id) : DCTCore.embed(input,id:id)
                        output = try AppleImageCodec.jpeg(markedImage)
                        let encoded = DispatchTime.now().uptimeNanoseconds
                        let decoded = try AppleImageCodec.decode(output)
                        let extractStart = DispatchTime.now().uptimeNanoseconds
                        let recovery = try recover(decoded,candidate:candidate)
                        let end = DispatchTime.now().uptimeNanoseconds
                        if iteration >= 3 { samples.append(Sample(embedJPEGMilliseconds: Double(encoded-start)/1e6, extractMilliseconds: Double(end-extractStart)/1e6, recovery: recovery)) }
                        }
                        await MainActor.run { self.status = iteration < 3 ? "Warmup \(iteration+1)/3" : "Measured sample \(iteration-2)/20" }
                    }
                    #if targetEnvironment(simulator)
                    let runtime = "simulator"
                    #else
                    let runtime = "physical_device"
                    #endif
                    var system = utsname(); uname(&system)
                    let hardware = withUnsafeBytes(of: &system.machine) { bytes in String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self) }
                    let executable = Bundle.main.executableURL.flatMap { try? Data(contentsOf: $0) }.map(sha)
                    return (output, Report(hardwareModel: hardware, executableSHA256: executable, inputWidth: input.width, inputHeight: input.height, candidate: candidate, createdAt: Date(), operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString, runtime: runtime, sourceSHA256: sha(data), markedSHA256: sha(output), expectedID: id, warmups: 3, samples: samples, screenshots: []))
                }.value
                if let data = result.0 { marked = data }; report = result.1
                let correct = result.1.samples.filter { $0.recovery.decodedIDs == [result.1.expectedID] }.count
                status = "\(result.1.candidate): \(correct)/20 JPEG recoveries. \(result.1.screenshots.count) screenshot tests recorded. Export JSON for all attempts. JPEG p95: \(Int(result.1.embedP95Milliseconds)) ms; extraction p95: \(Int(result.1.extractP95Milliseconds)) ms."
                if let last = result.1.screenshots.last { status += " Latest screenshot: " + (last.recovery.decodedIDs == [result.1.expectedID] ? "matching ID." : last.recovery.decodedIDs.isEmpty ? "no ID recovered." : "different or conflicting IDs.") }
            } catch ResearchError.insufficientCapacity where tiled {
                status = version == 3 ? "Failed: v3 needs at least a 132×120-pixel tile after normalization." : "Failed: v2 needs at least a 160×144-pixel tile after normalization."
            } catch { status = "Failed: \(error.localizedDescription)" }
            busy = false
        }
    }
}
@main struct ProofCamResearchApp: App { var body: some Scene { WindowGroup { CameraRootView() } } }
struct ResearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = Model()
    @StateObject private var provenance = CaptureProvenance()
    @State private var importingEnrollment = false
    @State private var importingAppAttest = false
    @State private var attestedCapture: PendingCapture?
    @State private var importing = false
    @State private var screenshot = false
    @State private var exporting = false
    @State private var attested = false
    @State private var rectangle = ""
    @State private var filename = "report.json"
    @State private var document = ExportFile(data: Data())
    @State private var exportType: UTType = .json
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Research lab").font(ProofCamType.display(26, relativeTo: .title)).accessibilityAddTraits(.isHeader)
                        Text("Tools for testing how well an invisible watermark survives re-saving and screenshots. Everything runs on this iPhone. Results are measurements, not proof that a photo is authentic, came from a camera, or is free of AI.")
                            .font(.subheadline).foregroundStyle(ProofCamTheme.secondary)
                    }.padding(.vertical, 6)
                }
                benchmarkSection
                reliabilitySection
                screenshotSection
                exportSection
                captureSection
            }
            .scrollContentBackground(.hidden).background(ProofCamTheme.background)
            .foregroundStyle(ProofCamTheme.text).tint(ProofCamTheme.accent)
            .navigationTitle("Lab").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: (importingEnrollment || importingAppAttest) ? [.data] : [.jpeg,.png]) { result in
            switch result { case .success(let url):
                if importingAppAttest {
                    let capture = attestedCapture
                    Task {
                        do { export(try await provenance.appAttestExport(from: url, capture: capture), name: capture == nil ? "app-attest-enrollment.cbor" : "app-attest-registration.cbor", type: .data) }
                        catch { provenance.status = "App Attest evidence was not prepared. Check provisioning, Apple service availability and the challenge. No basic-registration fallback was attempted." }
                    }
                } else if importingEnrollment {
                    do { export(try provenance.enrollment(from: url), name: "proofcam-enrollment.cbor", type: .data) }
                    catch { provenance.status = "Enrollment preparation failed. Check the invitation and unlock the physical iPhone." }
                } else { model.load(url, screenshot: screenshot, rectangle: rectangle, attested: attested) }
            case .failure(let error): model.status = error.localizedDescription }
        }
        .fullScreenCover(isPresented: $provenance.showCamera) {
            ProofCamCamera(completed: { provenance.captured($0) }, cancelled: { provenance.showCamera = false })
                .ignoresSafeArea()
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: exportType, defaultFilename: filename) { result in
            if case .failure(let error) = result { model.status = error.localizedDescription }
        }
    }

    private var benchmarkSection: some View {
        Section {
            Text(model.status).font(.subheadline)
            Picker("Watermark version", selection: $model.candidateVersion) { Text("v1").tag(1); Text("v2").tag(2); Text("v3").tag(3) }
                .pickerStyle(.segmented).disabled(model.busy)
            if model.busy { ProgressView("Running locally…") }
            Button("Choose image and run 20 samples") { importingAppAttest = false; importingEnrollment = false; screenshot = false; rectangle = ""; attested = false; importing = true }
                .disabled(model.busy)
            if let data = model.marked, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("Marked JPEG result")
            }
            Button("Save marked JPEG") { export(model.marked, name: "proofcam-marked.jpg", type: .jpeg) }.disabled(model.marked == nil || model.busy)
        } header: { Text("Watermark benchmark") } footer: {
            Text("Applies to the next source. v1 is fastest, v2 favors stronger marking, and v3 (the default) uses smaller tiles with adaptive strength. v2 and v3 search edited images and take longer.")
        }
    }

    private var reliabilitySection: some View {
        Section {
            ForEach(WatermarkEvidence.rows) { EvidenceRow(row: $0) }
        } header: { Text("How reliable is the watermark check?") } footer: {
            Text("Counts come from the adaptive v3 simulation in benchmark/reports (step06-ios-adaptive-validation.json), run on a Linux computer, not an iPhone. Ranges are 95% Wilson score intervals. They describe only whether the watermark can be found again after edits. They say nothing about whether a photo is real or AI-generated.")
        }
    }

    private var screenshotSection: some View {
        Section {
            TextField("Optional crop: left,top,right,bottom", text: $rectangle).textInputAutocapitalization(.never).autocorrectionDisabled()
            Toggle("I captured this using iOS screenshot", isOn: $attested)
            Button("Import screenshot") { importingAppAttest = false; importingEnrollment = false; screenshot = true; importing = true }
                .disabled(model.report == nil || model.busy)
        } header: { Text("Screenshot recovery") } footer: {
            Text(model.report == nil ? "Run a benchmark first. Then save the marked JPEG, open it, take an iOS screenshot, and import the screenshot here." : "Save the marked JPEG, open it in a viewer, take an iOS screenshot, save it to Files, then import it here.")
        }
    }

    private var exportSection: some View {
        Section {
            Button("Export research JSON") {
                do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
                    export(try encoder.encode(model.report), name: "proofcam-report.json", type: .json)
                } catch { model.status = error.localizedDescription }
            }.disabled(model.report == nil || model.busy)
        } header: { Text("Export") } footer: {
            Text("A detected identifier is not proof that a photo is authentic. Optional App Attest contacts Apple; default research runs use no network services.")
        }
    }

    private var captureSection: some View {
        Section {
            Text(provenance.status).font(.subheadline)
            Button("Prepare device enrollment") { importingAppAttest = false; importingEnrollment = true; importing = true }
                .disabled(model.busy || provenance.busy)
            if AppAttestDeviceKey.enabled {
                Button("Export App Attest challenge request") {
                    do { export(try provenance.appAttestChallengeRequest(purpose: "attest"), name: "attest-challenge-request.cbor", type: .data) }
                    catch { provenance.status = "App Attest challenge preparation failed." }
                }.disabled(provenance.busy)
                Button("Import App Attest challenge JSON") { attestedCapture = nil; importingAppAttest = true; importing = true }.disabled(provenance.busy)
            } else {
                Text("App Attest is off in this build. Turning it on needs an eligible Apple developer team; basic signatures do not attest the app.").font(.footnote).foregroundStyle(ProofCamTheme.secondary)
            }
            Button("Take and sign a photo") { provenance.startCamera() }.disabled(model.busy || provenance.busy)
            if provenance.busy { ProgressView("Saving signed capture…") }
            Button("Refresh saved captures") { provenance.refresh() }.disabled(provenance.busy)
            ForEach(provenance.pending) { capture in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Capture \(capture.id.prefix(8))" + (capture.hasRequest ? " — registration pending" : " — incomplete, photo retained"))
                        .font(.subheadline.weight(.medium))
                    Button("Export capture JPEG") {
                        do { export(try Data(contentsOf: capture.jpeg), name: capture.id + ".jpg", type: .jpeg) }
                        catch { provenance.status = "Unable to read the saved photo." }
                    }
                    if AppAttestDeviceKey.enabled {
                        Button("Export registration challenge request") {
                            do { export(try provenance.appAttestChallengeRequest(purpose: "register"), name: "registration-challenge-request.cbor", type: .data) }
                            catch { provenance.status = "Registration challenge preparation failed." }
                        }.disabled(provenance.busy)
                        Button("Import registration challenge JSON") { attestedCapture = capture; importingAppAttest = true; importing = true }.disabled(provenance.busy)
                    }
                    if capture.hasRequest {
                        Button("Export signed request") {
                            do { export(try Data(contentsOf: capture.request), name: capture.id + ".cbor", type: .data) }
                            catch { provenance.status = "Unable to read the saved request." }
                        }
                    }
                }.buttonStyle(.borderless).padding(.vertical, 4)
            }
            ForEach(provenance.appAttestExports, id: \.self) { saved in
                Button("Re-export " + saved.lastPathComponent) {
                    do { export(try Data(contentsOf: saved), name: saved.lastPathComponent, type: .data) }
                    catch { provenance.status = "Saved App Attest export is unavailable." }
                }.disabled(provenance.busy)
            }
        } header: { Text("Signing and registration (development)") } footer: {
            Text("Select the private invitation file from your local server, then save the signed enrollment request. Keep both files private. Device signatures bind exported bytes; registration and independent verification run on your Mac. This does not certify camera origin or absence of AI.")
        }
    }

    private func export(_ data: Data?, name: String, type: UTType) { guard let data else { return }; document = ExportFile(data: data); filename = name; exportType = type; exporting = true }
}

/// The simulation counts behind the reliability ranges. Each row says what its trials really were,
/// because an interval is only as honest as the independence of those trials.
private struct WatermarkEvidence {
    struct Row: Identifiable {
        let id: Int
        let title: String
        let successes: Int
        let trials: Int
        let outcome: String
        let caveat: String
    }
    static let rows = [
        Row(id: 0, title: "Marked photos recovered, per source photo", successes: 5, trials: 5, outcome: "recovered",
            caveat: "Only 5 source photos, so this range is wide. It is the most cautious of the three."),
        Row(id: 1, title: "Marked copies recovered", successes: 125, trials: 125, outcome: "recovered",
            caveat: "These are 25 edits of the same 5 photos, so they are not independent trials. Treat this range as optimistic."),
        Row(id: 2, title: "Unmarked images wrongly detected", successes: 0, trials: 100, outcome: "wrongly detected",
            caveat: "Synthetic noise images, not real photographs. This is not a real-photo false-positive study.")
    ]
}

private struct EvidenceRow: View {
    let row: WatermarkEvidence.Row
    private var range: String {
        guard let interval = ProportionInterval(successes: row.successes, trials: row.trials) else { return "No range" }
        return String(format: "%.1f%% to %.1f%%", interval.lower * 100, interval.upper * 100)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title).font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Text("\(row.successes) of \(row.trials)").font(.system(.footnote, design: .monospaced)).foregroundStyle(ProofCamTheme.secondary)
            }
            Text("95% range: \(range)").font(.subheadline).foregroundStyle(ProofCamTheme.accent)
            Text(row.caveat).font(.footnote).foregroundStyle(ProofCamTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title). \(row.successes) of \(row.trials) \(row.outcome). 95 percent range \(range). \(row.caveat)")
    }
}
