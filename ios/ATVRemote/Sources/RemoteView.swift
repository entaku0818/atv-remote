import ATVRemoteKit
import SwiftUI

struct RemoteView: View {
    let device: DeviceDiscovery.Device
    @StateObject private var viewModel: RemoteViewModel
    @State private var tverURL = "https://tver.jp/episodes/"

    init(device: DeviceDiscovery.Device) {
        self.device = device
        _viewModel = StateObject(wrappedValue: RemoteViewModel(host: device.host ?? ""))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                statusView
                if viewModel.phase == .connected {
                    dpadView
                    systemKeysView
                    tverView
                }
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
            keyButton("chevron.up", .keycodeDpadUp)
            HStack(spacing: 8) {
                keyButton("chevron.left", .keycodeDpadLeft)
                Button {
                    viewModel.send(.keycodeDpadCenter)
                } label: {
                    Text("OK")
                        .font(.headline)
                        .frame(width: 64, height: 64)
                }
                .buttonStyle(.borderedProminent)
                keyButton("chevron.right", .keycodeDpadRight)
            }
            keyButton("chevron.down", .keycodeDpadDown)
        }
    }

    private var systemKeysView: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.send(.keycodeBack)
            } label: {
                Label("戻る", systemImage: "arrow.uturn.backward")
            }
            Button {
                viewModel.send(.keycodeHome)
            } label: {
                Label("ホーム", systemImage: "house")
            }
            Button {
                viewModel.send(.keycodePower)
            } label: {
                Label("電源", systemImage: "power")
            }
        }
        .buttonStyle(.bordered)
    }

    private var tverView: some View {
        VStack(spacing: 8) {
            TextField("TVer エピソードURL", text: $tverURL)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button {
                viewModel.launch(tverURL)
            } label: {
                Label("TVで観る", systemImage: "play.tv")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!tverURL.hasPrefix("http"))
        }
    }

    private func keyButton(_ systemImage: String, _ key: Remote_RemoteKeyCode) -> some View {
        Button {
            viewModel.send(key)
        } label: {
            Image(systemName: systemImage)
                .frame(width: 64, height: 64)
        }
        .buttonStyle(.bordered)
    }
}
