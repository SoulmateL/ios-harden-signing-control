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
        guard Self.matches(keyID, pattern: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#) else {
            throw SigningControlError.invalidField("key_id")
        }
        guard Self.matches(
            bundleIdentifier,
            pattern: #"^[A-Za-z0-9][A-Za-z0-9-]*(?:\.[A-Za-z0-9][A-Za-z0-9-]*)+$"#
        ) else {
            throw SigningControlError.invalidField("bundle_identifier")
        }
        guard Self.matches(buildID, pattern: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#) else {
            throw SigningControlError.invalidField("build_id")
        }
        guard Self.matches(manifestSHA256, pattern: #"^[0-9a-f]{64}$"#) else {
            throw SigningControlError.invalidField("manifest_sha256")
        }
        guard createdAtEpochSeconds >= 0 else {
            throw SigningControlError.invalidField("created_at_epoch_seconds")
        }
    }

    private static func matches(_ value: String, pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}
