import Foundation
import Network

enum RemoteInput {
    static func pairingCode(_ input: String) -> String {
        String(input.uppercased().filter { "0123456789ABCDEF".contains($0) }.prefix(6))
    }

    static func host(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return IPv4Address(value) != nil || IPv6Address(value) != nil ? value : nil
    }

    static func linkError(_ value: String) -> String? {
        guard let url = URLComponents(string: value),
              let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
            return "httpまたはhttpsで始まる動画のURLを入力してください。"
        }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if host.lowercased() == "tver.jp" || host.lowercased().hasSuffix(".tver.jp") {
            if path.isEmpty || path == "episodes" || path == "series" {
                return "TVerアプリの共有から、動画やシリーズのURLをコピーしてください。"
            }
        }
        return nil
    }
}
