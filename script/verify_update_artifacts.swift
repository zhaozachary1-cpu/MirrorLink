import CryptoKit
import Foundation

// Release QA only. The application continues to use Sparkle's own verifier.
// This tool reads the public key from a trusted local bundle, never Keychain.
enum VerificationFailure: Error, CustomStringConvertible {
    case invalid(String)
    var description: String {
        switch self { case .invalid(let message): return message }
    }
}

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw VerificationFailure.invalid(message) }
}

func authenticatedContent(_ feed: Data, key: Curve25519.Signing.PublicKey) throws -> Data {
    let marker = Data("<!-- sparkle-signatures:\n".utf8)
    guard let range = feed.range(of: marker, options: .backwards),
          let footer = String(data: feed[range.lowerBound...], encoding: .utf8) else {
        throw VerificationFailure.invalid("missing signature footer")
    }
    let lines = footer.components(separatedBy: "\n")
    try require(lines.count == 5 && lines[0] == "<!-- sparkle-signatures:"
        && lines[1].hasPrefix("edSignature: ") && lines[2].hasPrefix("length: ")
        && lines[3] == "-->" && lines[4].isEmpty, "invalid signature footer")
    guard let signature = Data(base64Encoded: String(lines[1].dropFirst(13))),
          let length = Int(lines[2].dropFirst(8)) else {
        throw VerificationFailure.invalid("invalid signature or length")
    }
    let content = Data(feed[..<range.lowerBound])
    try require(signature.count == 64 && content.count == length, "feed length mismatch")
    try require(key.isValidSignature(signature, for: content), "feed signature rejected")
    return content
}

func verify(plist: URL, feed: URL, archive: URL, selfTest: Bool) throws {
    let infoData = try Data(contentsOf: plist)
    guard let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
          let publicKey = info["SUPublicEDKey"] as? String,
          let keyData = Data(base64Encoded: publicKey),
          let version = info["CFBundleShortVersionString"] as? String,
          let build = info["CFBundleVersion"] as? String else {
        throw VerificationFailure.invalid("invalid trusted application metadata")
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    let feedData = try Data(contentsOf: feed)
    try require(feedData.count < 4 * 1024 * 1024, "oversized appcast")
    let content = try authenticatedContent(feedData, key: key)
    let xml = try XMLDocument(data: content, options: [.nodeLoadExternalEntitiesNever])
    try require(xml.dtd == nil, "unexpected DTD")
    let expectedName = "MirrorLink-\(version)-update.zip"
    let expectedURL = "https://github.com/zhaozachary1-cpu/MirrorLink/releases/download/v\(version)/\(expectedName)"
    try require(archive.lastPathComponent == expectedName, "unexpected archive filename")
    let candidates = try xml.nodes(forXPath: "/rss/channel/item/enclosure")
        .compactMap { $0 as? XMLElement }
        .filter { $0.attribute(forName: "url")?.stringValue == expectedURL }
    try require(candidates.count == 1, "expected exactly one matching canonical enclosure")
    let enclosure = candidates[0]
    guard let item = enclosure.parent as? XMLElement,
          let signatureText = enclosure.attribute(forName: "sparkle:edSignature")?.stringValue,
          let signature = Data(base64Encoded: signatureText),
          let lengthText = enclosure.attribute(forName: "length")?.stringValue,
          let expectedLength = Int(lengthText) else {
        throw VerificationFailure.invalid("invalid enclosure signature metadata")
    }
    try require(expectedLength > 0, "empty archive length")
    try require(item.elements(forName: "sparkle:version").first?.stringValue == build,
                "update build does not match trusted bundle")
    try require(item.elements(forName: "sparkle:shortVersionString").first?.stringValue == version,
                "update version does not match trusted bundle")
    let archiveData = try Data(contentsOf: archive, options: .mappedIfSafe)
    try require(archiveData.count == expectedLength, "archive length mismatch")
    try require(signature.count == 64 && key.isValidSignature(signature, for: archiveData),
                "archive signature rejected")
    print("PASS: authenticated appcast and archive for \(version) / build \(build)")
    print("PASS: canonical archive URL and byte lengths")
    if selfTest {
        var changedFeed = feedData
        changedFeed[0] ^= 1
        do {
            _ = try authenticatedContent(changedFeed, key: key)
            throw VerificationFailure.invalid("tampered appcast was accepted")
        } catch VerificationFailure.invalid(let message) where message == "feed signature rejected" {
            print("PASS: single-byte appcast modification rejected")
        }
        var changedArchive = archiveData
        changedArchive[0] ^= 1
        try require(!key.isValidSignature(signature, for: changedArchive), "tampered archive was accepted")
        print("PASS: single-byte archive modification rejected")
        var changedSignature = signature
        changedSignature[0] ^= 1
        try require(!key.isValidSignature(changedSignature, for: archiveData), "invalid signature was accepted")
        print("PASS: modified archive signature rejected")
        var truncatedFeed = feedData
        truncatedFeed.removeLast()
        do {
            _ = try authenticatedContent(truncatedFeed, key: key)
            throw VerificationFailure.invalid("truncated signature footer was accepted")
        } catch VerificationFailure.invalid(let message) where message == "invalid signature footer" {
            print("PASS: truncated signature footer rejected")
        }
    }
}

do {
    let arguments = CommandLine.arguments
    try require(arguments.count == 4 || (arguments.count == 5 && arguments[4] == "--self-test"),
                "usage: verify_update_artifacts <trusted Info.plist> <appcast.xml> <update.zip> [--self-test]")
    try verify(plist: URL(fileURLWithPath: arguments[1]),
               feed: URL(fileURLWithPath: arguments[2]),
               archive: URL(fileURLWithPath: arguments[3]), selfTest: arguments.count == 5)
} catch {
    FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
    exit(1)
}
