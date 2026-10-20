import SwiftUI

@main
struct WedoProbeApp: App {
    @StateObject private var ble = WedoBleManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ble)
                .frame(minWidth: 980, minHeight: 700)
        }
    }
}
