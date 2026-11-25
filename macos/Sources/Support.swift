import AppKit

/// Публичный адрес для благодарностей. Сид и ключи здесь не хранятся.
enum Support {
    static let bitcoinAddress = "bc1q8dtk9sar0862ckav0hacmvllwkhy00rvzn6puv"

    static func copyBitcoinAddress() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(bitcoinAddress, forType: .string)
    }
}
