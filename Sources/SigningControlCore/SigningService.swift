import CryptoKit
import Foundation

public struct SigningService: Sendable {
    public init() {}

    public func sign(
        requestData: Data,
        policyData: Data,
        privateKeyInput: Data,
        now: Date
    ) throws -> IntegritySignatureResponse {
        let request = try IntegritySigningRequest.decode(requestData)
        let canonicalRequest = try request.canonicalData()
        guard canonicalRequest == requestData else {
            throw SigningControlError.invalidJSON
        }

        let policy = try PublicSigningPolicy.decode(policyData)
        try validate(request: request, policy: policy, now: now)

        let seed = try decodeSeed(privateKeyInput)
        let privateKey: Curve25519.Signing.PrivateKey
        do {
            privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        } catch {
            throw SigningControlError.invalidPrivateKey
        }
        let publicKeySHA256 = privateKey.publicKey.rawRepresentation.sha256Hex
        guard publicKeySHA256 == policy.publicKeySHA256 else {
            throw SigningControlError.policyRejected
        }

        let signature = try privateKey.signature(for: canonicalRequest)
        return IntegritySignatureResponse(
            schemaVersion: 1,
            requestSHA256: canonicalRequest.sha256Hex,
            keyID: policy.keyID,
            publicKeySHA256: publicKeySHA256,
            signatureBase64: signature.base64EncodedString()
        )
    }

    public func publicKeySHA256(privateKeyInput: Data) throws -> String {
        try derivePublicKey(privateKeyInput: privateKeyInput).publicKeySHA256
    }

    public func derivePublicKey(privateKeyInput: Data) throws -> DerivedPublicKey {
        let seed = try decodeSeed(privateKeyInput)
        do {
            let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
            let publicKey = privateKey.publicKey.rawRepresentation
            return DerivedPublicKey(
                publicKeyBase64: publicKey.base64EncodedString(),
                publicKeySHA256: publicKey.sha256Hex
            )
        } catch {
            throw SigningControlError.invalidPrivateKey
        }
    }

    private func validate(
        request: IntegritySigningRequest,
        policy: PublicSigningPolicy,
        now: Date
    ) throws {
        guard request.keyID == policy.keyID else {
            throw SigningControlError.policyRejected
        }
        guard policy.allowedBundleIdentifiers.contains(request.bundleIdentifier) else {
            throw SigningControlError.policyRejected
        }
        guard StrictJSON.matches(request.buildID, pattern: policy.buildIDPattern) else {
            throw SigningControlError.policyRejected
        }

        let nowSeconds = Int64(now.timeIntervalSince1970.rounded(.down))
        guard request.createdAtEpochSeconds <= nowSeconds + policy.maxFutureSkewSeconds else {
            throw SigningControlError.requestFromFuture
        }
        guard nowSeconds - request.createdAtEpochSeconds <= policy.maxRequestAgeSeconds else {
            throw SigningControlError.requestExpired
        }
    }

    private func decodeSeed(_ input: Data) throws -> Data {
        if input.count == 32 {
            return input
        }
        guard
            let encoded = String(data: input, encoding: .utf8),
            let decoded = Data(base64Encoded: encoded),
            decoded.count == 32,
            decoded.base64EncodedString() == encoded
        else {
            throw SigningControlError.invalidPrivateKey
        }
        return decoded
    }
}

public struct DerivedPublicKey: Equatable, Sendable {
    public let publicKeyBase64: String
    public let publicKeySHA256: String
}
