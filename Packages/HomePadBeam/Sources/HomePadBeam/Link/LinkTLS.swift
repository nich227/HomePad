import Foundation
import HomePadBeamCore
import Network
import Security

/// Network parameters for the peer link: TCP with TLS 1.2 authenticated by pre-shared keys.
enum LinkTLS {
    /// TLS_ECDHE_PSK_WITH_CHACHA20_POLY1305_SHA256. The pre-shared key authenticates both ends
    /// and the ephemeral exchange gives forward secrecy.
    private static let preferredSuite: UInt16 = 0xCCAC
    /// TLS_PSK_WITH_AES_256_GCM_SHA384, offered second in case a device lacks the first.
    private static let fallbackSuite: UInt16 = 0x00A9

    /// `nil` when there is no key to install. A link is never created without one.
    static func parameters(credentials: [LinkCredential]) -> NWParameters? {
        guard !credentials.isEmpty else { return nil }
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        for credential in credentials {
            sec_protocol_options_add_pre_shared_key(
                options,
                dispatchData(credential.key) as __DispatchData,
                dispatchData(credential.identity) as __DispatchData
            )
        }
        for raw in [preferredSuite, fallbackSuite] {
            guard let suite = tls_ciphersuite_t(rawValue: raw) else { return nil }
            sec_protocol_options_append_tls_ciphersuite(options, suite)
        }
        // The system's TLS 1.3 does not negotiate an external pre-shared key, so the version is
        // pinned to 1.2, where only the two PSK suites above are offered.
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_tls_tickets_enabled(options, false)
        sec_protocol_options_set_tls_resumption_enabled(options, false)

        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 30
        tcp.keepaliveInterval = 10
        tcp.keepaliveCount = 3
        tcp.noDelay = true
        tcp.connectionTimeout = Int(LinkLimits.handshakeTimeout)

        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }

    private static func dispatchData(_ data: Data) -> DispatchData {
        data.withUnsafeBytes { DispatchData(bytes: $0) }
    }
}
