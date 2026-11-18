import Foundation

public enum BeamURLRejection: String, Error, Equatable, Sendable, Codable, CaseIterable {
    case empty
    case tooLong
    case malformed
    case unsupportedScheme
    case missingHost
    case embeddedCredentials
    case localHost
}

/// A URL that passed `BeamURLPolicy`. The browser only loads values of this type, so nothing
/// reaches a web view without going through the policy.
public struct ValidatedURL: Equatable, Hashable, Sendable {
    public let url: URL

    fileprivate init(url: URL) {
        self.url = url
    }

    /// Scheme and host only. Paths and queries can carry personal data and stay out of logs.
    public var logDescription: String {
        BeamURLPolicy.logDescription(for: url)
    }
}

public struct BeamURLPolicy: Equatable, Sendable {
    public static let maximumLength = 2048
    public static let allowedSchemes: Set<String> = ["http", "https"]

    /// When false, hosts on the hub's own machine or local network are rejected, so a beam
    /// cannot point the hub's browser at a router or another device in the home.
    public var allowsLocalHosts: Bool

    public init(allowsLocalHosts: Bool = false) {
        self.allowsLocalHosts = allowsLocalHosts
    }

    public func validate(_ url: URL) -> Result<ValidatedURL, BeamURLRejection> {
        validate(url.absoluteString)
    }

    public func validate(_ text: String) -> Result<ValidatedURL, BeamURLRejection> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard trimmed.utf8.count <= Self.maximumLength else { return .failure(.tooLong) }
        guard !trimmed.unicodeScalars.contains(where: Self.isForbidden) else { return .failure(.malformed) }
        guard let components = URLComponents(string: trimmed, encodingInvalidCharacters: false) else {
            return .failure(.malformed)
        }
        guard let scheme = components.scheme?.lowercased(), Self.allowedSchemes.contains(scheme) else {
            return .failure(.unsupportedScheme)
        }
        guard components.user == nil, components.password == nil else {
            return .failure(.embeddedCredentials)
        }
        guard let host = components.host, !host.isEmpty, let url = components.url else {
            return .failure(.missingHost)
        }
        if !allowsLocalHosts, HostClassifier.isLocal(host) {
            return .failure(.localHost)
        }
        return .success(ValidatedURL(url: url))
    }

    /// Turns what a person typed into something `validate` can judge. A bare host such as
    /// "example.com/page" gets "https://". Anything that already names a scheme is left alone so
    /// the policy can reject it.
    public static func normalizedUserInput(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("://") else { return trimmed }
        if let colon = trimmed.firstIndex(of: ":") {
            let beforeColon = trimmed[..<colon]
            guard beforeColon.contains(".") else { return trimmed }
        }
        return "https://" + trimmed
    }

    public static func logDescription(for url: URL) -> String {
        let scheme = url.scheme ?? "?"
        let parsed = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host ?? ""
        let host = parsed.isEmpty ? "?" : parsed
        return "\(scheme)://\(host)"
    }

    private static func isForbidden(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator, .spaceSeparator:
            true
        default:
            false
        }
    }
}

/// Decides whether a URL host names this machine or something on the local network.
public enum HostClassifier {
    public static func isLocal(_ rawHost: String) -> Bool {
        var host = rawHost.lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        if host.contains(":") {
            return isLocalIPv6(host)
        }
        while host.hasSuffix(".") {
            host.removeLast()
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard let last = labels.last, !last.isEmpty else { return true }
        if endsInNumber(last) {
            guard let octets = canonicalIPv4(labels) else { return true }
            return isLocalIPv4(octets)
        }
        if labels.count == 1 { return true }
        return last == "local" || last == "localhost" || last == "internal" || host.hasSuffix(".home.arpa")
    }

    /// Browsers read a host whose last label is a number as an IPv4 address, including hex and
    /// single-integer spellings. Only the plain dotted form is accepted here.
    private static func endsInNumber(_ label: String) -> Bool {
        if label.allSatisfy(\.isASCIIDigit) { return true }
        return label.hasPrefix("0x") && label.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    private static func canonicalIPv4(_ labels: [String]) -> [UInt8]? {
        guard labels.count == 4 else { return nil }
        var octets: [UInt8] = []
        for label in labels {
            guard !label.isEmpty, label.allSatisfy(\.isASCIIDigit), label == "0" || !label.hasPrefix("0"),
                  let value = UInt8(label)
            else { return nil }
            octets.append(value)
        }
        return octets
    }

    private static func isLocalIPv4(_ octets: [UInt8]) -> Bool {
        switch (octets[0], octets[1]) {
        case (0, _), (10, _), (127, _): true
        case (100, 64...127): true
        case (169, 254): true
        case (172, 16...31): true
        case (192, 168): true
        case (224..., _): true
        default: false
        }
    }

    private static func isLocalIPv6(_ host: String) -> Bool {
        let address = String(host.prefix { $0 != "%" })
        var storage = in6_addr()
        guard inet_pton(AF_INET6, address, &storage) == 1 else { return true }
        let bytes = withUnsafeBytes(of: storage) { Array($0) }
        if bytes.dropLast().allSatisfy({ $0 == 0 }), bytes[15] <= 1 { return true }
        if bytes[0] == 0xfe, bytes[1] & 0xc0 == 0x80 { return true }
        if bytes[0] & 0xfe == 0xfc { return true }
        if bytes[0] == 0xff { return true }
        let isMapped = bytes[0..<10].allSatisfy { $0 == 0 } && bytes[10] == 0xff && bytes[11] == 0xff
        let isCompatible = bytes[0..<12].allSatisfy { $0 == 0 }
        if isMapped || isCompatible {
            return isLocalIPv4(Array(bytes[12..<16]))
        }
        return false
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}
