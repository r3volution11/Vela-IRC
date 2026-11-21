// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Ed25519 keys in Sparkle's format, for scripts/sparkle-key.sh,
// scripts/release.sh and scripts/test-update.sh. Run with `swift`:
//
//   swift scripts/lib/sparkle-ed25519.swift generate-op-item <title>
//       A new key, as a 1Password item (JSON, for `op item create -`) on
//       standard output: the private key in the item's password field, the
//       public key in a text field.
//   swift scripts/lib/sparkle-ed25519.swift generate
//       A new key on standard output: the private key, then the public key,
//       one per line. For throwaway test keys only.
//   swift scripts/lib/sparkle-ed25519.swift public
//       Reads a private key from standard input and prints its public key.
//   swift scripts/lib/sparkle-ed25519.swift verify <file> <signature> <public key>
//       Exits 0 if <signature> (base64) is a valid signature of <file> for
//       <public key> (base64), as Sparkle checks an update, and 1 if not.
//
// Sparkle's format: the private key is the base64 of the key's 32-byte
// seed, as `generate_keys -x` exports it and `sign_update --ed-key-file`
// reads it (the older 96-byte form, a private key followed by its public
// key, is read too); the public key, SUPublicEDKey, is the base64 of its
// 32 bytes. Keys never touch a file or the Keychain here: they go through
// pipes.

import CryptoKit
import Foundation

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data("sparkle-ed25519: \(message)\n".utf8))
    exit(code)
}

/// The public key of a Sparkle private key (base64), or nil.
func publicKey(ofPrivateKey text: String) -> Data? {
    guard let secret = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
    switch secret.count {
    case 32:
        return try? Curve25519.Signing.PrivateKey(rawRepresentation: secret).publicKey.rawRepresentation
    case 96:
        // The older format: a 64-byte private key, then the public key.
        return secret.suffix(32)
    default:
        return nil
    }
}

func readStandardInput() -> String {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let text = String(data: data, encoding: .utf8) else { fail("standard input isn't text") }
    return text
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "generate":
    let key = Curve25519.Signing.PrivateKey()
    print(key.rawRepresentation.base64EncodedString())
    print(key.publicKey.rawRepresentation.base64EncodedString())

case "generate-op-item":
    guard arguments.count == 2 else { fail("usage: generate-op-item <title>") }
    let key = Curve25519.Signing.PrivateKey()
    let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
    let item: [String: Any] = [
        "title": arguments[1],
        "category": "PASSWORD",
        "tags": ["Vela"],
        "fields": [
            [
                "id": "password", "type": "CONCEALED", "purpose": "PASSWORD", "label": "password",
                "value": key.rawRepresentation.base64EncodedString(),
            ],
            ["id": "publicKey", "type": "STRING", "label": "public key", "value": publicKey],
            [
                "id": "notesPlain", "type": "STRING", "purpose": "NOTES", "label": "notesPlain",
                "value": """
                    Signs Vela's updates (Sparkle EdDSA, ed25519). The password is the private key in Sparkle's \
                    format (the base64 of its 32-byte seed); scripts/release.sh reads it with `op read` to sign \
                    each release's Vela.dmg. The public key is SUPublicEDKey in Vela/Info.plist. Never put the \
                    private key in a file or the repository. Losing it means rotating keys (docs/RELEASING.md, \
                    "The update signing key").
                    """,
            ],
        ],
    ]
    let data = try JSONSerialization.data(withJSONObject: item, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)

case "public":
    guard let key = publicKey(ofPrivateKey: readStandardInput()) else {
        fail("standard input isn't a Sparkle private key (base64 of 32 or 96 bytes)")
    }
    print(key.base64EncodedString())

case "verify":
    guard arguments.count == 4 else { fail("usage: verify <file> <signature> <public key>") }
    guard let signature = Data(base64Encoded: arguments[2]), signature.count == 64 else {
        fail("the signature isn't base64 of 64 bytes")
    }
    guard let keyData = Data(base64Encoded: arguments[3]), keyData.count == 32,
          let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    else { fail("the public key isn't base64 of 32 bytes") }
    guard let file = try? Data(contentsOf: URL(fileURLWithPath: arguments[1]), options: .mappedIfSafe) else {
        fail("can't read \(arguments[1])")
    }
    exit(key.isValidSignature(signature, for: file) ? 0 : 1)

default:
    fail("usage: generate | generate-op-item <title> | public | verify <file> <signature> <public key>")
}
