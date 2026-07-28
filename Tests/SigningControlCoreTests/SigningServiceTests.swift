import CryptoKit
import Foundation
import XCTest
@testable import SigningControlCore

final class SigningServiceTests: XCTestCase {
    private let seed = Data(repeating: 0x07, count: 32)
    private let requestTime: Int64 = 1_000

    func testSigningProducesVerifiableIOSHardenResponse() throws {
        let requestData = try requestData()
        let response = try SigningService().sign(
            requestData: requestData,
            policyData: try policyData(),
            privateKeyInput: seed,
            now: Date(timeIntervalSince1970: 1_100)
        )

        let publicKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed).publicKey
        let signature = try XCTUnwrap(Data(base64Encoded: response.signatureBase64))
        XCTAssertTrue(publicKey.isValidSignature(signature, for: requestData))
        XCTAssertEqual(response.schemaVersion, 1)
        XCTAssertEqual(response.keyID, "skb-integrity-fixture")
        XCTAssertEqual(response.requestSHA256, requestData.sha256Hex)
        XCTAssertEqual(response.publicKeySHA256, publicKey.rawRepresentation.sha256Hex)
        XCTAssertEqual(signature.count, 64)
        XCTAssertEqual(
            try IntegritySignatureResponse.decode(response.canonicalData()),
            response
        )
    }

    func testSigningAcceptsCanonicalBase64Seed() throws {
        let response = try SigningService().sign(
            requestData: try requestData(),
            policyData: try policyData(),
            privateKeyInput: Data(seed.base64EncodedString().utf8),
            now: Date(timeIntervalSince1970: 1_100)
        )

        XCTAssertEqual(response.keyID, "skb-integrity-fixture")
    }

    func testSigningRejectsWrongKeyID() throws {
        XCTAssertThrowsError(
            try SigningService().sign(
                requestData: try requestData(keyID: "skb-integrity-other"),
                policyData: try policyData(),
                privateKeyInput: seed,
                now: Date(timeIntervalSince1970: 1_100)
            )
        )
    }

    func testSigningRejectsWrongPublicKeyFingerprint() throws {
        XCTAssertThrowsError(
            try SigningService().sign(
                requestData: try requestData(),
                policyData: try policyData(publicKeySHA256: String(repeating: "a", count: 64)),
                privateKeyInput: seed,
                now: Date(timeIntervalSince1970: 1_100)
            )
        )
    }

    func testSigningRejectsExpiredRequest() throws {
        XCTAssertThrowsError(
            try SigningService().sign(
                requestData: try requestData(),
                policyData: try policyData(),
                privateKeyInput: seed,
                now: Date(timeIntervalSince1970: 1_601)
            )
        )
    }

    func testSigningRejectsFutureRequest() throws {
        XCTAssertThrowsError(
            try SigningService().sign(
                requestData: try requestData(),
                policyData: try policyData(),
                privateKeyInput: seed,
                now: Date(timeIntervalSince1970: 879)
            )
        )
    }

    func testSigningRejectsDisallowedBundleID() throws {
        XCTAssertThrowsError(
            try SigningService().sign(
                requestData: try requestData(bundleIdentifier: "com.attacker.App"),
                policyData: try policyData(),
                privateKeyInput: seed,
                now: Date(timeIntervalSince1970: 1_100)
            )
        )
    }

    func testSigningRejectsNonnumericBuildID() throws {
        XCTAssertThrowsError(
            try SigningService().sign(
                requestData: try requestData(buildID: "release-42"),
                policyData: try policyData(),
                privateKeyInput: seed,
                now: Date(timeIntervalSince1970: 1_100)
            )
        )
    }

    func testSigningRejectsNoncanonicalOrWrongLengthSeed() throws {
        let invalidSeeds = [
            Data("not-base64".utf8),
            Data(Data(repeating: 0x07, count: 31).base64EncodedString().utf8),
            Data((seed.base64EncodedString() + "\n").utf8)
        ]

        for invalidSeed in invalidSeeds {
            XCTAssertThrowsError(
                try SigningService().sign(
                    requestData: try requestData(),
                    policyData: try policyData(),
                    privateKeyInput: invalidSeed,
                    now: Date(timeIntervalSince1970: 1_100)
                )
            )
        }
    }

    func testPolicyRejectsUnsafeValuesAndUnknownFields() throws {
        let publicKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed).publicKey
        let fingerprint = publicKey.rawRepresentation.sha256Hex
        let invalidPolicies = [
            #"{"allowed_bundle_identifiers":[],"build_id_pattern":"^[0-9]+$","key_id":"skb-integrity-fixture","max_future_skew_seconds":120,"max_request_age_seconds":600,"public_key_sha256":"\#(fingerprint)","schema_version":1}"#,
            #"{"allowed_bundle_identifiers":["com.example.App"],"build_id_pattern":".*","key_id":"skb-integrity-fixture","max_future_skew_seconds":120,"max_request_age_seconds":600,"public_key_sha256":"\#(fingerprint)","schema_version":1}"#,
            #"{"allowed_bundle_identifiers":["com.example.App"],"build_id_pattern":"^[0-9]+$","key_id":"../unsafe","max_future_skew_seconds":120,"max_request_age_seconds":600,"public_key_sha256":"\#(fingerprint)","schema_version":1}"#,
            #"{"allowed_bundle_identifiers":["com.example.App"],"build_id_pattern":"^[0-9]+$","key_id":"skb-integrity-fixture","max_future_skew_seconds":-1,"max_request_age_seconds":600,"public_key_sha256":"\#(fingerprint)","schema_version":1}"#,
            #"{"allowed_bundle_identifiers":["com.example.App"],"build_id_pattern":"^[0-9]+$","extra":true,"key_id":"skb-integrity-fixture","max_future_skew_seconds":120,"max_request_age_seconds":600,"public_key_sha256":"\#(fingerprint)","schema_version":1}"#
        ]

        for policy in invalidPolicies {
            XCTAssertThrowsError(try PublicSigningPolicy.decode(Data(policy.utf8)))
        }
    }

    private func requestData(
        keyID: String = "skb-integrity-fixture",
        bundleIdentifier: String = "com.example.App",
        buildID: String = "42"
    ) throws -> Data {
        try IntegritySigningRequest(
            schemaVersion: 1,
            algorithm: "Ed25519",
            keyID: keyID,
            bundleIdentifier: bundleIdentifier,
            buildID: buildID,
            manifestSHA256: String(repeating: "a", count: 64),
            createdAtEpochSeconds: requestTime
        ).canonicalData()
    }

    private func policyData(publicKeySHA256: String? = nil) throws -> Data {
        let publicKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed).publicKey
        let fingerprint = publicKeySHA256 ?? publicKey.rawRepresentation.sha256Hex
        return Data(
            #"{"allowed_bundle_identifiers":["com.example.App"],"build_id_pattern":"^[0-9]+$","key_id":"skb-integrity-fixture","max_future_skew_seconds":120,"max_request_age_seconds":600,"public_key_sha256":"\#(fingerprint)","schema_version":1}"#.utf8
        )
    }
}
