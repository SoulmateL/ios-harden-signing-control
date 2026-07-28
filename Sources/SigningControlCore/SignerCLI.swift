import Foundation

public struct SignerCLIResult: Equatable, Sendable {
    public let exitCode: Int32
    public let standardOutput: Data
    public let standardError: Data
}

public enum SignerCLI {
    public static func run(arguments: [String], standardInput: Data) -> SignerCLIResult {
        guard arguments == ["version", "--format", "json"] else {
            return failure(.unsupportedCommand)
        }

        let output =
            #"{"name":"ios-harden-actions-signer","schema_version":1,"version":"0.1.0"}"#
            + "\n"
        return SignerCLIResult(
            exitCode: 0,
            standardOutput: Data(output.utf8),
            standardError: Data()
        )
    }

    private static func failure(_ error: SigningControlError) -> SignerCLIResult {
        SignerCLIResult(
            exitCode: 2,
            standardOutput: Data(),
            standardError: Data("错误：\(error.localizedDescription)\n".utf8)
        )
    }
}
