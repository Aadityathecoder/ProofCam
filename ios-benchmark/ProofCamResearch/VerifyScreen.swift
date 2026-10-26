import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import CryptoKit

@MainActor final class PhotoVerification: ObservableObject {
    @Published var image: UIImage?
    @Published var title = "Check a photo’s signature"
    @Published var detail = "Choose a photo captured with ProofCam. Verification happens on your iPhone."
    @Published var verified = false
    @Published var checking = false
    @Published var hasImportedReceipt = false
    @Published var proofIsEmbedded = false
    private var data: Data?
    private var suppliedReceipt: LocalCaptureReceipt?

    func load(_ bytes: Data, captures: [PendingCapture]) {
        data = nil; image = nil; verified = false; proofIsEmbedded = false
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
        else { title = "Check a photo’s signature"; detail = "Choose a photo captured with ProofCam. Verification happens on your iPhone." }
    }
    func check(_ captures: [PendingCapture]) {
        verified = false; proofIsEmbedded = false
        guard let data else { title = "Signature ready"; detail = "Now choose the photo that belongs to this signature."; return }
        checking = true; defer { checking = false }
        if let embedded = try? EmbeddedProof.extract(from: data),
           embedded.count <= 4096,
           let receipt = try? JSONDecoder().decode(LocalCaptureReceipt.self, from: embedded) {
            do {
                guard try receipt.verifies(data) else {
                    fail("The embedded proof is intact, but the image bytes no longer match it."); return
                }
                proofIsEmbedded = true
                success(local: false, embedded: true)
            } catch { fail("The proof embedded in this photo is invalid or unsupported.") }
            return
        }
        if let suppliedReceipt {
            do {
                guard try suppliedReceipt.verifies(data) else { fail("The photo does not match this signature. It may have been edited or re-encoded."); return }
                success(local: false, embedded: false)
            } catch { fail("The signature is invalid or unsupported.") }
            return
        }
        let comparable = (try? EmbeddedProof.prooflessJPEG(data)) ?? data
        let digest = SHA256.hash(data: comparable).map { String(format: "%02x", $0) }.joined()
        for capture in captures where capture.hasRequest {
            guard let bytes = try? Data(contentsOf: capture.receipt), bytes.count <= 4096,
                  let receipt = try? JSONDecoder().decode(LocalCaptureReceipt.self, from: bytes), receipt.fileSHA256 == digest else { continue }
            do {
                guard try receipt.verifies(data, request: Data(contentsOf: capture.request)) else { continue }
                success(local: true, embedded: false); return
            } catch { continue }
        }
        title = "No matching signature found"
        detail = "No saved signature on this iPhone matches these exact bytes. Import the photo’s signature, or choose the original file if a shared copy was changed."
    }
    func fail(_ message: String) { verified = false; checking = false; title = "Unable to verify"; detail = message }
    private func success(local: Bool, embedded: Bool) {
        verified = true; title = "Signature verified"
        if embedded {
            detail = "The cryptographic proof carried inside this JPEG matches its image bytes. The signing key’s owner has not been independently verified."
        } else {
            detail = local ? "This photo exactly matches a signed capture saved in ProofCam on this iPhone." : "This photo exactly matches the supplied signature. The signing key’s owner has not been independently verified."
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
    @StateObject private var model = PhotoVerification()
    @State private var selected: PhotosPickerItem?
    @State private var importing = false
    @State private var signatureImport = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack { ProofCamMark(); Spacer(); Text("FIELD NOTES  /  02").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary) }
                    VStack(alignment: .leading, spacing: 6) {
                        WorkshopEyebrow(text: "Check the record")
                        Text("Does it hold up?")
                            .font(.system(.largeTitle, design: .serif).weight(.bold))
                            .tracking(-0.8)
                        Text("Choose an original. Its signed proof is checked privately on this iPhone.")
                            .font(.body).foregroundStyle(ProofCamTheme.ink.opacity(0.72)).fixedSize(horizontal: false, vertical: true)
                    }
                    if let image = model.image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 310)
                            .background(Color.black).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(ProofCamTheme.paper).frame(height: 200)
                            .overlay {
                                VStack(spacing: 4) {
                                    ProofWorkshopIllustration(compact: true).frame(width: 175, height: 145)
                                    Text("A photo, filed with care").font(.system(size: 13, weight: .medium, design: .serif)).foregroundStyle(ProofCamTheme.ink.opacity(0.7))
                                }
                            }
                            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(ProofCamTheme.line) }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            let failed = model.title == "Unable to verify" || model.title == "No matching signature found"
                            Image(systemName: model.verified ? "checkmark.circle.fill" : failed ? "exclamationmark.triangle.fill" : "info.circle.fill")
                                .font(.title2).foregroundStyle(model.verified ? ProofCamTheme.success : failed ? ProofCamTheme.clay : ProofCamTheme.accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(model.title).font(.headline).foregroundStyle(ProofCamTheme.ink)
                                Text(model.detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if model.proofIsEmbedded {
                            Label("Embedded proof", systemImage: "shippingbox.fill")
                                .font(.caption.weight(.semibold)).foregroundStyle(ProofCamTheme.success)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(ProofCamTheme.success.opacity(0.1), in: Capsule())
                        }
                        if model.verified {
                            Divider()
                            Text("This confirms integrity, not whether the pictured event is true.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                        .background(ProofCamTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(ProofCamTheme.line) }
                    VStack(spacing: 12) {
                        PhotosPicker(selection: $selected, matching: .images, preferredItemEncoding: .current) {
                            Label("Choose from Photos", systemImage: "photo")
                                .font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 54)
                                .foregroundStyle(.white)
                                .background(ProofCamTheme.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }.buttonStyle(.plain)
                        Button { signatureImport = false; importing = true } label: {
                            Label("Choose from Files", systemImage: "folder")
                                .font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 54)
                                .foregroundStyle(ProofCamTheme.ink)
                                .background(ProofCamTheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ProofCamTheme.line) }
                        }.buttonStyle(.plain)
                        Button("Use a separate proof file") { signatureImport = true; importing = true }.font(.subheadline).padding(.top, 2)
                        if model.hasImportedReceipt {
                            Button("Remove separate proof") { model.clearReceipt(captures: provenance.pending) }.font(.caption)
                        }
                    }.disabled(model.checking)
                    HStack(spacing: 18) {
                        Label("On-device", systemImage: "iphone")
                        Label("No upload", systemImage: "icloud.slash")
                        Label("SHA-256", systemImage: "number")
                    }.font(.caption2.weight(.medium)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }.padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 32)
            }.background(ProofCamTheme.canvas).navigationBarHidden(true)
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
}
