import Foundation
import Testing
@testable import HomePadMessagingCore

@Suite struct MessageDeepLinkTests {
    typealias Codec = MessageDeepLinkCodec
    private let page = URL(string: "https://example.com/recipes/soup?id=42&lang=en#step-2")!

    private func decode(_ string: String) throws -> MessageDeepLink {
        try Codec.decode(#require(URL(string: string)))
    }

    private static let links: [MessageDeepLink] = [
        .beamPage(URL(string: "https://example.com/recipes/soup?id=42&lang=en#step-2")!),
        .beamPage(URL(string: "http://example.com")!),
        .openApp(id: "messages"),
        .openFace(id: "clock.analog-1"),
    ]

    @Test(arguments: links)
    func appURL_whenDecoded_thenRoundTrips(link: MessageDeepLink) throws {
        let url = try Codec.appURL(for: link)
        #expect(url.scheme == "homepad")
        #expect(url.host() == "message")
        #expect(try Codec.decode(url) == link)
    }

    @Test(arguments: links)
    func messageURL_whenDecoded_thenRoundTrips(link: MessageDeepLink) throws {
        let url = try Codec.messageURL(for: link)
        #expect(url.scheme == "data")
        #expect(try Codec.decode(url) == link)
    }

    @Test func appURL_whenBeamingAPage_thenPageIsFullyPercentEncodedInOneParameter() throws {
        let url = try Codec.appURL(for: .beamPage(page))
        #expect(url.absoluteString == "homepad://message?v=1&kind=beam&url=https%3A%2F%2Fexample.com%2Frecipes%2Fsoup%3Fid%3D42%26lang%3Den%23step-2")
    }

    @Test func encode_whenPageIsNotHTTP_thenRejected() {
        for bad in ["file:///etc/passwd", "javascript:alert(1)", "homepad://pair?code=1", "ftp://example.com/x", "https://", "data:text/html,hi"] {
            let url = URL(string: bad)!
            #expect(throws: MessageDeepLinkError.invalidPageURL) { _ = try Codec.appURL(for: .beamPage(url)) }
            #expect(throws: MessageDeepLinkError.invalidPageURL) { _ = try Codec.messageURL(for: .beamPage(url)) }
        }
    }

    @Test func encode_whenPageHasCredentials_thenRejected() {
        let url = URL(string: "https://user:secret@example.com/")!
        #expect(throws: MessageDeepLinkError.invalidPageURL) { _ = try Codec.appURL(for: .beamPage(url)) }
        #expect(throws: MessageDeepLinkError.invalidPageURL) { _ = try Codec.appURL(for: .beamPage(URL(string: "https://user@example.com/")!)) }
    }

    @Test func encode_whenPageTooLong_thenRejected() {
        let url = URL(string: "https://example.com/" + String(repeating: "a", count: 1800))!
        #expect(throws: MessageDeepLinkError.invalidPageURL) { _ = try Codec.messageURL(for: .beamPage(url)) }
    }

    @Test func encode_whenEncodedLinkExceedsCap_thenTooLong() {
        // Each "%" grows to three characters when percent-encoded, which pushes a valid page past the cap.
        let url = URL(string: "https://example.com/?q=" + String(repeating: "%20", count: 500))!
        #expect(throws: MessageDeepLinkError.tooLong) { _ = try Codec.appURL(for: .beamPage(url)) }
    }

    @Test func encode_whenIdentifierInvalid_thenRejected() {
        for bad in ["", "has space", "a/b", "a&b=c", String(repeating: "x", count: 65), "émoji"] {
            #expect(throws: MessageDeepLinkError.invalidIdentifier) { _ = try Codec.appURL(for: .openApp(id: bad)) }
            #expect(throws: MessageDeepLinkError.invalidIdentifier) { _ = try Codec.messageURL(for: .openFace(id: bad)) }
        }
    }

    @Test func decode_whenURLIsSomethingElse_thenNotAMessageLink() {
        for other in ["https://example.com/?v=1&kind=beam", "homepad://pair?code=123", "homepad://beam?url=x", "data:text/plain,v=1&kind=app&id=x", "mailto:a@example.com"] {
            #expect(throws: MessageDeepLinkError.notAMessageLink) { _ = try decode(other) }
        }
    }

    @Test func decode_whenKindIsPairing_thenRefused() {
        for kind in ["pair", "pairing", "invite"] {
            #expect(throws: MessageDeepLinkError.kindNotAllowed) { _ = try decode("homepad://message?v=1&kind=\(kind)&code=123456") }
            #expect(throws: MessageDeepLinkError.kindNotAllowed) { _ = try decode("data:application/vnd.homepad.link,v=1&kind=\(kind)") }
        }
    }

    @Test func decode_whenKindUnknown_thenRejected() {
        #expect(throws: MessageDeepLinkError.unknownKind) { _ = try decode("homepad://message?v=1&kind=unlock") }
    }

    @Test func decode_whenVersionIsNotCurrent_thenRejected() {
        #expect(throws: MessageDeepLinkError.unsupportedVersion) { _ = try decode("homepad://message?v=2&kind=app&id=messages") }
        #expect(throws: MessageDeepLinkError.unsupportedVersion) { _ = try decode("homepad://message?v=01&kind=app&id=messages") }
    }

    @Test func decode_whenRequiredParameterMissing_thenRejected() {
        for link in ["homepad://message?kind=app&id=x", "homepad://message?v=1&id=x", "homepad://message?v=1&kind=beam", "homepad://message?v=1&kind=app", "homepad://message?v=1&kind=face"] {
            #expect(throws: MessageDeepLinkError.missingParameter) { _ = try decode(link) }
        }
    }

    @Test func decode_whenParameterRepeatedUnknownOrMalformed_thenRejected() {
        for link in [
            "homepad://message?v=1&kind=app&id=a&id=b",
            "homepad://message?v=1&kind=app&id=a&extra=1",
            "homepad://message?v=1&kind=app&id",
            "homepad://message?v=1&&kind=app&id=a",
            "homepad://message/extra?v=1&kind=app&id=a",
            "homepad://message?v=1&kind=app&id=a#fragment",
            "homepad://message?v=1&kind=app&id=%FF",
            "homepad://message",
            "data:application/vnd.homepad.link,",
        ] {
            #expect(throws: MessageDeepLinkError.malformed) { _ = try decode(link) }
        }
    }

    @Test func decode_whenPathIsASingleSlash_thenAccepted() throws {
        #expect(try decode("homepad://message/?v=1&kind=app&id=messages") == .openApp(id: "messages"))
        #expect(try decode("HOMEPAD://MESSAGE?v=1&kind=app&id=messages") == .openApp(id: "messages"))
    }

    @Test func decode_whenEmbeddedPageIsNotHTTP_thenRejected() {
        for page in ["file%3A%2F%2F%2Fetc%2Fpasswd", "javascript%3Aalert(1)", "homepad%3A%2F%2Fmessage%3Fv%3D1", "https%3A%2F%2Fuser%3Apw%40example.com"] {
            #expect(throws: MessageDeepLinkError.invalidPageURL) { _ = try decode("homepad://message?v=1&kind=beam&url=\(page)") }
        }
    }

    @Test func decode_whenIdentifierInvalid_thenRejected() {
        #expect(throws: MessageDeepLinkError.invalidIdentifier) { _ = try decode("homepad://message?v=1&kind=app&id=a%2Fb") }
        #expect(throws: MessageDeepLinkError.invalidIdentifier) { _ = try decode("homepad://message?v=1&kind=face&id=") }
    }

    @Test func decode_whenLinkExceedsCap_thenTooLong() {
        let long = "homepad://message?v=1&kind=app&id=" + String(repeating: "a", count: 2100)
        #expect(throws: MessageDeepLinkError.tooLong) { _ = try decode(long) }
    }

    @Test func validatedPage_whenSchemeIsUppercaseOrPadded_thenAccepted() throws {
        #expect(try Codec.validatedPage("  HTTPS://Example.com/a  ").absoluteString == "HTTPS://Example.com/a")
    }

    @Test func validatedPage_whenTextIsNotAURL_thenRejected() {
        #expect(throws: MessageDeepLinkError.invalidPageURL) { _ = try Codec.validatedPage("not a url") }
        #expect(throws: MessageDeepLinkError.invalidPageURL) { _ = try Codec.validatedPage("") }
    }
}
