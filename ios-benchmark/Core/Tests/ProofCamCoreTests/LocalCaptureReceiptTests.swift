#if canImport(CryptoKit)
import XCTest
import CryptoKit
@testable import ProofCamCore

final class LocalCaptureReceiptTests: XCTestCase {
    private let photo = Data("final JPEG bytes".utf8)
    private func makeReceipt(for bytes: Data? = nil) throws -> LocalCaptureReceipt {
        let signedPhoto = bytes ?? photo
        let key = P256.Signing.PrivateKey()
        let publicKey = key.publicKey.x963Representation
        let keyID = SHA256.hash(data: publicKey).map { String(format: "%02x", $0) }.joined()
        let digest = SHA256.hash(data: signedPhoto).map { String(format: "%02x", $0) }.joined()
        let id = String(repeating: "a", count: 32), session = String(repeating: "b", count: 32)
        let payload = try ProvenanceWire.offlineCameraRequest(id: id, fileSHA256: digest, session: session)
        let input = try ProvenanceWire.signatureInput(payload: payload, keyID: keyID, purpose: "register")
        return LocalCaptureReceipt(id: id, session: session, fileSHA256: digest, publicKey: publicKey, signature: try key.signature(for: input).rawRepresentation)
    }
    func testPortableReceiptAndRegistrationRequest() throws {
        let receipt = try makeReceipt()
        let restored = try JSONDecoder().decode(LocalCaptureReceipt.self, from: JSONEncoder().encode(receipt))
        XCTAssertTrue(try restored.verifies(photo, request: receipt.request))
        XCTAssertEqual(try restored.request, try receipt.request)
    }
    func testAlteredPhotoAndRequestFail() throws {
        let receipt = try makeReceipt()
        XCTAssertFalse(try receipt.verifies(photo + Data([0])))
        XCTAssertFalse(try receipt.verifies(photo, request: receipt.request + Data([0])))
    }
    func testReplacedKeyAndSignatureFail() throws {
        let receipt = try makeReceipt()
        let replaced = LocalCaptureReceipt(id: receipt.id, session: receipt.session, fileSHA256: receipt.fileSHA256,
                                          publicKey: P256.Signing.PrivateKey().publicKey.x963Representation, signature: receipt.signature)
        XCTAssertFalse(try replaced.verifies(photo))
        var signature = receipt.signature; signature[0] ^= 1
        let damaged = LocalCaptureReceipt(id: receipt.id, session: receipt.session, fileSHA256: receipt.fileSHA256,
                                         publicKey: receipt.publicKey, signature: signature)
        XCTAssertFalse(try damaged.verifies(photo))
    }
    func testIdentifiersAreSignedAndMalformedReceiptsFailClosed() throws {
        let receipt = try makeReceipt()
        let replaced = LocalCaptureReceipt(id: String(repeating: "c", count: 32), session: receipt.session, fileSHA256: receipt.fileSHA256,
                                          publicKey: receipt.publicKey, signature: receipt.signature)
        XCTAssertFalse(try replaced.verifies(photo))
        let malformed = LocalCaptureReceipt(id: receipt.id, session: receipt.session, fileSHA256: receipt.fileSHA256,
                                           publicKey: Data(), signature: Data())
        XCTAssertThrowsError(try malformed.verifies(photo))
    }
    func testReceiptCanTravelInsideJPEG() throws {
        let jpeg = Data([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x04, 0x01, 0x02,
                         0xff, 0xda, 0x00, 0x02, 0x11, 0x22, 0xff, 0xd9])
        let receipt = try makeReceipt(for: jpeg)
        let encoded = try JSONEncoder().encode(receipt)
        let carrying = try EmbeddedProof.embed(encoded, in: jpeg)
        XCTAssertEqual(try EmbeddedProof.prooflessJPEG(carrying), jpeg)
        XCTAssertEqual(try EmbeddedProof.extract(from: carrying), encoded)
        XCTAssertTrue(try receipt.verifies(carrying))
        XCTAssertThrowsError(try EmbeddedProof.embed(encoded, in: carrying))

        var tampered = carrying
        tampered[tampered.count - 3] ^= 1
        XCTAssertFalse(try receipt.verifies(tampered))
    }
}
#endif
