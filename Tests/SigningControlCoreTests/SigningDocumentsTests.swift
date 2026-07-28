import Foundation
import XCTest
@testable import SigningControlCore

final class SigningDocumentsTests: XCTestCase {
    func testRequestUsesCanonicalIOSHardenSchema() throws {
        let data = Data(#"{"algorithm":"Ed25519","build_id":"42","bundle_identifier":"com.example.App","created_at_epoch_seconds":900,"key_id":"skb-integrity-fixture","manifest_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","schema_version":1}"#.utf8)

        let request = try IntegritySigningRequest.decode(data)

        XCTAssertEqual(request.keyID, "skb-integrity-fixture")
        XCTAssertEqual(try request.canonicalData(), data)
    }

    func testRequestRejectsUnknownField() {
        let data = Data(#"{"algorithm":"Ed25519","build_id":"42","bundle_identifier":"com.example.App","created_at_epoch_seconds":900,"extra":true,"key_id":"skb-integrity-fixture","manifest_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","schema_version":1}"#.utf8)

        XCTAssertThrowsError(try IntegritySigningRequest.decode(data))
    }

    func testRequestRejectsInvalidProtocolValues() {
        let invalidRequests = [
            #"{"algorithm":"RSA","build_id":"42","bundle_identifier":"com.example.App","created_at_epoch_seconds":900,"key_id":"skb-integrity-fixture","manifest_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","schema_version":1}"#,
            #"{"algorithm":"Ed25519","build_id":"../42","bundle_identifier":"com.example.App","created_at_epoch_seconds":900,"key_id":"skb-integrity-fixture","manifest_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","schema_version":1}"#,
            #"{"algorithm":"Ed25519","build_id":"42","bundle_identifier":"not-dotted","created_at_epoch_seconds":900,"key_id":"skb-integrity-fixture","manifest_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","schema_version":1}"#,
            #"{"algorithm":"Ed25519","build_id":"42","bundle_identifier":"com.example.App","created_at_epoch_seconds":-1,"key_id":"skb-integrity-fixture","manifest_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","schema_version":1}"#
        ]

        for request in invalidRequests {
            XCTAssertThrowsError(try IntegritySigningRequest.decode(Data(request.utf8)))
        }
    }
}
