import CryptoKit
import Foundation

public enum SigningControlError: Error, Equatable, LocalizedError {
    case invalidJSON
    case unexpectedFields
    case invalidField(String)
    case invalidFile
    case fileTooLarge
    case destinationExists
    case fileOperationFailed
    case unsupportedCommand

    public var errorDescription: String? {
        switch self {
        case .invalidJSON:
            "JSON 格式无效"
        case .unexpectedFields:
            "JSON 字段不完全匹配"
        case let .invalidField(field):
            "字段无效：\(field)"
        case .invalidFile:
            "文件必须是普通文件"
        case .fileTooLarge:
            "文件超过大小限制"
        case .destinationExists:
            "目标文件已存在"
        case .fileOperationFailed:
            "文件操作失败"
        case .unsupportedCommand:
            "不支持的命令"
        }
    }
}

enum StrictJSON {
    static func requireExactObjectKeys(_ data: Data, keys: Set<String>) throws {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw SigningControlError.invalidJSON
        }

        guard
            let object = value as? [String: Any],
            Set(object.keys) == keys
        else {
            throw SigningControlError.unexpectedFields
        }
    }

    static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        keys: Set<String>
    ) throws -> T {
        try requireExactObjectKeys(data, keys: keys)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let error as SigningControlError {
            throw error
        } catch {
            throw SigningControlError.invalidJSON
        }
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

extension Data {
    var sha256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
