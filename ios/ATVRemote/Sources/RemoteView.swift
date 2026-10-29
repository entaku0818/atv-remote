import ATVRemoteKit
import SwiftUI

struct RemoteView: View {
    let device: DeviceDiscovery.Device
    @StateObject private var viewModel: RemoteViewModel
    @StateObject private var logStore = LogStore.shared
    @State private var appLinkURL = ""
    @State private var logCopied = false

    init(device: DeviceDiscovery.Device) {
        self.device = device
        _viewModel = StateObject(wrappedValue: RemoteViewModel(host: device.host ?? ""))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                statusView
                if viewModel.phase == .connected {
                    resultView
                    dpadView
                    systemKeysView
                    appLinkView
                }
                logView
            }
            .padding()
        }
        .navigationTitle(device.name)
        .task { await viewModel.connect() }
        .onDisappear { viewModel.disconnect() }
    }

    @ViewBuilder
    private var statusView: some View {
        switch viewModel.phase {
        case .idle, .connecting:
            ProgressView("接続中…")
        case .pairingCodeRequired, .pairing:
            VStack(spacing: 12) {
                Text("TVに表示された6桁コードを入力してください")
                TextField("6桁コード", text: $viewModel.pairingCode)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .frame(maxWidth: 200)
                Button("ペアリング") {
                    Task { await viewModel.submitPairingCode() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.pairingCode.count != 6 || viewModel.phase == .pairing)
            }
        case .connected:
            VStack(spacing: 4) {
                Label("接続済み", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(viewModel.deviceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !viewModel.currentApp.isEmpty {
                    Text(viewModel.currentApp)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Button("再接続") {
                    Task { await viewModel.connect() }
                }
            }
        }
    }

    private var dpadView: some View {
        VStack(spacing: 8) {
            keyButton("chevron.up", .keycodeDpadUp, label: "上")
            HStack(spacing: 8) {
                keyButton("chevron.left", .keycodeDpadLeft, label: "左")
                Button {
                    viewModel.send(.keycodeDpadCenter, label: "OK")
                } label: {
                    Text("OK")
                        .font(.headline)
                        .frame(width: 64, height: 64)
                }
                .buttonStyle(.borderedProminent)
                keyButton("chevron.right", .keycodeDpadRight, label: "右")
            }
            keyButton("chevron.down", .keycodeDpadDown, label: "下")
        }
    }

    private var systemKeysView: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.send(.keycodeBack, label: "戻る")
            } label: {
                Label("戻る", systemImage: "arrow.uturn.backward")
            }
            Button {
                viewModel.send(.keycodeHome, label: "ホーム")
            } label: {
                Label("ホーム", systemImage: "house")
            }
            Button {
                viewModel.send(.keycodePower, label: "電源")
            } label: {
                Label("電源", systemImage: "power")
            }
        }
        .buttonStyle(.bordered)
    }

    private var appLinkView: some View {
        VStack(spacing: 8) {
            Text("TVer・Netflix・YouTube・Prime Video・Disney+・AbemaTVなどのURLを開けます")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("アプリのURL（例: https://tver.jp/episodes/...）", text: $appLinkURL)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button {
                viewModel.launch(appLinkURL)
            } label: {
                Label("TVで開く", systemImage: "play.tv")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!appLinkURL.hasPrefix("http"))
        }
    }

    @ViewBuilder
    private var resultView: some View {
        if let result = viewModel.result {
            Label(result.text, systemImage: Self.icon(for: result.kind))
                .font(.callout)
                .foregroundStyle(Self.color(for: result.kind))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Self.color(for: result.kind).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .animation(.default, value: result)
        }
    }

    private var logView: some View {
        DisclosureGroup("ログ（\(logStore.lines.count)）") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Button {
                        UIPasteboard.general.string = logStore.allText
                        logCopied = true
                    } label: {
                        Label(logCopied ? "コピーしました" : "全部コピー", systemImage: logCopied ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(logStore.lines.isEmpty)
                    ShareLink(item: logStore.allText) {
                        Label("共有", systemImage: "square.and.arrow.up")
                    }
                    Spacer()
                    Button("クリア", role: .destructive) { logStore.clear() }
                }
                .font(.caption)
                ForEach(logStore.lines.reversed()) { line in
                    Text(line.text)
                        .font(.caption2.monospaced())
                        .foregroundStyle(line.entry.level == .error ? Color.red : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 8)
        }
        .font(.callout)
        .onChange(of: logStore.lines.count) { logCopied = false }
    }

    private static func icon(for kind: ResultMessage.Kind) -> String {
        switch kind {
        case .info: return "paperplane"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle"
        case .failure: return "xmark.octagon.fill"
        }
    }

    private static func color(for kind: ResultMessage.Kind) -> Color {
        switch kind {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .failure: return .red
        }
    }

    private func keyButton(_ systemImage: String, _ key: Remote_RemoteKeyCode, label: String) -> some View {
        Button {
            viewModel.send(key, label: label)
        } label: {
            Image(systemName: systemImage)
                .frame(width: 64, height: 64)
        }
        .buttonStyle(.bordered)
    }
}
