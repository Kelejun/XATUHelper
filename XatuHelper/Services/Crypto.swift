import Foundation
import CommonCrypto

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
        return aesCBCEncrypt(plain, key: salt, iv: iv) ?? plain
    }

    static func aesCBCEncrypt(_ plaintext: String, key: String, iv: String) -> String? {
        let data = Data(plaintext.utf8)
        let keyData = Data(key.utf8)
        let ivData = Data(iv.utf8)
        guard keyData.count == kCCKeySizeAES128, ivData.count == kCCBlockSizeAES128 else { return nil }

        let bufferSize = data.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var moved = 0

        let status = buffer.withUnsafeMutableBytes { bufRaw -> CCCryptorStatus in
            data.withUnsafeBytes { dataRaw -> CCCryptorStatus in
                keyData.withUnsafeBytes { keyRaw -> CCCryptorStatus in
                    ivData.withUnsafeBytes { ivRaw -> CCCryptorStatus in
                        CCCrypt(CCOperation(kCCEncrypt),
                                CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding),
                                keyRaw.baseAddress, keyData.count,
                                ivRaw.baseAddress,
                                dataRaw.baseAddress, data.count,
                                bufRaw.baseAddress, bufferSize,
                                &moved)
                    }
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        return buffer.prefix(moved).base64EncodedString()
    }
}
