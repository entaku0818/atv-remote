import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("端末内のデータ") {
                    Button("URLの履歴を消去", role: .destructive) { confirmClear = true }
                    Text("接続用の鍵はこの端末のKeychainに、URL履歴はこの端末内に保存します。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("このアプリについて") {
                    NavigationLink("プライバシーについて") { PrivacyView() }
                    NavigationLink("オープンソースライセンス") { LicenseView() }
                    Text("Google TV / Android TV向けの非公式リモコンです。Googleおよび各動画サービスとは関係ありません。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(
                        "バージョン \(appVersion)"
                    )
                        .font(.footnote)
                }
            }
            .navigationTitle("設定")
            .toolbar { Button("閉じる") { dismiss() } }
            .confirmationDialog("URL履歴をすべて消去しますか？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("履歴を消去", role: .destructive) { LinkHistory.shared.clear() }
            }
        }
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("収集するデータ") {
                Text("このアプリには広告・分析SDKを組み込んでいません。開発者のサーバーへ接続情報や操作履歴を送信しません。")
            }
            Section("TVとの通信") {
                Text("ローカルネットワーク上でTVを検索し、暗号化した接続で操作や入力したURLをTVに送信します。URLを受け取ったTV上のサービスには、それぞれのプライバシーポリシーが適用されます。")
            }
            Section("端末内の保存") {
                Text(
                    "接続に使う証明書と秘密鍵はKeychainに保存します。送信したURLは最大30件を端末内に保存し、設定から消去できます。"
                    + "端末のバックアップ設定によってURL履歴がバックアップされる場合があります。"
                )
            }
        }
        .navigationTitle("プライバシー")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LicenseView: View {
    private let names = ["ATVRemote", "SwiftProtobuf"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(names, id: \.self) { name in
                    Text(name).font(.headline)
                    if let url = Bundle.main.url(forResource: "\(name)-LICENSE", withExtension: "txt"),
                       let text = try? String(contentsOf: url, encoding: .utf8) {
                        Text(text).font(.caption).textSelection(.enabled)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("ライセンス")
        .navigationBarTitleDisplayMode(.inline)
    }
}
