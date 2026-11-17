import Foundation
import CoreBluetooth

// Keeps a BLE connection open and reads the standard model-number characteristic.
// It never writes to the printer and does not send print or configuration commands.
final class VrettiKeepReady: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager!
    private var target: CBPeripheral?
    private var model: CBCharacteristic?
    private var lastRead: Date?
    private var attemptStarted: Date?
    private var readStarted: Date?
    private var readPending = false
    private var scanning = false
    private let targetID: UUID
    private let deadline: Date

    init(targetID: UUID, duration: TimeInterval) {
        self.targetID = targetID
        self.deadline = Date().addingTimeInterval(duration)
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func log(_ message: String) {
        print("\(ISO8601DateFormatter().string(from: Date())) \(message)")
        fflush(stdout)
    }

    private func scan() {
        guard central.state == .poweredOn, target == nil, !scanning else { return }
        scanning = true
        log("Scanning for Vretti")
        central.scanForPeripherals(withServices: nil)
    }

    private func tick() {
        if Date() >= deadline {
            if let target { central.cancelPeripheralConnection(target) }
            log("Monitor finished")
            exit(0)
        }
        guard let target else { scan(); return }
        if let attemptStarted, target.state != .connected, Date().timeIntervalSince(attemptStarted) >= 30 {
            log("Connection attempt timed out"); central.cancelPeripheralConnection(target)
            self.target = nil; self.attemptStarted = nil; return
        }
        if let attemptStarted, target.state == .connected, model == nil, Date().timeIntervalSince(attemptStarted) >= 30 {
            log("Service discovery timed out"); self.attemptStarted = nil
            central.cancelPeripheralConnection(target); return
        }
        if let readStarted, readPending, Date().timeIntervalSince(readStarted) >= 30 {
            log("Model read timed out"); readPending = false; self.readStarted = nil
            central.cancelPeripheralConnection(target); return
        }
        if target.state == .connected, let model, !readPending,
           lastRead == nil || Date().timeIntervalSince(lastRead!) >= 60 {
            readPending = true
            readStarted = Date()
            target.readValue(for: model)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("Bluetooth state: \(central.state.rawValue)")
        if central.state == .poweredOn { scan() }
        else { scanning = false; target = nil; model = nil; readPending = false }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        guard peripheral.identifier == targetID else { return }
        central.stopScan(); scanning = false
        target = peripheral; peripheral.delegate = self; attemptStarted = Date()
        log("Found Vretti; connecting")
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        attemptStarted = Date()
        log("Connected; discovering device information")
        peripheral.discoverServices([CBUUID(string: "180A")])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("Connection failed: \(error?.localizedDescription ?? "unknown")")
        target = nil; model = nil; readPending = false; attemptStarted = nil; readStarted = nil; lastRead = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("Disconnected: \(error?.localizedDescription ?? "no error reported")")
        target = nil; model = nil; readPending = false; attemptStarted = nil; readStarted = nil; lastRead = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first else {
            log("Device information service unavailable"); central.cancelPeripheralConnection(peripheral); return
        }
        peripheral.discoverCharacteristics([CBUUID(string: "2A24")], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristic = service.characteristics?.first,
              characteristic.properties.contains(.read) else {
            log("Model-number read unavailable"); central.cancelPeripheralConnection(peripheral); return
        }
        model = characteristic
        attemptStarted = nil
        tick()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == CBUUID(string: "2A24") else { return }
        readPending = false; readStarted = nil
        if let error { log("Read failed: \(error.localizedDescription)"); central.cancelPeripheralConnection(peripheral) }
        else { lastRead = Date(); log("Connected; model read succeeded") }
    }
}

guard CommandLine.arguments.count == 3,
      let identifier = UUID(uuidString: CommandLine.arguments[1]),
      let seconds = Double(CommandLine.arguments[2]), (30...86400).contains(seconds) else {
    fputs("Usage: VrettiKeepReady PERIPHERAL_UUID DURATION_SECONDS (30-86400)\n", stderr)
    exit(2)
}
let monitor = VrettiKeepReady(targetID: identifier, duration: seconds)
dispatchMain()
