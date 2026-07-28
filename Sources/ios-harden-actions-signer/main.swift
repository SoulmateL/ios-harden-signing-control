import Foundation
import SigningControlCore

let result = SignerCLI.run(
    arguments: Array(CommandLine.arguments.dropFirst()),
    standardInput: FileHandle.standardInput.readDataToEndOfFile()
)
FileHandle.standardOutput.write(result.standardOutput)
FileHandle.standardError.write(result.standardError)
exit(result.exitCode)
