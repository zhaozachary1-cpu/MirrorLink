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
        print("MirrorLink update policy checks passed (\(count) checks)")
    }
}
