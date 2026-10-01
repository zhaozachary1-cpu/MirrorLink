import Foundation

@main
struct UpdateChecks {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
        }
        check(UpdateConfiguration.validatedFeedURL("https://updates.example.com/appcast.xml") != nil, "HTTPS")
        check(UpdateConfiguration.validatedFeedURL("  https://updates.example.com/feed.xml\n") != nil, "trim")
        for input in ["", "http://example.com/a", "file:///tmp/appcast.xml", "javascript:alert(1)", "https:///", "https://me@example.com/a", "https://me:secret@example.com/a", "https://example.com/a#fragment"] {
            check(UpdateConfiguration.validatedFeedURL(input) == nil, "reject unsafe feed")
        }
        check(!UpdateConfiguration.hasValidPublicKey(nil), "missing key")
        check(!UpdateConfiguration.hasValidPublicKey("not base64!"), "malformed key")
        check(!UpdateConfiguration.hasValidPublicKey(Data(repeating: 0, count: 31).base64EncodedString()), "short key")
        check(UpdateConfiguration.hasValidPublicKey(Data(repeating: 0, count: 32).base64EncodedString()), "key length")
        check(UpdateConfiguration.effectiveFeed(bundled: "https://sealed.example.com/feed", custom: "https://custom.example.com/feed")?.host == "sealed.example.com", "sealed feed wins")
        check(UpdateConfiguration.effectiveFeed(bundled: "http://invalid.example.com/feed", custom: "https://custom.example.com/feed") == nil, "invalid sealed feed fails closed")
        check(UpdateConfiguration.effectiveFeed(bundled: nil, custom: "https://custom.example.com/feed")?.host == "custom.example.com", "custom feed")
        check(UpdateConfiguration.effectiveFeed(bundled: nil, custom: nil) == nil, "no invented feed")
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let plistData = try! Data(contentsOf: root.appendingPathComponent("Sources/MirrorLinkApp/Resources/Info.plist"))
        let info = try! PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
        check(info["CFBundleIdentifier"] as? String == "com.mirrorlink.desktop", "preserve application identity and preferences")
        check((Int(info["CFBundleVersion"] as? String ?? "") ?? 0) >= 4, "newer than installed build 3")
        check(info["SUFeedURL"] as? String == "https://github.com/zhaozachary1-cpu/MirrorLink/releases/latest/download/appcast.xml", "canonical public feed")
        check(info["SUPublicEDKey"] as? String == "bOeogeHcYh4ZR7k1g/Pso/V0MNLZUyzGO1eHTqegci4=", "preserve installed trust key")
        check(info["SURequireSignedFeed"] as? Bool == true, "require authenticated feed")
        check(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true, "authenticate archive before extraction")
        check(info["SUEnableAutomaticChecks"] as? Bool == false, "checks remain opt in")
        check(info["SUAllowsAutomaticUpdates"] as? Bool == false, "no silent installation")
        check(info["SUSendProfileInfo"] as? Bool == false, "no system profile collection")
        check(info["MirrorLinkDistributionChannel"] as? String == "local-preview", "public channel must be selected explicitly at packaging")
        print("MirrorLink update policy checks passed (\(count) checks)")
    }
}
