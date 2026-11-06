import SwiftUI

@main
struct ATVRemoteApp: App {
    init() {
        #if DEBUG
        LogStore.shared.install()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            DeviceListView()
        }
    }
}
