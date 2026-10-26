#if canImport(CryptoKit)
import Foundation
import CryptoKit

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
        let digest = SHA256.hash(data: file).map { String(format: "%02x", $0) }.joined()
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
