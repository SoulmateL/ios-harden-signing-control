import Foundation

public struct IntegritySigningRequest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let algorithm: String
    public let keyID: String
    public let bundleIdentifier: String
    public let buildID: String
    public let manifestSHA256: String
    public let createdAtEpochSeconds: Int64

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case algorithm
        case keyID = "key_id"
        case bundleIdentifier = "bundle_identifier"
        case buildID = "build_id"
        case manifestSHA256 = "manifest_sha256"
        case createdAtEpochSeconds = "created_at_epoch_seconds"
    }

    public init(
        schemaVersion: Int,
        algorithm: String,
        keyID: String,
        bundleIdentifier: String,
        buildID: String,
        manifestSHA256: String,
        createdAtEpochSeconds: Int64
    ) {
        self.schemaVersion = schemaVersion
        self.algorithm = algorithm
        self.keyID = keyID
        self.bundleIdentifier = bundleIdentifier
        self.buildID = buildID
        self.manifestSHA256 = manifestSHA256
        self.createdAtEpochSeconds = createdAtEpochSeconds
    }

    public static func decode(_ data: Data) throws -> Self {
        let value = try StrictJSON.decode(
            Self.self,
            from: data,
            keys: Set(CodingKeys.allCases.map(\.rawValue))
        )
        try value.validate()
        return value
    }

    public func canonicalData() throws -> Data {
        try validate()
        return try StrictJSON.encode(self)
    }

    public func requestSHA256() throws -> String {
        try canonicalData().sha256Hex
    }

    private func validate() throws {
        guard schemaVersion == 1 else {
            throw SigningControlError.invalidField("schema_version")
        }
        guard algorithm == "Ed25519" else {
            throw SigningControlError.invalidField("algorithm")
        }
        guard StrictJSON.isSafeIdentifier(keyID) else {
            throw SigningControlError.invalidField("key_id")
        }
        guard StrictJSON.isBundleIdentifier(bundleIdentifier) else {
            throw SigningControlError.invalidField("bundle_identifier")
        }
        guard StrictJSON.isSafeIdentifier(buildID) else {
            throw SigningControlError.invalidField("build_id")
        }
        guard StrictJSON.isSHA256(manifestSHA256) else {
            throw SigningControlError.invalidField("manifest_sha256")
        }
        guard createdAtEpochSeconds >= 0 else {
            throw SigningControlError.invalidField("created_at_epoch_seconds")
        }
    }

}

public struct PublicSigningPolicy: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let keyID: String
    public let publicKeySHA256: String
    public let allowedBundleIdentifiers: [String]
    public let buildIDPattern: String
    public let maxRequestAgeSeconds: Int64
    public let maxFutureSkewSeconds: Int64

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case keyID = "key_id"
        case publicKeySHA256 = "public_key_sha256"
        case allowedBundleIdentifiers = "allowed_bundle_identifiers"
        case buildIDPattern = "build_id_pattern"
        case maxRequestAgeSeconds = "max_request_age_seconds"
        case maxFutureSkewSeconds = "max_future_skew_seconds"
    }

    public static func decode(_ data: Data) throws -> Self {
        let value = try StrictJSON.decode(
            Self.self,
            from: data,
            keys: Set(CodingKeys.allCases.map(\.rawValue))
        )
        try value.validate()
        return value
    }

    public func canonicalData() throws -> Data {
        try validate()
        return try StrictJSON.encode(self)
    }

    private func validate() throws {
        guard schemaVersion == 1 else {
            throw SigningControlError.invalidField("schema_version")
        }
        guard StrictJSON.isSafeIdentifier(keyID) else {
            throw SigningControlError.invalidField("key_id")
        }
        guard StrictJSON.isSHA256(publicKeySHA256) else {
            throw SigningControlError.invalidField("public_key_sha256")
        }
        guard
            !allowedBundleIdentifiers.isEmpty,
            Set(allowedBundleIdentifiers).count == allowedBundleIdentifiers.count,
            allowedBundleIdentifiers.allSatisfy(StrictJSON.isBundleIdentifier)
        else {
            throw SigningControlError.invalidField("allowed_bundle_identifiers")
        }
        guard buildIDPattern == #"^[0-9]+$"# else {
            throw SigningControlError.invalidField("build_id_pattern")
        }
        guard maxRequestAgeSeconds > 0 else {
            throw SigningControlError.invalidField("max_request_age_seconds")
        }
        guard maxFutureSkewSeconds >= 0 else {
            throw SigningControlError.invalidField("max_future_skew_seconds")
        }
    }
}

public struct IntegritySignatureResponse: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let requestSHA256: String
    public let keyID: String
    public let publicKeySHA256: String
    public let signatureBase64: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case requestSHA256 = "request_sha256"
        case keyID = "key_id"
        case publicKeySHA256 = "public_key_sha256"
        case signatureBase64 = "signature_base64"
    }

    public init(
        schemaVersion: Int,
        requestSHA256: String,
        keyID: String,
        publicKeySHA256: String,
        signatureBase64: String
    ) {
        self.schemaVersion = schemaVersion
        self.requestSHA256 = requestSHA256
        self.keyID = keyID
        self.publicKeySHA256 = publicKeySHA256
        self.signatureBase64 = signatureBase64
    }

    public static func decode(_ data: Data) throws -> Self {
        let value = try StrictJSON.decode(
            Self.self,
            from: data,
            keys: Set(CodingKeys.allCases.map(\.rawValue))
        )
        try value.validate()
        return value
    }

    public func canonicalData() throws -> Data {
        try validate()
        return try StrictJSON.encode(self)
    }

    private func validate() throws {
        guard schemaVersion == 1 else {
            throw SigningControlError.invalidField("schema_version")
        }
        guard StrictJSON.isSHA256(requestSHA256) else {
            throw SigningControlError.invalidField("request_sha256")
        }
        guard StrictJSON.isSafeIdentifier(keyID) else {
            throw SigningControlError.invalidField("key_id")
        }
        guard StrictJSON.isSHA256(publicKeySHA256) else {
            throw SigningControlError.invalidField("public_key_sha256")
        }
        guard
            let signature = Data(base64Encoded: signatureBase64),
            signature.count == 64,
            signature.base64EncodedString() == signatureBase64
        else {
            throw SigningControlError.invalidField("signature_base64")
        }
    }
}
