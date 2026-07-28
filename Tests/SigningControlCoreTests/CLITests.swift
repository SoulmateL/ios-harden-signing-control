import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import SigningControlCore

final class CLITests: XCTestCase {
    private let seed = Data(repeating: 0x07, count: 32)

    func testSignWritesResponseAndOnlyPublicReceiptToStdout() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let request = directory.appendingPathComponent("request.json")
        let policy = directory.appendingPathComponent("policy.json")
        let response = directory.appendingPathComponent("response.json")
        let requestData = try makeRequestData()
        try requestData.write(to: request)
        try makePolicyData().write(to: policy)

        let result = SignerCLI.run(
            arguments: signArguments(policy: policy, request: request, response: response),
            standardInput: Data(seed.base64EncodedString().utf8),
            now: Date()
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardError, Data())
        let expected =
            #"{"key_id":"skb-integrity-fixture","public_key_sha256":"fe812c12f3ab4ce6ac5db69ac352f906cb1b11ef43fb33e252ef7ff552263889","request_sha256":"\#(requestData.sha256Hex)","status":"signed"}"#
            + "\n"
        XCTAssertEqual(String(decoding: result.standardOutput, as: UTF8.self), expected)
        let signed = try IntegritySignatureResponse.decode(Data(contentsOf: response))
        XCTAssertEqual(signed.requestSHA256, requestData.sha256Hex)

        var metadata = stat()
        XCTAssertEqual(lstat(response.path, &metadata), 0)
        XCTAssertEqual(metadata.st_mode & (S_IRWXG | S_IRWXO), 0)
    }

    func testSignRejectsExistingResponseWithoutChangingIt() throws {
        let directory = try preparedDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let response = directory.appendingPathComponent("response.json")
        try Data("existing".utf8).write(to: response)

        let result = SignerCLI.run(
            arguments: signArguments(
                policy: directory.appendingPathComponent("policy.json"),
                request: directory.appendingPathComponent("request.json"),
                response: response
            ),
            standardInput: seed,
            now: Date()
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertEqual(try Data(contentsOf: response), Data("existing".utf8))
    }

    func testSignRejectsRelativeAndDotComponentPaths() throws {
        let directory = try preparedDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let policy = directory.appendingPathComponent("policy.json")
        let request = directory.appendingPathComponent("request.json")
        let response = directory.appendingPathComponent("response.json")
        let invalidArgumentSets = [
            [
                "sign", "--policy", "policy.json", "--request", request.path,
                "--response", response.path, "--private-key-stdin"
            ],
            [
                "sign", "--policy", policy.path, "--request",
                directory.path + "/./request.json", "--response", response.path,
                "--private-key-stdin"
            ],
            [
                "sign", "--policy", policy.path, "--request", request.path,
                "--response", directory.path + "/nested/../response.json",
                "--private-key-stdin"
            ]
        ]

        for arguments in invalidArgumentSets {
            let result = SignerCLI.run(
                arguments: arguments,
                standardInput: seed,
                now: Date()
            )
            XCTAssertNotEqual(result.exitCode, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: response.path))
        }
    }

    func testSignCapsPrivateKeyInputAndNeverEchoesIt() throws {
        let directory = try preparedDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let oversized = Data(repeating: 0x41, count: 257)
        let result = SignerCLI.run(
            arguments: signArguments(
                policy: directory.appendingPathComponent("policy.json"),
                request: directory.appendingPathComponent("request.json"),
                response: directory.appendingPathComponent("response.json")
            ),
            standardInput: oversized,
            now: Date()
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput, Data())
        XCTAssertFalse(result.standardError.contains(oversized))
        XCTAssertFalse(
            String(decoding: result.standardError, as: UTF8.self)
                .contains(seed.base64EncodedString())
        )
    }

    private func preparedDirectory() throws -> URL {
        let directory = try temporaryDirectory()
        try makeRequestData().write(to: directory.appendingPathComponent("request.json"))
        try makePolicyData().write(to: directory.appendingPathComponent("policy.json"))
        return directory
    }

    private func makeRequestData() throws -> Data {
        try IntegritySigningRequest(
            schemaVersion: 1,
            algorithm: "Ed25519",
            keyID: "skb-integrity-fixture",
            bundleIdentifier: "com.example.App",
            buildID: "42",
            manifestSHA256: String(repeating: "a", count: 64),
            createdAtEpochSeconds: Int64(Date().timeIntervalSince1970)
        ).canonicalData()
    }

    private func makePolicyData() throws -> Data {
        Data(
            #"{"allowed_bundle_identifiers":["com.example.App"],"build_id_pattern":"^[0-9]+$","key_id":"skb-integrity-fixture","max_future_skew_seconds":120,"max_request_age_seconds":600,"public_key_sha256":"fe812c12f3ab4ce6ac5db69ac352f906cb1b11ef43fb33e252ef7ff552263889","schema_version":1}"#.utf8
        )
    }

    private func signArguments(policy: URL, request: URL, response: URL) -> [String] {
        [
            "sign",
            "--policy", policy.path,
            "--request", request.path,
            "--response", response.path,
            "--private-key-stdin"
        ]
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
