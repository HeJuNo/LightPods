import Foundation

/// Connection handshake. After service discovery, pods that advertised
/// manufacturer data must receive `"sea" + response(4 bytes)` on NUS RX,
/// otherwise they do not operate. Reconstructed from `je.e0.handleMessage`
/// (READY branch).
///
/// 1. Reflected CRC-32 over the 4-byte key, init 0xFFFFFFFF, with a *keyed*
///    polynomial `0xEDB88321 + (version % 50)` (Java signed-byte remainder).
/// 2. Complement the CRC.
/// 3. Jenkins one-at-a-time style final avalanche:
///    `h += h << 3; h ^= h >> 11; h += h << 15` (32-bit wrap).
/// 4. Little-endian bytes.
public enum PodAuthenticator {
    public static let commandPrefix: [UInt8] = Array("sea".utf8)

    public static func response(key: [UInt8], version: Int8) -> [UInt8] {
        // Java: (int)((0xEDB88321L) + (byte % 50)) – remainder keeps the sign of the dividend.
        let poly = UInt32(truncatingIfNeeded: Int64(0xEDB8_8321) + Int64(version % 50))

        var crc: UInt32 = 0xFFFF_FFFF
        for byte in key {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (crc & 1 == 1 ? poly : 0)
            }
        }

        var h = ~crc
        h = h &+ (h << 3)
        h ^= h >> 11
        h = h &+ (h << 15)

        return [UInt8(h & 0xFF), UInt8((h >> 8) & 0xFF), UInt8((h >> 16) & 0xFF), UInt8((h >> 24) & 0xFF)]
    }

    /// Full 7-byte NUS payload.
    public static func command(for ad: PodAdvertisement) -> [UInt8] {
        commandPrefix + response(key: ad.key, version: ad.version)
    }
}
