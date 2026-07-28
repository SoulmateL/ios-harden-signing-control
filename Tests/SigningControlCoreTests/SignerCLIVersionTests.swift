import Foundation
import XCTest
@testable import SigningControlCore

final class SignerCLIVersionTests: XCTestCase {
    func testVersionJSONIsStable() {
        let result = SignerCLI.run(
            arguments: ["version", "--format", "json"],
            standardInput: Data()
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardError, Data())
        XCTAssertEqual(
            String(decoding: result.standardOutput, as: UTF8.self),
            #"{"name":"ios-harden-actions-signer","schema_version":1,"version":"0.1.0"}"# + "\n"
        )
    }

    func testUnknownCommandReturnsStableChineseError() {
        let result = SignerCLI.run(arguments: ["unknown"], standardInput: Data())

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput, Data())
        XCTAssertEqual(
            String(decoding: result.standardError, as: UTF8.self),
            "错误：不支持的命令\n"
        )
    }
}
