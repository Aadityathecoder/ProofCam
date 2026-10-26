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
    private var data: Data?
    private var suppliedReceipt: LocalCaptureReceipt?

    func load(_ bytes: Data, captures: [PendingCapture]) {
        data = nil; image = nil; verified = false
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
        verified = false
        guard let data else { title = "Signature ready"; detail = "Now choose the photo that belongs to this signature."; return }
        checking = true; defer { checking = false }
        if let suppliedReceipt {
            do {
                guard try suppliedReceipt.verifies(data) else { fail("The photo does not match this signature. It may have been edited or re-encoded."); return }
                success(local: false)
            } catch { fail("The signature is invalid or unsupported.") }
            return
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        for capture in captures where capture.hasRequest {
            guard let bytes = try? Data(contentsOf: capture.receipt), bytes.count <= 4096,
                  let receipt = try? JSONDecoder().decode(LocalCaptureReceipt.self, from: bytes), receipt.fileSHA256 == digest else { continue }
            do {
                guard try receipt.verifies(data, request: Data(contentsOf: capture.request)) else { continue }
                success(local: true); return
            } catch { continue }
        }
        title = "No matching signature found"
        detail = "No saved signature on this iPhone matches these exact bytes. Import the photo’s signature, or choose the original file if a shared copy was changed."
    }
    func fail(_ message: String) { verified = false; checking = false; title = "Unable to verify"; detail = message }
    private func success(local: Bool) {
        verified = true; title = "Signature verified"
        detail = local ? "This photo exactly matches a signed capture saved in ProofCam on this iPhone." : "This photo exactly matches the supplied signature. The signing key’s owner has not been independently verified."
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
                VStack(spacing: 26) {
                    HStack { Text("PROOFCAM").font(.system(size: 11, weight: .semibold)).tracking(3).foregroundStyle(.secondary); Spacer() }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("A photo.\nIts signature.").font(.system(size: 42, weight: .semibold, design: .rounded)).tracking(-1.5)
                        Text("See whether a photo matches its signed original.").font(.body).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if let image = model.image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 300).clipShape(RoundedRectangle(cornerRadius: 18))
                    } else {
                        RoundedRectangle(cornerRadius: 22).fill(.white.opacity(0.035)).frame(height: 210)
                            .overlay { Image(systemName: "checkmark.shield").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(.yellow) }
                            .overlay { RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.08)) }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Label(model.title, systemImage: model.verified ? "checkmark.seal.fill" : "info.circle")
                            .font(.headline).foregroundStyle(model.verified ? .green : .white)
                        Text(model.detail).font(.subheadline).foregroundStyle(.secondary)
                        if model.verified {
                            Text("A valid signature does not prove camera origin or that the photo is free of AI.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 12) {
                        PhotosPicker(selection: $selected, matching: .images, preferredItemEncoding: .current) {
                            Label("Choose photo", systemImage: "photo").frame(maxWidth: .infinity).padding(.vertical, 8)
                        }.buttonStyle(.borderedProminent).tint(.yellow).foregroundStyle(.black)
                        Button { signatureImport = false; importing = true } label: {
                            Label("Choose original from Files", systemImage: "folder").frame(maxWidth: .infinity).padding(.vertical, 8)
                        }.buttonStyle(.bordered)
                        Button("Import signature") { signatureImport = true; importing = true }.font(.subheadline).padding(.top, 4)
                        if model.hasImportedReceipt {
                            Button("Remove imported signature") { model.clearReceipt(captures: provenance.pending) }.font(.caption)
                        }
                    }.disabled(model.checking)
                    Label("Checked on your device", systemImage: "lock")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(26)
            }.background(Color(white: 0.035)).navigationTitle("Verify").navigationBarTitleDisplayMode(.inline)
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
