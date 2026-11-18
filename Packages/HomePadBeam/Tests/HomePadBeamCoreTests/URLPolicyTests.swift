import Foundation
import Testing
@testable import HomePadBeamCore

@Suite struct BeamURLPolicyTests {
    let policy = BeamURLPolicy()

    @Test(arguments: [
        "https://example.com",
        "http://example.com/path?q=1#frag",
        "HTTPS://Example.COM/a",
        "  https://example.com/trimmed  ",
        "https://sub.example.co.uk:8443/x",
        "https://8.8.8.8/dns",
        "https://[2606:4700:4700::1111]/",
    ])
    func validate_whenWebURL_thenAccepts(text: String) throws {
        let url = try policy.validate(text).get()
        #expect(url.url.absoluteString == text.trimmingCharacters(in: .whitespaces))
    }

    @Test(arguments: [
        ("", BeamURLRejection.empty),
        ("   \n", .empty),
        ("javascript:alert(1)", .unsupportedScheme),
        ("JavaScript:alert(1)", .unsupportedScheme),
        ("file:///etc/passwd", .unsupportedScheme),
        ("data:text/html,<script>1</script>", .malformed),
        ("data:text/html,hi", .unsupportedScheme),
        ("homepad://beam?url=x", .unsupportedScheme),
        ("ftp://example.com", .unsupportedScheme),
        ("example.com/no-scheme", .unsupportedScheme),
        ("https://user:pass@example.com", .embeddedCredentials),
        ("https://user@example.com", .embeddedCredentials),
        ("https://@example.com", .embeddedCredentials),
        ("https://", .missingHost),
        ("https:///path", .missingHost),
        ("https://exa mple.com", .malformed),
        ("https://example.com/a\u{0007}b", .malformed),
        ("https://example.com/\u{202E}gnp.exe", .malformed),
        ("https://example.com\\@evil.com", .malformed),
        ("https://exam<ple.com", .malformed),
        ("http://localhost:8080", .localHost),
        ("http://192.168.1.1/admin", .localHost),
        ("http://10.0.0.5", .localHost),
        ("http://127.0.0.1", .localHost),
        ("http://[::1]/", .localHost),
        ("http://printer.local/", .localHost),
    ])
    func validate_whenUnsafe_thenRejectsWithReason(text: String, reason: BeamURLRejection) {
        #expect(policy.validate(text) == .failure(reason))
    }

    @Test func validate_whenTooLong_thenRejects() {
        let text = "https://example.com/" + String(repeating: "a", count: BeamURLPolicy.maximumLength)
        #expect(policy.validate(text) == .failure(.tooLong))
        let fits = "https://example.com/" + String(repeating: "a", count: BeamURLPolicy.maximumLength - 20)
        #expect((try? policy.validate(fits).get()) != nil)
    }

    @Test func validate_whenLocalHostsAllowed_thenAcceptsLocal() throws {
        let relaxed = BeamURLPolicy(allowsLocalHosts: true)
        #expect(try relaxed.validate("http://192.168.1.10/recipes").get().url.host() == "192.168.1.10")
        #expect(relaxed.validate("http://user@192.168.1.10") == .failure(.embeddedCredentials))
    }

    @Test func validate_whenGivenURL_thenUsesItsText() throws {
        let url = try #require(URL(string: "https://example.com/a?b=c"))
        #expect(try policy.validate(url).get().url == url)
        #expect(policy.validate(URL(fileURLWithPath: "/tmp/x")) == .failure(.unsupportedScheme))
    }

    @Test func logDescription_whenURLHasPathAndQuery_thenKeepsOnlySchemeAndHost() throws {
        let url = try policy.validate("https://example.com/private/path?token=secret").get()
        #expect(url.logDescription == "https://example.com")
        #expect(BeamURLPolicy.logDescription(for: URL(fileURLWithPath: "/tmp/x")) == "file://?")
        let schemeless = try #require(URL(string: "/relative/path"))
        #expect(BeamURLPolicy.logDescription(for: schemeless) == "?://?")
    }

    @Test(arguments: [
        ("example.com", "https://example.com"),
        ("example.com/a b", "https://example.com/a b"),
        ("  example.com:8080/x ", "https://example.com:8080/x"),
        ("https://example.com", "https://example.com"),
        ("http://example.com", "http://example.com"),
        ("javascript:alert(1)", "javascript:alert(1)"),
        ("localhost:3000", "localhost:3000"),
        ("ftp://example.com", "ftp://example.com"),
        ("", ""),
    ])
    func normalizedUserInput_whenTyped_thenAddsSchemeOnlyToBareHosts(input: String, expected: String) {
        #expect(BeamURLPolicy.normalizedUserInput(input) == expected)
    }
}

@Suite struct HostClassifierTests {
    @Test(arguments: [
        "localhost", "LOCALHOST", "foo.localhost", "nas", "router.local", "box.internal", "printer.home.arpa",
        "example.local.", "",
        "0.0.0.0", "10.1.2.3", "127.0.0.1", "100.64.0.1", "100.127.255.255", "169.254.1.1", "172.16.0.1", "172.31.255.255",
        "192.168.0.1", "224.0.0.251", "255.255.255.255",
        "2130706433", "0x7f.0.0.1", "0x7f000001", "127.1", "010.0.0.1", "1.2.3.256", "1.2..4", "1.2.3.4.5",
        "::1", "::", "[::1]", "fe80::1", "fe80::1%en0", "fc00::1", "fd12:3456::1", "ff02::fb",
        "::ffff:192.168.1.1", "::10.0.0.1", "not:an:address", ":",
    ])
    func isLocal_whenHostIsOnThisMachineOrNetwork_thenTrue(host: String) {
        #expect(HostClassifier.isLocal(host))
    }

    @Test(arguments: [
        "example.com", "example.com.", "sub.example.org", "8.8.8.8", "1.1.1.1", "100.63.0.1", "100.128.0.1", "172.15.0.1",
        "172.32.0.1", "192.167.1.1", "169.253.0.1", "223.255.255.255", "localhost.example.com", "my-local.net",
        "2606:4700:4700::1111", "[2001:db8::1]", "::ffff:8.8.8.8", "0xdeadbeef.example.com", "1e100.net",
    ])
    func isLocal_whenHostIsPublic_thenFalse(host: String) {
        #expect(!HostClassifier.isLocal(host))
    }
}
