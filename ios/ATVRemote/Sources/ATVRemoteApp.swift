import SwiftUI

@main
struct ATVRemoteApp: App {
    @StateObject private var purchases = PurchaseStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        LogStore.shared.install()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            DeviceListView()
                .environmentObject(purchases)
                .task { await purchases.refreshEntitlement() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await purchases.refreshEntitlement() } }
                }
        }
    }
}
