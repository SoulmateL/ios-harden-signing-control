import Foundation

public struct SignerCLIResult: Equatable, Sendable {
    public let exitCode: Int32
    public let standardOutput: Data
    public let standardError: Data
}

public enum SignerCLI {
    public static let maximumPrivateKeyInputSize = 256

    public static func requiresStandardInput(arguments: [String]) -> Bool {
        arguments.first == "sign" || arguments.first == "derive-public-key"
    }

    public static func run(
        arguments: [String],
        standardInput: Data,
        now: Date = Date()
    ) -> SignerCLIResult {
        if arguments == ["version", "--format", "json"] {
            return versionResult()
        }
        if
            arguments.count == 3,
            arguments[0] == "validate-request",
            arguments[1] == "--request"
        {
            return validateRequest(path: arguments[2])
        }
        if arguments == [
            "derive-public-key",
            "--private-key-stdin",
            "--format",
            "json"
        ] {
            return derivePublicKey(standardInput: standardInput)
        }
        if
            arguments.count == 7,
            arguments[0] == "verify-response",
            arguments[1] == "--request",
            arguments[3] == "--response",
            arguments[5] == "--public-key-base64"
        {
            return verifyResponse(
                requestPath: arguments[2],
                responsePath: arguments[4],
                publicKeyBase64: arguments[6]
            )
        }
        guard
            arguments.count == 8,
            arguments[0] == "sign",
            arguments[1] == "--policy",
            arguments[3] == "--request",
            arguments[5] == "--response",
            arguments[7] == "--private-key-stdin"
        else {
            return failure(.unsupportedCommand)
        }

        guard standardInput.count <= maximumPrivateKeyInputSize else {
            return failure(.invalidPrivateKey)
        }
        guard
            let policy = absoluteFileURL(arguments[2]),
            let request = absoluteFileURL(arguments[4]),
            let response = absoluteFileURL(arguments[6])
        else {
            return failure(.invalidFile)
        }

        do {
            let policyData = try SecureFiles.readRegularFile(at: policy)
            let requestData = try SecureFiles.readRegularFile(at: request)
            let signed = try SigningService().sign(
                requestData: requestData,
                policyData: policyData,
                privateKeyInput: standardInput,
                now: now
            )
            try SecureFiles.writeNewFile(try signed.canonicalData(), to: response)

            let receipt = SigningReceipt(
                keyID: signed.keyID,
                publicKeySHA256: signed.publicKeySHA256,
                requestSHA256: signed.requestSHA256,
                status: "signed"
            )
            var output = try StrictJSON.encode(receipt)
            output.append(0x0A)
            return SignerCLIResult(
                exitCode: 0,
                standardOutput: output,
                standardError: Data()
            )
        } catch let error as SigningControlError {
            return failure(error)
        } catch {
            return failure(.policyRejected)
        }
    }

    private static func versionResult() -> SignerCLIResult {
        let output =
            #"{"name":"ios-harden-actions-signer","schema_version":1,"version":"0.1.0"}"#
            + "\n"
        return SignerCLIResult(
            exitCode: 0,
            standardOutput: Data(output.utf8),
            standardError: Data()
        )
    }

    private static func validateRequest(path: String) -> SignerCLIResult {
        guard let requestURL = absoluteFileURL(path) else {
            return failure(.invalidFile)
        }
        do {
            let data = try SecureFiles.readRegularFile(at: requestURL)
            let request = try IntegritySigningRequest.decode(data)
            guard try request.canonicalData() == data else {
                throw SigningControlError.invalidJSON
            }
            let receipt = RequestValidationReceipt(
                buildID: request.buildID,
                bundleIdentifier: request.bundleIdentifier,
                keyID: request.keyID,
                requestSHA256: data.sha256Hex,
                status: "valid"
            )
            var output = try StrictJSON.encode(receipt)
            output.append(0x0A)
            return SignerCLIResult(
                exitCode: 0,
                standardOutput: output,
                standardError: Data()
            )
        } catch let error as SigningControlError {
            return failure(error)
        } catch {
            return failure(.invalidJSON)
        }
    }

    private static func derivePublicKey(standardInput: Data) -> SignerCLIResult {
        guard standardInput.count <= maximumPrivateKeyInputSize else {
            return failure(.invalidPrivateKey)
        }
        do {
            let derived = try SigningService().derivePublicKey(
                privateKeyInput: standardInput
            )
            let receipt = PublicKeyReceipt(
                algorithm: "Ed25519",
                publicKeyBase64: derived.publicKeyBase64,
                publicKeySHA256: derived.publicKeySHA256,
                status: "derived"
            )
            var output = try StrictJSON.encode(receipt)
            output.append(0x0A)
            return SignerCLIResult(
                exitCode: 0,
                standardOutput: output,
                standardError: Data()
            )
        } catch let error as SigningControlError {
            return failure(error)
        } catch {
            return failure(.invalidPrivateKey)
        }
    }

    private static func verifyResponse(
        requestPath: String,
        responsePath: String,
        publicKeyBase64: String
    ) -> SignerCLIResult {
        guard
            let requestURL = absoluteFileURL(requestPath),
            let responseURL = absoluteFileURL(responsePath)
        else {
            return failure(.invalidFile)
        }
        do {
            let requestData = try SecureFiles.readRegularFile(at: requestURL)
            let responseData = try SecureFiles.readRegularFile(at: responseURL)
            let verified = try SigningService().verify(
                requestData: requestData,
                responseData: responseData,
                publicKeyBase64: publicKeyBase64
            )
            let receipt = SigningReceipt(
                keyID: verified.keyID,
                publicKeySHA256: verified.publicKeySHA256,
                requestSHA256: verified.requestSHA256,
                status: "verified"
            )
            var output = try StrictJSON.encode(receipt)
            output.append(0x0A)
            return SignerCLIResult(
                exitCode: 0,
                standardOutput: output,
                standardError: Data()
            )
        } catch let error as SigningControlError {
            return failure(error)
        } catch {
            return failure(.policyRejected)
        }
    }

    private static func absoluteFileURL(_ path: String) -> URL? {
        guard path.hasPrefix("/"), !path.hasSuffix("/") else {
            return nil
        }
        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard !components.contains("."), !components.contains("..") else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: false)
    }

    private static func failure(_ error: SigningControlError) -> SignerCLIResult {
        SignerCLIResult(
            exitCode: 2,
            standardOutput: Data(),
            standardError: Data("错误：\(error.localizedDescription)\n".utf8)
        )
    }
}

private struct SigningReceipt: Encodable {
    let keyID: String
    let publicKeySHA256: String
    let requestSHA256: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case keyID = "key_id"
        case publicKeySHA256 = "public_key_sha256"
        case requestSHA256 = "request_sha256"
        case status
    }
}

private struct RequestValidationReceipt: Encodable {
    let buildID: String
    let bundleIdentifier: String
    let keyID: String
    let requestSHA256: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case buildID = "build_id"
        case bundleIdentifier = "bundle_identifier"
        case keyID = "key_id"
        case requestSHA256 = "request_sha256"
        case status
    }
}

private struct PublicKeyReceipt: Encodable {
    let algorithm: String
    let publicKeyBase64: String
    let publicKeySHA256: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case algorithm
        case publicKeyBase64 = "public_key_base64"
        case publicKeySHA256 = "public_key_sha256"
        case status
    }
}
