import ATVRemoteKit
import SwiftUI

struct DeviceListView: View {
    @State private var devices: [DeviceDiscovery.Device] = []
    @State private var discovery = DeviceDiscovery()

    var body: some View {
        NavigationStack {
            List {
                if devices.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Android TVを検索中…")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(devices) { device in
                    NavigationLink(value: device) {
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text(device.host ?? "解決中…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(device.host == nil)
                }
            }
            .navigationTitle("デバイス")
            .navigationDestination(for: DeviceDiscovery.Device.self) { device in
                RemoteView(device: device)
            }
        }
        .onAppear {
            discovery.start { found in
                DispatchQueue.main.async { devices = found }
            }
        }
        .onDisappear { discovery.stop() }
    }
}
