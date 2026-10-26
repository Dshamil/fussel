// Signs a release file for Fussel's self-updater.
// Usage: FUSSEL_SIGNING_KEY=<base64 private key> swift scripts/sign-update.swift <file>   → prints the base64 signature
// Without a file: generates a new key pair, prints the private key and writes the public key to stderr.
import CryptoKit
import Foundation

let args = CommandLine.arguments
if args.count < 2 {
    let key = Curve25519.Signing.PrivateKey()
    FileHandle.standardError.write(Data("public key: \(key.publicKey.rawRepresentation.base64EncodedString())\n".utf8))
    print(key.rawRepresentation.base64EncodedString(), terminator: "")
    exit(0)
}
guard let encoded = ProcessInfo.processInfo.environment["FUSSEL_SIGNING_KEY"],
      let raw = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
    FileHandle.standardError.write(Data("FUSSEL_SIGNING_KEY is missing or invalid\n".utf8))
    exit(1)
}
let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
print(try key.signature(for: data).base64EncodedString(), terminator: "")
