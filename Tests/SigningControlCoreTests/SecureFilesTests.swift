import Darwin
import Foundation
import XCTest
@testable import SigningControlCore

final class SecureFilesTests: XCTestCase {
    func testReadRegularFileRejectsSymlink() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target")
        let link = directory.appendingPathComponent("link")
        try Data("request".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertThrowsError(try SecureFiles.readRegularFile(at: link))
    }

    func testReadRegularFileRejectsFileOverOneMiB() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("oversized")
        try Data(repeating: 0, count: 1_048_577).write(to: file)

        XCTAssertThrowsError(try SecureFiles.readRegularFile(at: file))
    }

    func testWriteNewFileUsesMode0600AndNeverOverwrites() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("response.json")

        try SecureFiles.writeNewFile(Data("first".utf8), to: file)

        var metadata = stat()
        XCTAssertEqual(lstat(file.path, &metadata), 0)
        XCTAssertEqual(metadata.st_mode & S_IRWXU, S_IRUSR | S_IWUSR)
        XCTAssertEqual(metadata.st_mode & (S_IRWXG | S_IRWXO), 0)
        XCTAssertThrowsError(try SecureFiles.writeNewFile(Data("second".utf8), to: file))
        XCTAssertEqual(try Data(contentsOf: file), Data("first".utf8))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
