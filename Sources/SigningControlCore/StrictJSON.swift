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
    case invalidPrivateKey
    case policyRejected
    case requestExpired
    case requestFromFuture

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
        case .invalidPrivateKey:
            "私钥输入无效"
        case .policyRejected:
            "请求不符合签名策略"
        case .requestExpired:
            "签名请求已过期"
        case .requestFromFuture:
            "签名请求时间超出允许范围"
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

    static func matches(_ value: String, pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    static func isSafeIdentifier(_ value: String) -> Bool {
        matches(value, pattern: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#)
    }

    static func isBundleIdentifier(_ value: String) -> Bool {
        matches(
            value,
            pattern: #"^[A-Za-z0-9][A-Za-z0-9-]*(?:\.[A-Za-z0-9][A-Za-z0-9-]*)+$"#
        )
    }

    static func isSHA256(_ value: String) -> Bool {
        matches(value, pattern: #"^[0-9a-f]{64}$"#)
    }
}

extension Data {
    var sha256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
