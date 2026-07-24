//
//  QRCrypto.swift
//  devpro3_G4
//
//  Created by 齊藤 洸希 on 2026/06/26.
//

import Foundation
import CryptoKit

struct QRCrypto {
    static let urlScheme = "devpro3-auth"
    private static let connectHost = "connect"
    private static let encryptedPayloadQueryName = "payload"
    private static let plainIPQueryName = "ip"
    private static let legacySchemePrefix = "devpro3-auth://"
    private static let keyString = "devpro3_G4_Super_Secret_Key_2026"
    private static var symmetricKey: SymmetricKey {
        let keyData = SHA256.hash(data: keyString.data(using: .utf8)!)
        return SymmetricKey(data: keyData)
    }
    
    static func deepLinkString(for ip: String) -> String {
        guard let payload = encryptedPayload(for: ip) else { return "" }
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = connectHost
        components.queryItems = [URLQueryItem(name: encryptedPayloadQueryName, value: payload)]
        return components.string ?? ""
    }
    
    static func encryptIP(_ ip: String) -> String {
        guard let payload = encryptedPayload(for: ip) else { return "" }
        return legacySchemePrefix + payload
    }
    
    static func decryptIP(_ encryptedString: String) -> String? {
        let trimmedString = encryptedString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmedString), let ip = ipAddress(from: url) {
            return ip
        }
        guard trimmedString.hasPrefix(legacySchemePrefix) else { return nil }
        let base64String = String(trimmedString.dropFirst(legacySchemePrefix.count))
        return decryptPayload(base64String)
    }
    
    static func ipAddress(from url: URL) -> String? {
        guard url.scheme == urlScheme, url.host == connectHost,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        
        if let payload = components.queryItems?.first(where: { $0.name == encryptedPayloadQueryName })?.value,
           let ip = decryptPayload(payload) {
            return ip
        }
        
        if let ip = components.queryItems?.first(where: { $0.name == plainIPQueryName })?.value,
           isValidIPAddress(ip) {
            return ip
        }
        
        return nil
    }
    
    private static func encryptedPayload(for ip: String) -> String? {
        let normalizedIP = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidIPAddress(normalizedIP),
              let data = normalizedIP.data(using: .utf8),
              let sealedBox = try? AES.GCM.seal(data, using: symmetricKey),
              let combinedData = sealedBox.combined else {
            return nil
        }
        return combinedData.base64EncodedString()
    }
    
    private static func decryptPayload(_ payload: String) -> String? {
        guard let combinedData = Data(base64Encoded: payload),
              let sealedBox = try? AES.GCM.SealedBox(combined: combinedData),
              let decryptedData = try? AES.GCM.open(sealedBox, using: symmetricKey),
              let ip = String(data: decryptedData, encoding: .utf8),
              isValidIPAddress(ip) else {
            return nil
        }
        return ip
    }
    
    private static func isValidIPAddress(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part), (0...255).contains(value) else { return false }
            return String(value) == part || part == "0"
        }
    }
}
