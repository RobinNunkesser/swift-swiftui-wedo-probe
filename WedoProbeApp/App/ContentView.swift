import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var ble: WedoBleManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WedoProbe - Native CoreBluetooth Check")
                .font(.title2)
                .bold()

            Text("State: \(ble.stateDescription)")
                .font(.subheadline)

            HStack(spacing: 8) {
                Button(ble.isScanning ? "Stop Scan" : "Start Scan") {
                    ble.isScanning ? ble.stopScan() : ble.startScan()
                }

                Button("Connect") {
                    ble.connectSelected()
                }
                .disabled(ble.selectedDeviceID == nil)

                Button("Disconnect") {
                    ble.disconnect()
                }

                Divider()
                    .frame(height: 20)

                Button("Subscribe Hub") {
                    ble.subscribeHubChannel()
                }
                .disabled(!ble.isConnected)

                Button("Probe Hub") {
                    ble.sendProbe()
                }
                .disabled(!ble.isConnected)

                Button("Read Battery") {
                    ble.readBattery()
                }
                .disabled(!ble.isConnected)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Devices")
                        .font(.headline)

                    List(selection: $ble.selectedDeviceID) {
                        ForEach(ble.devices) { device in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.displayName)
                                    .font(.body)
                                Text("RSSI: \(device.rssiDescription)  UUID: \(device.id.uuidString)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(Optional(device.id))
                        }
                    }
                    .frame(minWidth: 420, minHeight: 320)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Log")
                        .font(.headline)

                    ScrollView {
                        Text(ble.logText)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
                    .frame(minWidth: 520, minHeight: 320)

                    HStack {
                        Button("Copy Log") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(ble.logText, forType: .string)
                        }

                        Button("Clear Log") {
                            ble.clearLog()
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(16)
    }
}
