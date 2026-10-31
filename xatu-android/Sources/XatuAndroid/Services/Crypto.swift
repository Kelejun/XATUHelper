import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import CryptoSwift

/// 复刻金智 CAS 前端 encrypt.js 的加密方式。
enum Crypto {
    /// 与页面里 $aes_chars 完全一致
    private static let chars = Array("ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678")

    static func randomString(_ n: Int) -> String {
        var s = ""
        s.reserveCapacity(n)
        for _ in 0..<n {
            s.append(chars[Int.random(in: 0..<chars.count)])
        }
        return s
    }

    /// encryptAES(password, salt)：明文前面拼 64 位随机串，AES-CBC 加密后 Base64。
    /// 服务端解密后丢掉前 64 个字符，所以 IV 用随机值也不影响结果。
    static func encryptPassword(_ password: String, salt: String) -> String {
        let plain = randomString(64) + password
        let iv = randomString(16)
        return aesCBCEncrypt(plain, key: salt, iv: iv) ?? ""
    }

    static func aesCBCEncrypt(_ plaintext: String, key: String, iv: String) -> String? {
        guard key.utf8.count == 16, iv.utf8.count == 16 else { return nil }
        guard let encrypted = try? AES(key: Array(key.utf8), blockMode: CBC(iv: Array(iv.utf8)), padding: .pkcs7).encrypt(Array(plaintext.utf8)) else { return nil }
        return Data(encrypted).base64EncodedString()
    }
}
