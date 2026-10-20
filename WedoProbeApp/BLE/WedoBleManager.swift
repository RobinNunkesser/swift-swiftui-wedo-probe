import Foundation
import CoreBluetooth

struct ScannedDevice: Identifiable, Hashable {
    let id: UUID
    let name: String?
    let rssi: NSNumber
    let advertisedServices: [CBUUID]
    let peripheral: CBPeripheral

    var hasWedoServiceMarker: Bool {
        advertisedServices.contains(WedoBleManager.hubService)
    }

    var displayName: String {
        let base = (name?.isEmpty == false ? name! : "(unnamed)")
        if hasWedoServiceMarker {
            return "\(base) [WEDO UUID]"
        }
        return base
    }

    var rssiDescription: String {
        "\(rssi.intValue)"
    }
}

final class WedoBleManager: NSObject, ObservableObject {
    static let hubService = CBUUID(string: "00001623-1212-EFDE-1623-785FEABCD123")
    static let hubCharacteristic = CBUUID(string: "00001624-1212-EFDE-1623-785FEABCD123")
    static let legacyHubService = CBUUID(string: "00001523-1212-EFDE-1523-785FEABCD123")
    static let legacyHubCharacteristic = CBUUID(string: "00001524-1212-EFDE-1523-785FEABCD123")
    static let batteryService = CBUUID(string: "180F")
    static let batteryCharacteristic = CBUUID(string: "2A19")

    @Published var devices: [ScannedDevice] = []
    @Published var selectedDeviceID: UUID?
    @Published var isScanning: Bool = false
    @Published var isConnected: Bool = false
    @Published var logText: String = ""

    var stateDescription: String {
        switch central.state {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "powered off"
        case .poweredOn: return "powered on"
        @unknown default: return "unknown default"
        }
    }

    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var discoveredByID: [UUID: ScannedDevice] = [:]
    private var hubWriteChannel: CBCharacteristic?
    private var hubNotifyChannel: CBCharacteristic?
    private var batteryLevelChannel: CBCharacteristic?
    private var pendingSubscribeToHub: Bool = false
    private var pendingProbeOnHub: Bool = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard central.state == .poweredOn else {
            appendLog("Cannot scan: Bluetooth not powered on.")
            return
        }

        discoveredByID.removeAll()
        devices = []
        selectedDeviceID = nil
        appendLog("Scan started...")
        isScanning = true
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
        appendLog("Scan stopped.")
    }

    func connectSelected() {
        guard let id = selectedDeviceID, let selected = discoveredByID[id] else {
            appendLog("Connect skipped: no selected device.")
            return
        }

        stopScan()
        appendLog("Connecting to \(selected.displayName) [\(id.uuidString)]...")
        central.connect(selected.peripheral, options: nil)
    }

    func disconnect() {
        guard let peripheral = connectedPeripheral else {
            appendLog("Disconnect skipped: no active connection.")
            return
        }
        central.cancelPeripheralConnection(peripheral)
    }

    func subscribeHubChannel() {
        guard let peripheral = connectedPeripheral else {
            appendLog("Subscribe skipped: not connected.")
            return
        }
        guard let characteristic = hubNotifyChannel else {
            pendingSubscribeToHub = true
            appendLog("Hub notify channel not discovered yet. Subscribe queued and service discovery retriggered.")
            peripheral.discoverServices(nil)
            return
        }

        peripheral.setNotifyValue(true, for: characteristic)
        appendLog("Requested notify on hub channel: \(characteristic.uuid.uuidString).")
    }

    func sendProbe() {
        guard let peripheral = connectedPeripheral else {
            appendLog("Probe skipped: not connected.")
            return
        }

        guard let characteristic = hubWriteChannel else {
            pendingProbeOnHub = true
            appendLog("Hub write channel not discovered yet. Probe queued and service discovery retriggered.")
            peripheral.discoverServices(nil)
            return
        }

        sendProbe(on: characteristic, peripheral: peripheral)
    }

    private func sendProbe(on characteristic: CBCharacteristic, peripheral: CBPeripheral) {
        // 0x05 bytes total, hub id 0x00, type 0x01 hub properties, prop 0x06 battery voltage, op 0x05 request update.
        let frame: [UInt8] = [0x05, 0x00, 0x01, 0x06, 0x05]
        write(frame: frame, on: characteristic, peripheral: peripheral)
        appendLog("Probe frame sent on hub write channel \(characteristic.uuid.uuidString): \(Self.hex(frame)).")
    }

    func readBattery() {
        guard let peripheral = connectedPeripheral else {
            appendLog("Battery read skipped: not connected.")
            return
        }

        if let batteryChar = batteryLevelChannel {
            peripheral.readValue(for: batteryChar)
            appendLog("Requested battery via 180F/2A19.")
            return
        }

        appendLog("180F/2A19 unavailable, using 1624 hub property fallback.")
        sendProbe()
    }

    func clearLog() {
        logText = ""
    }

    private func write(frame: [UInt8], on characteristic: CBCharacteristic, peripheral: CBPeripheral) {
        let data = Data(frame)
        let props = characteristic.properties

        if props.contains(.writeWithoutResponse) {
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
            return
        }

        if props.contains(.write) {
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
            return
        }

        // Try anyway as a last resort for debug sessions.
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    private func appendLog(_ line: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        logText.append("[\(ts)] \(line)\n")
    }

    private func updateDevices() {
        devices = discoveredByID.values.sorted { lhs, rhs in
            if lhs.hasWedoServiceMarker != rhs.hasWedoServiceMarker {
                return lhs.hasWedoServiceMarker && !rhs.hasWedoServiceMarker
            }
            return lhs.rssi.intValue > rhs.rssi.intValue
        }

        if selectedDeviceID == nil {
            selectedDeviceID = devices.first?.id
        }
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: "-")
    }

    private static func normalizedUuid(_ uuid: CBUUID) -> String {
        uuid.uuidString.uppercased().replacingOccurrences(of: "-", with: "")
    }

    private static func isHubServiceUuid(_ uuid: CBUUID) -> Bool {
        let normalized = normalizedUuid(uuid)
        if normalized == normalizedUuid(hubService) {
            return true
        }
        if normalized == normalizedUuid(legacyHubService) {
            return true
        }
        // Some stacks expose vendor UUIDs with short variants.
        return normalized.hasPrefix("00001623") || normalized.hasPrefix("00001523") || normalized == "1623" || normalized == "1523"
    }

    private static func isHubCharacteristicUuid(_ uuid: CBUUID) -> Bool {
        let normalized = normalizedUuid(uuid)
        if normalized == normalizedUuid(hubCharacteristic) {
            return true
        }
        if normalized == normalizedUuid(legacyHubCharacteristic) {
            return true
        }
        return normalized.hasPrefix("00001624") || normalized.hasPrefix("00001524") || normalized == "1624" || normalized == "1524"
    }

    private static func isBatteryCharacteristicUuid(_ uuid: CBUUID) -> Bool {
        normalizedUuid(uuid) == normalizedUuid(batteryCharacteristic)
    }

    private func parseHubMessage(_ data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 3 else {
            appendLog("1624 notify raw (short): \(Self.hex(bytes))")
            return
        }

        let length = Int(bytes[0])
        let hubId = bytes[1]
        let type = bytes[2]
        let payload = Array(bytes.dropFirst(3))

        appendLog("1624 notify len=\(length) hub=0x\(String(format: "%02X", hubId)) type=0x\(String(format: "%02X", type)) payload=\(Self.hex(payload))")

        // Hub properties update format: [property, operation, value...]
        if type == 0x01, payload.count >= 3 {
            let property = payload[0]
            let operation = payload[1]
            let value = Array(payload.dropFirst(2))

            if property == 0x06, operation == 0x06, let level = value.first {
                appendLog("Battery via 1624 hub property: \(level)%")
            }
        }
    }
}

extension WedoBleManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        appendLog("Central state changed to \(stateDescription).")
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let advertised = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let device = ScannedDevice(
            id: peripheral.identifier,
            name: peripheral.name,
            rssi: RSSI,
            advertisedServices: advertised,
            peripheral: peripheral
        )

        discoveredByID[device.id] = device
        updateDevices()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        isConnected = true
        hubWriteChannel = nil
        hubNotifyChannel = nil
        batteryLevelChannel = nil
        pendingSubscribeToHub = false
        pendingProbeOnHub = false
        appendLog("Connected: \(peripheral.identifier.uuidString). Discovering services...")
        // Discover all services to avoid missing 1623/1624 when devices expose non-standard forms.
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        isConnected = false
        appendLog("Connect failed: \(error?.localizedDescription ?? "unknown error").")
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        isConnected = false
        connectedPeripheral = nil
        hubWriteChannel = nil
        hubNotifyChannel = nil
        batteryLevelChannel = nil
        appendLog("Disconnected: \(error?.localizedDescription ?? "no error").")
    }
}

extension WedoBleManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            appendLog("Service discovery failed: \(error.localizedDescription).")
            return
        }

        guard let services = peripheral.services else {
            appendLog("No services discovered.")
            return
        }

        for service in services {
            appendLog("Service discovered: \(service.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error {
            appendLog("Characteristic discovery failed for \(service.uuid.uuidString): \(error.localizedDescription)")
            return
        }

        let isHubService = Self.isHubServiceUuid(service.uuid)

        for characteristic in service.characteristics ?? [] {
            appendLog("Characteristic discovered: \(characteristic.uuid.uuidString) props=\(characteristic.properties.rawValue)")

            if Self.isHubCharacteristicUuid(characteristic.uuid) {
                if characteristic.properties.contains(.writeWithoutResponse) || characteristic.properties.contains(.write) {
                    hubWriteChannel = characteristic
                    appendLog("Hub write channel available: \(characteristic.uuid.uuidString).")
                }

                if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                    hubNotifyChannel = characteristic
                    appendLog("Hub notify channel available: \(characteristic.uuid.uuidString).")
                }

                continue
            }

            if isHubService {
                // Legacy hubs may split write and notify across different characteristics.
                if hubWriteChannel == nil && (characteristic.properties.contains(.writeWithoutResponse) || characteristic.properties.contains(.write)) {
                    hubWriteChannel = characteristic
                    appendLog("Hub write fallback channel selected: \(characteristic.uuid.uuidString).")
                }

                if hubNotifyChannel == nil && (characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)) {
                    hubNotifyChannel = characteristic
                    appendLog("Hub notify fallback channel selected: \(characteristic.uuid.uuidString).")
                }
            }

            if Self.isBatteryCharacteristicUuid(characteristic.uuid) {
                batteryLevelChannel = characteristic
                appendLog("Battery channel 2A19 available.")
            }
        }

        if let notify = hubNotifyChannel, pendingSubscribeToHub {
            pendingSubscribeToHub = false
            peripheral.setNotifyValue(true, for: notify)
            appendLog("Queued subscribe executed on hub channel: \(notify.uuid.uuidString).")
        }

        if let write = hubWriteChannel, pendingProbeOnHub {
            pendingProbeOnHub = false
            sendProbe(on: write, peripheral: peripheral)
            appendLog("Queued probe executed on hub channel: \(write.uuid.uuidString).")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            appendLog("Notify state update failed for \(characteristic.uuid.uuidString): \(error.localizedDescription)")
            return
        }

        appendLog("Notify state for \(characteristic.uuid.uuidString): \(characteristic.isNotifying)")
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            appendLog("Write failed for \(characteristic.uuid.uuidString): \(error.localizedDescription)")
            return
        }

        appendLog("Write confirmed for \(characteristic.uuid.uuidString).")
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            appendLog("Value update failed for \(characteristic.uuid.uuidString): \(error.localizedDescription)")
            return
        }

        guard let value = characteristic.value else {
            appendLog("Value update empty for \(characteristic.uuid.uuidString).")
            return
        }

        if characteristic.uuid == hubNotifyChannel?.uuid || characteristic.uuid == hubWriteChannel?.uuid || Self.isHubCharacteristicUuid(characteristic.uuid) {
            parseHubMessage(value)
            return
        }

        if Self.isBatteryCharacteristicUuid(characteristic.uuid), let first = value.first {
            appendLog("Battery via 2A19: \(first)%")
            return
        }

        appendLog("Value update \(characteristic.uuid.uuidString): \(Self.hex([UInt8](value)))")
    }
}
