//
//  InstallTLSCert.swift
//  zsignapp
//
//  iOS 27 and later refuse app-install connections served over plain HTTP
//  (ATS enforcement for itms-services payloads), so the local install server
//  terminates TLS with the bundled *.backloop.dev certificate. Its DNS points
//  at 127.0.0.1, so the payload fetch stays on-device and passes ATS.
//

import Foundation
import NIOSSL

enum InstallTLSCert {
    struct Pack {
        let context: NIOSSLContext
        let host: String
    }

    static func load() -> Pack? {
        guard
            let crtURL = Bundle.main.url(forResource: "server", withExtension: "crt"),
            let pemURL = Bundle.main.url(forResource: "server", withExtension: "pem"),
            let cnURL = Bundle.main.url(forResource: "commonName", withExtension: "txt")
        else {
            return nil
        }

        guard
            let chain = try? NIOSSLCertificate.fromPEMFile(crtURL.path),
            let key = try? NIOSSLPrivateKey(file: pemURL.path, format: .pem)
        else {
            return nil
        }

        var config = TLSConfiguration.makeServerConfiguration(
            certificateChain: chain.map { NIOSSLCertificateSource.certificate($0) },
            privateKey: .privateKey(key)
        )
        config.minimumTLSVersion = .tlsv12

        guard let context = try? NIOSSLContext(configuration: config) else {
            return nil
        }

        let raw = (try? String(contentsOf: cnURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }

        // A wildcard CN is not a hostname; any concrete label under it both
        // matches the cert and resolves to loopback via backloop.dev DNS.
        let host = raw.hasPrefix("*.") ? "local" + raw.dropFirst() : raw
        return Pack(context: context, host: host)
    }
}
