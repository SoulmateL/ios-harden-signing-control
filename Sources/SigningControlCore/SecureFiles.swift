import Darwin
import Foundation

public enum SecureFiles {
    public static let maximumInputSize = 1_048_576

    public static func readRegularFile(
        at url: URL,
        maximumSize: Int = maximumInputSize
    ) throws -> Data {
        var linkMetadata = stat()
        guard lstat(url.path, &linkMetadata) == 0 else {
            throw SigningControlError.invalidFile
        }
        guard linkMetadata.st_mode & S_IFMT == S_IFREG else {
            throw SigningControlError.invalidFile
        }

        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw SigningControlError.invalidFile
        }
        defer { close(descriptor) }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG else {
            throw SigningControlError.invalidFile
        }
        guard metadata.st_size >= 0, metadata.st_size <= maximumSize else {
            throw SigningControlError.fileTooLarge
        }

        var data = Data()
        data.reserveCapacity(Int(metadata.st_size))
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count == 0 {
                break
            }
            guard count > 0 else {
                if errno == EINTR {
                    continue
                }
                throw SigningControlError.fileOperationFailed
            }
            guard data.count + count <= maximumSize else {
                throw SigningControlError.fileTooLarge
            }
            data.append(contentsOf: buffer[0 ..< count])
        }
        return data
    }

    public static func writeNewFile(_ data: Data, to destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(
            ".\(destination.lastPathComponent).tmp.\(UUID().uuidString)"
        )

        let descriptor = open(
            temporary.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw SigningControlError.fileOperationFailed
        }

        var shouldRemoveTemporary = true
        defer {
            close(descriptor)
            if shouldRemoveTemporary {
                unlink(temporary.path)
            }
        }

        do {
            try data.withUnsafeBytes { rawBuffer in
                guard var pointer = rawBuffer.baseAddress else {
                    return
                }
                var remaining = rawBuffer.count
                while remaining > 0 {
                    let count = Darwin.write(descriptor, pointer, remaining)
                    guard count >= 0 else {
                        if errno == EINTR {
                            continue
                        }
                        throw SigningControlError.fileOperationFailed
                    }
                    pointer = pointer.advanced(by: count)
                    remaining -= count
                }
            }
            guard fsync(descriptor) == 0 else {
                throw SigningControlError.fileOperationFailed
            }
            guard link(temporary.path, destination.path) == 0 else {
                if errno == EEXIST {
                    throw SigningControlError.destinationExists
                }
                throw SigningControlError.fileOperationFailed
            }
            guard unlink(temporary.path) == 0 else {
                unlink(destination.path)
                throw SigningControlError.fileOperationFailed
            }
            shouldRemoveTemporary = false

            let parentDescriptor = open(parent.path, O_RDONLY | O_CLOEXEC)
            if parentDescriptor >= 0 {
                _ = fsync(parentDescriptor)
                close(parentDescriptor)
            }
        } catch {
            throw error
        }
    }
}
