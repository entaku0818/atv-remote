import SwiftUI

@main
struct ATVRemoteApp: App {
    init() {
        LogStore.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            DeviceListView()
        }
    }
}
