import Foundation
import SigningControlCore

let arguments = Array(CommandLine.arguments.dropFirst())
var standardInput = Data()
if SignerCLI.requiresStandardInput(arguments: arguments) {
    do {
        while standardInput.count <= SignerCLI.maximumPrivateKeyInputSize {
            let remaining = SignerCLI.maximumPrivateKeyInputSize - standardInput.count + 1
            guard
                let chunk = try FileHandle.standardInput.read(upToCount: remaining),
                !chunk.isEmpty
            else {
                break
            }
            standardInput.append(chunk)
        }
    } catch {
        FileHandle.standardError.write(Data("错误：无法读取标准输入\n".utf8))
        exit(2)
    }
}

let result = SignerCLI.run(
    arguments: arguments,
    standardInput: standardInput
)
FileHandle.standardOutput.write(result.standardOutput)
FileHandle.standardError.write(result.standardError)
exit(result.exitCode)
