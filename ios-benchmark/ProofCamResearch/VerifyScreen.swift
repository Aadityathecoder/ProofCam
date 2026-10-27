import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import CryptoKit

@MainActor final class PhotoVerification: ObservableObject {
    enum Outcome: Equatable {
        case idle, receiptReady, verified(ProofSource), mismatch, noProof, failed
    }
    enum ProofSource: Equatable { case embedded, local, supplied }

    @Published var image: UIImage?
    @Published var title = "Check a photo’s signature"
    @Published var detail = "Choose a photo captured with ProofCam. Verification happens on your iPhone."
    @Published var verified = false
    @Published var checking = false
    @Published var hasImportedReceipt = false
    @Published var proofIsEmbedded = false
    @Published var outcome: Outcome = .idle
    /// SHA-256 recorded in the signed proof, when one was found.
    @Published var expectedDigest: String?
    /// SHA-256 of the chosen file's image bytes (proof container excluded).
    @Published var fileDigest: String?
    private var data: Data?
    private var suppliedReceipt: LocalCaptureReceipt?

    func load(_ bytes: Data, captures: [PendingCapture]) {
        data = nil; image = nil; verified = false; proofIsEmbedded = false; expectedDigest = nil; fileDigest = nil
        guard bytes.count <= 25 * 1024 * 1024 else { fail("This file is too large. Choose a photo smaller than 25 MB."); return }
        do { _ = try AppleImageCodec.decode(bytes) }
        catch { fail("Choose an opaque JPEG or PNG photo."); return }
        data = bytes; image = UIImage(data: bytes)
        check(captures)
    }
    func importReceipt(_ bytes: Data, captures: [PendingCapture]) {
        do {
            guard bytes.count <= 4096 else { throw ProvenanceWire.Invalid.signature }
            suppliedReceipt = try JSONDecoder().decode(LocalCaptureReceipt.self, from: bytes)
            hasImportedReceipt = true
            check(captures)
        } catch { suppliedReceipt = nil; hasImportedReceipt = false; fail("This signature file could not be read. Choose the JSON signature exported by ProofCam.") }
    }
    func clearReceipt(captures: [PendingCapture]) {
        suppliedReceipt = nil; hasImportedReceipt = false
        if data != nil { check(captures) }
        else { reset() }
    }
    func reset() {
        data = nil; image = nil; verified = false; proofIsEmbedded = false; expectedDigest = nil; fileDigest = nil
        title = "Check a photo’s signature"; detail = "Choose a photo captured with ProofCam. Verification happens on your iPhone."
        outcome = hasImportedReceipt ? .receiptReady : .idle
    }
    func check(_ captures: [PendingCapture]) {
        verified = false; proofIsEmbedded = false; expectedDigest = nil
        guard let data else { title = "Signature ready"; detail = "Now choose the photo that belongs to this signature."; outcome = .receiptReady; return }
        checking = true; defer { checking = false }
        let comparable = (try? EmbeddedProof.prooflessJPEG(data)) ?? data
        let digest = SHA256.hash(data: comparable).map { String(format: "%02x", $0) }.joined()
        fileDigest = digest
        if let embedded = try? EmbeddedProof.extract(from: data),
           embedded.count <= 4096,
           let receipt = try? JSONDecoder().decode(LocalCaptureReceipt.self, from: embedded) {
            expectedDigest = receipt.fileSHA256
            do {
                guard try receipt.verifies(data) else {
                    fail("The embedded proof is intact, but the image bytes no longer match it.", mismatch: true); return
                }
                proofIsEmbedded = true
                success(.embedded)
            } catch { fail("The proof embedded in this photo is invalid or unsupported.") }
            return
        }
        if let suppliedReceipt {
            expectedDigest = suppliedReceipt.fileSHA256
            do {
                guard try suppliedReceipt.verifies(data) else { fail("The photo does not match this signature. It may have been edited or re-encoded.", mismatch: true); return }
                success(.supplied)
            } catch { fail("The signature is invalid or unsupported.") }
            return
        }
        for capture in captures where capture.hasRequest {
            guard let bytes = try? Data(contentsOf: capture.receipt), bytes.count <= 4096,
                  let receipt = try? JSONDecoder().decode(LocalCaptureReceipt.self, from: bytes), receipt.fileSHA256 == digest else { continue }
            do {
                guard try receipt.verifies(data, request: Data(contentsOf: capture.request)) else { continue }
                expectedDigest = receipt.fileSHA256
                success(.local); return
            } catch { continue }
        }
        title = "No matching signature found"
        detail = "No saved signature on this iPhone matches these exact bytes. Import the photo’s signature, or choose the original file if a shared copy was changed."
        outcome = .noProof
    }
    func fail(_ message: String, mismatch: Bool = false) {
        verified = false; checking = false; title = "Unable to verify"; detail = message
        outcome = mismatch ? .mismatch : .failed
    }
    private func success(_ source: ProofSource) {
        verified = true; title = "Signature verified"; outcome = .verified(source)
        switch source {
        case .embedded: detail = "The cryptographic proof carried inside this JPEG matches its image bytes. The signing key’s owner has not been independently verified."
        case .local: detail = "This photo exactly matches a signed capture saved in ProofCam on this iPhone."
        case .supplied: detail = "This photo exactly matches the supplied signature. The signing key’s owner has not been independently verified."
        }
    }
    static func read(_ url: URL, limit: Int) throws -> Data {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        return try ResearchUtilities.readBounded(limit: limit) { try file.read(upToCount: $0) ?? Data() }
    }
}

struct VerifyScreen: View {
    @ObservedObject var provenance: CaptureProvenance
    @ObservedObject var model: PhotoVerification
    @State private var selected: PhotosPickerItem?
    @State private var importing = false
    @State private var signatureImport = false
    @AppStorage("proofcam.shutterHaptics") private var haptics = true
    private var alignmentPhase: RegistrationAlignment.Phase {
        if model.checking { return .searching }
        switch model.outcome {
        case .verified: return .aligned
        case .mismatch: return .offset
        default: return .idle
        }
    }
    private var differingCount: Int? {
        guard let file = model.fileDigest, let expected = model.expectedDigest else { return nil }
        return zip(file, expected).filter { $0 != $1 }.count + abs(file.count - expected.count)
    }
    private var showingResult: Bool {
        switch model.outcome { case .idle, .receiptReady: return model.checking; default: return true }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                if showingResult { result } else { chooser }
            }
            .background(ProofCamTheme.background).navigationBarHidden(true)
            .animation(.easeOut(duration: 0.25), value: model.outcome)
        }
        .sensoryFeedback(trigger: model.outcome) { _, new in
            guard haptics else { return nil }
            switch new {
            case .verified: return .success
            case .mismatch, .failed: return .warning
            default: return nil
            }
        }
        .onChange(of: selected) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw ResearchError.invalidDimensions }
                    model.load(data, captures: provenance.pending)
                } catch { model.fail("The photo could not be opened. Try choosing its original file.") }
                selected = nil
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: signatureImport ? [.json] : [.jpeg, .png]) { result in
            do {
                let data = try PhotoVerification.read(result.get(), limit: signatureImport ? 4096 : 25*1024*1024)
                if signatureImport { model.importReceipt(data, captures: provenance.pending) }
                else { model.load(data, captures: provenance.pending) }
            } catch { if (error as NSError).code != NSUserCancelledError { model.fail("The file could not be opened. Please try again.") } }
        }
    }

    // MARK: Choosing a photo

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Verify a photo").font(ProofCamType.display(32, relativeTo: .largeTitle)).padding(.bottom, 8)
            Text("Choose an original. Its signed proof is checked privately on this iPhone.")
                .font(.body).foregroundStyle(ProofCamTheme.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)
            VStack(spacing: 0) {
                PhotosPicker(selection: $selected, matching: .images, preferredItemEncoding: .current) {
                    SourceRow(symbol: "photo", title: "Photos", subtitle: "Pick from your library")
                }.buttonStyle(.plain)
                Divider().overlay(ProofCamTheme.border).padding(.leading, 60)
                Button { signatureImport = false; importing = true } label: {
                    SourceRow(symbol: "folder", title: "Files", subtitle: "The original JPEG or PNG")
                }.buttonStyle(.plain)
                Divider().overlay(ProofCamTheme.border).padding(.leading, 60)
                Button { signatureImport = true; importing = true } label: {
                    SourceRow(symbol: "doc.text", title: "Separate proof file",
                              subtitle: model.hasImportedReceipt ? "Signature ready. Choose its photo next." : "For copies whose embedded proof was removed")
                }.buttonStyle(.plain)
            }
            .background(ProofCamTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ProofCamTheme.border) }
            .disabled(model.checking)
            Text("Images from anywhere can be checked, including ones made with AI. They only match if they still carry their own ProofCam proof.")
                .font(.footnote).foregroundStyle(ProofCamTheme.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12).padding(.horizontal, 4)
            if model.hasImportedReceipt {
                Button("Remove separate proof") { model.clearReceipt(captures: provenance.pending) }
                    .font(.footnote).tint(ProofCamTheme.accent).padding(.top, 12).padding(.leading, 4)
            }
        }
        .foregroundStyle(ProofCamTheme.text)
        .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 40)
    }

    // MARK: Result

    private var tone: Color {
        switch model.outcome {
        case .verified: return ProofCamTheme.success
        case .mismatch, .failed: return ProofCamTheme.warning
        default: return ProofCamTheme.secondary
        }
    }
    private var symbol: String {
        switch model.outcome {
        case .verified: return "checkmark.circle"
        case .mismatch, .failed: return "xmark.circle"
        default: return "minus.circle"
        }
    }
    private var headline: String {
        switch model.outcome {
        case .verified(.supplied): return "Matches the proof file."
        case .verified: return "Matches its proof."
        case .mismatch: return "Doesn’t match its proof."
        case .noProof: return "No proof found."
        default: return "Couldn’t check this file."
        }
    }
    private var records: [(String, String, Color)] {
        let text = ProofCamTheme.text
        switch model.outcome {
        case .verified(let source):
            let proof = source == .embedded ? "Embedded in JPEG" : source == .supplied ? "Separate JSON file" : "Saved on this iPhone"
            return [("Proof", proof, text), ("Signature", "Valid · P-256", ProofCamTheme.success),
                    ("Key owner", source == .local ? "This iPhone" : "Not independently verified", text), ("Checked", "On this iPhone", text)]
        case .mismatch:
            return [("Proof", model.hasImportedReceipt && !model.proofIsEmbedded ? "Separate JSON file" : "Embedded, intact", text),
                    ("Image bytes", "Changed after signing", ProofCamTheme.warning), ("Checked", "On this iPhone", text)]
        case .noProof:
            return [("Embedded proof", "None found", text), ("Saved signatures", "No match on this iPhone", text)]
        default: return []
        }
    }
    private var confirms: [String] {
        switch model.outcome {
        case .verified: return ["The image bytes are the ones that were signed.", "The signed proof is intact."]
        case .mismatch: return ["The file changed after it was signed. Ask the sender for the original file."]
        case .noProof: return ["This file carries no proof ProofCam can read, and no saved signature matches it."]
        default: return ["ProofCam couldn’t read this file or its proof."]
        }
    }
    private var doesNotConfirm: [String] {
        switch model.outcome {
        case .verified: return ["Whether the event happened as described.", "Who took the photo, or who owns the key.", "Whether the scene was staged or AI-generated."]
        case .mismatch: return ["What changed, who changed it, or why.", "Whether the change matters."]
        case .noProof: return ["Whether an imported image is a real photograph or AI-generated.", "That the photo is fake. Most photos weren’t taken with ProofCam."]
        default: return ["Anything about the photo’s content."]
        }
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                // A fixed-height clear frame keeps a fill-scaled photo from widening the page.
                Color.clear.frame(height: 300).frame(maxWidth: .infinity)
                    .overlay {
                        if let image = model.image {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            ProofCamTheme.surfaceMuted.overlay(Image(systemName: "photo").font(.largeTitle).foregroundStyle(ProofCamTheme.secondary))
                        }
                    }
                    .clipped().accessibilityHidden(true)
                    .overlay(alignment: .bottomTrailing) {
                        RegistrationAlignment(phase: alignmentPhase, size: 60)
                            .padding(10).background(ProofCamTheme.background.opacity(0.95), in: Circle())
                            .padding(14)
                    }
                Button { model.reset() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ProofCamTheme.onPrimary).frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.92), in: Circle())
                }.padding(12).accessibilityLabel("Back to Verify")
            }
            Rectangle().fill(model.checking ? ProofCamTheme.border : tone).frame(height: 3)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        if model.checking { ProgressView().controlSize(.small) } else { Image(systemName: symbol) }
                        Text(model.checking ? "Checking on this iPhone" : model.title)
                    }.font(.footnote.weight(.medium)).foregroundStyle(model.checking ? ProofCamTheme.secondary : tone)
                    Text(model.checking ? "Checking the photo against its proof" : headline)
                        .font(ProofCamType.display(28)).fixedSize(horizontal: false, vertical: true)
                    if !model.checking {
                        Text(model.detail).font(.body).foregroundStyle(ProofCamTheme.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.accessibilityElement(children: .combine)
                    .reveal(0)

                if !records.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(records, id: \.0) { RecordRow(label: $0.0, value: $0.1, tone: $0.2) }
                    }
                    .overlay(alignment: .top) { Rectangle().fill(ProofCamTheme.border).frame(height: 1) }
                    .padding(.top, 24)
                    .reveal(1)
                }

                if let fileDigest = model.fileDigest, let expected = model.expectedDigest {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SHA-256 fingerprints").font(.footnote.weight(.medium)).foregroundStyle(ProofCamTheme.secondary)
                        DigestLine(label: "In proof", digest: expected, reference: expected)
                        DigestLine(label: "This file", digest: fileDigest, reference: expected)
                        if let differingCount {
                            Text(differingCount == 0 ? "All \(expected.count) characters match." : "\(differingCount) of \(expected.count) characters differ.")
                                .font(.footnote.weight(.medium)).foregroundStyle(differingCount == 0 ? ProofCamTheme.success : ProofCamTheme.warning)
                                .padding(.top, 2)
                        }
                    }.padding(.top, 24).reveal(2)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("What this result means").font(ProofCamType.display(20, relativeTo: .headline)).padding(.bottom, 12)
                    Text("Confirms").font(.footnote.weight(.medium)).foregroundStyle(tone).padding(.bottom, 2)
                    ForEach(confirms, id: \.self) { MeaningLine(text: $0, muted: false) }
                    Text("Doesn’t confirm").font(.footnote.weight(.medium)).foregroundStyle(ProofCamTheme.secondary).padding(.top, 16).padding(.bottom, 2)
                    ForEach(doesNotConfirm, id: \.self) { MeaningLine(text: $0, muted: true) }
                }.padding(.top, 32).opacity(model.checking ? 0 : 1).reveal(3)

                Button("Check another photo") { model.reset() }.buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 32).disabled(model.checking).reveal(4)
            }
            .foregroundStyle(ProofCamTheme.text)
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 40)
        }
    }
}

private struct SourceRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(ProofCamTheme.accent)
                .frame(width: 32, height: 32).background(ProofCamTheme.brandPale, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).foregroundStyle(ProofCamTheme.text)
                Text(subtitle).font(.footnote).foregroundStyle(ProofCamTheme.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(ProofCamTheme.secondary)
        }
        .padding(.horizontal, 16).frame(minHeight: 64).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A full SHA-256 digest; characters that differ from the proof's digest are highlighted.
private struct DigestLine: View {
    let label: String
    let digest: String
    let reference: String
    private var styled: AttributedString {
        var out = AttributedString()
        let expected = Array(reference)
        for (index, char) in digest.enumerated() {
            var piece = AttributedString(String(char))
            let differs = index >= expected.count || expected[index] != char
            piece.foregroundColor = differs ? ProofCamTheme.warning : ProofCamTheme.text
            if index > 0 && index % 8 == 0 { out += AttributedString(" ") }
            out += piece
        }
        return out
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swept = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.footnote).foregroundStyle(ProofCamTheme.secondary).frame(width: 64, alignment: .leading)
            Text(styled).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .mask(alignment: .leading) {
                    Rectangle().scaleEffect(x: swept || reduceMotion ? 1 : 0.001, anchor: .leading)
                }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.8).delay(0.25)) { swept = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label == "This file" && digest != reference ? "This file's fingerprint differs from the proof" : "\(label) fingerprint")
    }
}

private struct MeaningLine: View {
    let text: String
    let muted: Bool
    var body: some View {
        Text(text).font(.subheadline).foregroundStyle(muted ? ProofCamTheme.secondary : ProofCamTheme.text)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(ProofCamTheme.border).frame(height: 1) }
    }
}
