import ATVRemoteKit
import SwiftUI

struct DeviceListView: View {
    @State private var devices: [DeviceDiscovery.Device] = []
    @State private var discovery = DeviceDiscovery()
    @State private var errorMessage: String?
    @State private var manualIP = ""
    @State private var showHelp = false
    @State private var showSettings = false
    @State private var searchID = UUID()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "appletvremote.gen4.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text("いつものTVを、手のひらから。")
                            .font(.title2.bold())
                        Text("まずTV本体や付属リモコンで電源を入れ、iPhoneと同じWi-Fi（ネットワーク）につないでください。接続中のTVをアプリが検索します。")
                            .foregroundStyle(.secondary)
                        Label("アプリ内課金なしですべての機能が使えます", systemImage: "checkmark.shield")
                            .font(.footnote)
                    }
                    .padding(.vertical, 12)
                }
                Section("近くのTV") {
                    if devices.isEmpty {
                        Label("TVを探しています", systemImage: "wifi")
                        Text(errorMessage ?? "電源OFFでネットワーク接続が切れているTVは見つかりません。TVの電源・Wi-Fi接続と、iPhoneのローカルネットワークの許可を確認してください。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(devices) { device in
                        NavigationLink(value: device) {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(device.name)
                                    Text(device.host ?? "接続先を確認中…")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: "tv") }
                        }
                        .disabled(device.host == nil)
                    }
                    Button("もう一度検索", systemImage: "arrow.clockwise") { searchID = UUID() }
                }
                Section {
                    TextField("例: 192.168.1.20", text: $manualIP)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("TVのIPアドレス")
                        .accessibilityIdentifier("manualIP")
                    if let host = RemoteInput.host(manualIP) {
                        NavigationLink("このIPアドレスに接続", value: DeviceDiscovery.Device.manual(host: host))
                    } else {
                        Text("IPアドレスを入力すると接続できます")
                            .foregroundStyle(.secondary).font(.footnote)
                    }
                } header: { Text("IPアドレスで接続") } footer: {
                    Text("自動検索で見つからない場合に使えます。TVのネットワーク設定に表示されるIPアドレスを入力してください。")
                }
                Button("接続できないとき", systemImage: "questionmark.circle") { showHelp = true }
            }
            .navigationTitle("ポケットリモコン")
            .navigationDestination(for: DeviceDiscovery.Device.self) { RemoteView(device: $0) }
            .toolbar {
                Button("設定", systemImage: "gearshape") { showSettings = true }
                    .accessibilityIdentifier("settings")
            }
            .sheet(isPresented: $showHelp) { ConnectionHelpView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
        .task(id: searchID) { startSearch() }
        .onDisappear { discovery.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { startSearch() } else if phase == .background { discovery.stop() }
        }
    }

    private func startSearch() {
        errorMessage = nil
        devices = []
        discovery.start(onError: { message in
            Task { @MainActor in errorMessage = message }
        }, onUpdate: { found in
            Task { @MainActor in devices = found }
        })
    }
}

struct ConnectionHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("1. TVの電源を入れ、同じWi-Fiへ") {
                    Text("まずTV本体や付属リモコンで電源を入れ、iPhoneと同じWi-Fi（ネットワーク）に接続してください。TVがネットワークにつながっていると、アプリで検索できます。電源OFF時にネットワーク接続が切れるTVは、アプリから発見したり電源を入れたりできません。")
                    Text("TVのネットワーク初期設定が済んでいる必要があります。リモコンをなくしてTVがWi-Fiに接続できない場合、このアプリだけで初期設定はできません。")
                    Text("ゲストWi-Fi、VPN、ルーターの端末間通信制限によってTVが見つからない場合があります。")
                }
                Section("2. ローカルネットワークを許可") {
                    Text("iPhoneの設定で、このアプリのローカルネットワークへのアクセスを許可してください。")
                    Button("iPhoneの設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                Section("3. TV画面のコードを入力") {
                    Text("TVを選択して、画面に表示された6文字のコードをiPhoneに入力します。機種によってTV側で確認操作が必要な場合があります。コードは他の人に教えないでください。")
                }
                Section("対応について") {
                    Text(
                        "Android TV Remote Serviceに対応したGoogle TV / Android TVが対象です。"
                        + "すべての機種での動作は保証されません。電源・音量・URL起動の対応はTVによって異なります。"
                    )
                    Text("TVがネットワークから切断されると、アプリから電源を入れられない場合があります。音量操作の動作もTVや音響機器の構成によって異なります。")
                }
            }
            .navigationTitle("接続ガイド")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("閉じる") { dismiss() } }
        }
    }
}
