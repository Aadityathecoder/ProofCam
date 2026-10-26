#if canImport(CryptoKit)
import Foundation
import CryptoKit

/// A signed ProofCam manifest stored inside a JPEG comment segment.
/// The digest excludes this one segment, avoiding a self-referential file hash
/// while still binding every byte of the JPEG image itself.
public enum EmbeddedProof {
    public enum Error: Swift.Error { case notJPEG, malformed, tooLarge, duplicate }
    private static let magic = Data("ProofCam\u{0}v1\u{0}".utf8)

    public static func embed(_ proof: Data, in jpeg: Data) throws -> Data {
        guard jpeg.count >= 2, jpeg[0] == 0xff, jpeg[1] == 0xd8 else { throw Error.notJPEG }
        guard proof.count + magic.count <= 65_531 else { throw Error.tooLarge }
        guard try extract(from: jpeg) == nil else { throw Error.duplicate }
        let payload = magic + proof
        let length = UInt16(payload.count + 2)
        var output = Data([0xff, 0xd8, 0xff, 0xfe, UInt8(length >> 8), UInt8(length & 0xff)])
        output.append(payload)
        output.append(jpeg.dropFirst(2))
        return output
    }

    public static func extract(from jpeg: Data) throws -> Data? { try scan(jpeg).proof }
    public static func prooflessJPEG(_ jpeg: Data) throws -> Data { try scan(jpeg).stripped }

    private static func scan(_ jpeg: Data) throws -> (proof: Data?, stripped: Data) {
        guard jpeg.count >= 2, jpeg[0] == 0xff, jpeg[1] == 0xd8 else { throw Error.notJPEG }
        var offset = 2
        var proof: Data?
        var stripped = Data(jpeg.prefix(2))
        while offset < jpeg.count {
            guard jpeg[offset] == 0xff else { throw Error.malformed }
            let markerStart = offset
            while offset < jpeg.count, jpeg[offset] == 0xff { offset += 1 }
            guard offset < jpeg.count else { throw Error.malformed }
            let marker = jpeg[offset]
            offset += 1
            if marker == 0xda {
                stripped.append(jpeg[markerStart...])
                return (proof, stripped)
            }
            if marker == 0xd9 {
                stripped.append(jpeg[markerStart..<offset])
                guard offset == jpeg.count else { throw Error.malformed }
                return (proof, stripped)
            }
            if marker == 0x01 || (0xd0...0xd7).contains(marker) {
                stripped.append(jpeg[markerStart..<offset])
                continue
            }
            guard offset + 2 <= jpeg.count else { throw Error.malformed }
            let length = Int(jpeg[offset]) << 8 | Int(jpeg[offset + 1])
            guard length >= 2, offset + length <= jpeg.count else { throw Error.malformed }
            let segmentEnd = offset + length
            let payload = Data(jpeg[(offset + 2)..<segmentEnd])
            if marker == 0xfe, payload.starts(with: magic) {
                guard proof == nil else { throw Error.duplicate }
                proof = Data(payload.dropFirst(magic.count))
            } else {
                stripped.append(jpeg[markerStart..<segmentEnd])
            }
            offset = segmentEnd
        }
        throw Error.malformed
    }
}

/// A portable, self-signed receipt. Key trust and sensor origin are separate claims.
public struct LocalCaptureReceipt: Codable, Sendable {
    public let id: String
    public let session: String
    public let fileSHA256: String
    public let publicKey: Data
    public let signature: Data

    public init(id: String, session: String, fileSHA256: String, publicKey: Data, signature: Data) {
        self.id = id; self.session = session; self.fileSHA256 = fileSHA256
        self.publicKey = publicKey; self.signature = signature
    }
    public var payload: Data {
        get throws { try ProvenanceWire.offlineCameraRequest(id: id, fileSHA256: fileSHA256, session: session) }
    }
    public var keyID: String { SHA256.hash(data: publicKey).map { String(format: "%02x", $0) }.joined() }
    public var request: Data {
        get throws { try ProvenanceWire.envelope(payload: payload, keyID: keyID, signature: signature) }
    }
    public func verifies(_ file: Data, request storedRequest: Data? = nil) throws -> Bool {
        let proofless = (try? EmbeddedProof.prooflessJPEG(file)) ?? file
        let digest = SHA256.hash(data: proofless).map { String(format: "%02x", $0) }.joined()
        guard digest == fileSHA256 else { return false }
        let key = try P256.Signing.PublicKey(x963Representation: publicKey)
        let signed = try P256.Signing.ECDSASignature(rawRepresentation: signature)
        let input = try ProvenanceWire.signatureInput(payload: payload, keyID: keyID, purpose: "register")
        guard key.isValidSignature(signed, for: input) else { return false }
        if let storedRequest { return try storedRequest == request }
        return true
    }
}
#endif
