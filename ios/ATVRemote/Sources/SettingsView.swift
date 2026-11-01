import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var purchases: PurchaseStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false
    @State private var showUpgrade = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("購入") {
                    Label(purchases.isUnlocked ? "すべての機能が利用できます" : "無料で動作確認できます",
                          systemImage: purchases.isUnlocked ? "checkmark.seal" : "appletvremote.gen4")
                    if !purchases.isUnlocked { Button("買い切りで全機能を解除") { showUpgrade = true } }
                    Button("購入を復元") { Task { await purchases.restore() } }
                        .disabled(purchases.isBusy)
                    if let message = purchases.message { Text(message).font(.footnote) }
                }
                Section("端末内のデータ") {
                    Button("URLの履歴を消去", role: .destructive) { confirmClear = true }
                    Text("接続用の鍵はこの端末のKeychainに、URL履歴はこの端末内に保存します。履歴を消しても購入は失われません。")
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
            .sheet(isPresented: $showUpgrade) { UpgradeView() }
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
                Text("このアプリには広告やアクセス解析を組み込んでいません。開発者のサーバーへ接続情報や操作履歴を送信しません。")
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
            Section("購入") {
                Text("購入と復元にはAppleのStoreKitを使用します。支払い情報を開発者が受け取ることはありません。購入の確認にはApp Storeとの通信が必要になる場合があります。")
            }
        }
        .navigationTitle("プライバシー")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct UpgradeView: View {
    @EnvironmentObject private var purchases: PurchaseStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "appletvremote.gen4.fill").font(.largeTitle).foregroundStyle(.tint)
                    Text("毎日の操作を、これひとつで。") .font(.largeTitle.bold())
                    Text("買い切り・月額料金なし") .font(.headline)
                    Label("ホーム・音量・電源の操作", systemImage: "tv")
                    Label("動画URLをTVで開く", systemImage: "play.tv")
                    Text("先に無料の方向キー・決定・戻るでTVが動くことを確認してください。電源・音量・URL起動の対応はTVによって異なります。")
                        .foregroundStyle(.secondary)
                    if purchases.isUnlocked {
                        Label("すべての機能が利用できます", systemImage: "checkmark.seal.fill")
                    } else if let offer = purchases.offer {
                        Button("\(offer.price)で全機能を解除") { Task { await purchases.purchase() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(purchases.isBusy)
                    } else {
                        Button("購入情報を再読み込み") { Task { await purchases.load() } }
                            .disabled(purchases.isBusy)
                    }
                    if purchases.isBusy { ProgressView("確認中…") }
                    if let message = purchases.message {
                        Text(message).font(.callout).accessibilityIdentifier("purchaseMessage")
                    }
                    Button("購入を復元") { Task { await purchases.restore() } }.disabled(purchases.isBusy)
                    Text("同じApple Accountで購入を復元できます。Android版の購入とは別です。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: 500, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("全機能を解除")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("閉じる") { dismiss() } }
            .task { await purchases.load() }
        }
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
