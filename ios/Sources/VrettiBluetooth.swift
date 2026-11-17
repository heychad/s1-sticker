import Foundation
import CoreBluetooth
import Combine

final class VrettiBluetooth: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var message = "Ready for a 4×6 label"
    @Published private(set) var busy = false
    @Published private(set) var progress: Double?
    private var central: CBCentralManager!
    private var device: CBPeripheral?, writer: CBCharacteristic?
    private var packet = Data(), offset = 0, chunk = 0, started = false
    private var generation = UUID()
    private var candidates: [UUID: CBPeripheral] = [:]
    override init() { super.init(); central = CBCentralManager(delegate: self, queue: .main) }
    func print(_ data: Data) {
        guard !busy else { return }
        guard central.state == .poweredOn else { message = "Turn on Bluetooth and allow printer access."; return }
        packet = data; offset = 0; started = false; busy = true; progress = nil; generation = UUID(); candidates = [:]; let token = generation
        message = "Looking for Vretti…"
        central.scanForPeripherals(withServices: nil)
        DispatchQueue.main.asyncAfter(deadline: .now()+15) { [weak self] in
            guard let self, self.busy, self.generation == token else { return }
            self.central.stopScan()
            guard self.candidates.count == 1, let device = self.candidates.values.first else {
                self.finish(self.candidates.isEmpty ? "Could not find Vretti. Turn it on and disconnect the Mac helper." : "Multiple Vretti printers found. Turn off the others and try again.")
                return
            }
            self.device = device; device.delegate = self; self.central.connect(device); self.message = "Connecting to Vretti…"
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+180) { [weak self] in
            guard let self, self.busy, self.generation == token else { return }
            self.finish(self.started ? "Transfer timed out. Check the label before retrying." : "Could not find Vretti. Turn it on and disconnect the Mac helper.")
        }
    }
    func cancel() { finish(started ? "Cancelled. Check the label before retrying." : "Cancelled before sending.") }
    private func finish(_ text: String) {
        generation = UUID(); central.stopScan(); if let device { central.cancelPeripheralConnection(device) }
        device = nil; writer = nil; packet = Data(); busy = false; progress = nil; message = text
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) { if central.state == .unauthorized { message = "Allow Bluetooth in Settings." } }
    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? p.name ?? ""
        guard busy, name == "4B-2054N" else { return }
        candidates[p.identifier] = p
    }
    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) { if busy && p.identifier == device?.identifier { p.discoverServices([CBUUID(string: "18F0")]) } }
    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { if busy && p.identifier == device?.identifier { finish("Could not connect to Vretti.") } }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) { if busy && p.identifier == device?.identifier { finish(started ? "Disconnected. Check the label before retrying." : "Disconnected before sending.") } }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = p.services?.first else { finish("Vretti service unavailable."); return }
        p.discoverCharacteristics([CBUUID(string: "2AF1")], for: service)
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let c = service.characteristics?.first, c.properties.contains(.write) else { finish("Vretti write service unavailable."); return }
        writer = c; progress = 0; message = "Sending 4×6 label…"; send()
    }
    private func send() {
        guard busy, let p = device, let c = writer else { return }
        if offset == packet.count { finish("Label sent. Check the printer."); return }
        chunk = min(p.maximumWriteValueLength(for: .withResponse), packet.count-offset)
        guard chunk > 0 else { finish("Invalid Bluetooth packet size."); return }
        started = true; p.writeValue(packet.subdata(in: offset..<(offset+chunk)), for: c, type: .withResponse)
    }
    func peripheral(_ p: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard busy else { return }
        guard error == nil else { finish("Transfer failed. Check the label before retrying."); return }
        offset += chunk
        let current = Double(offset) / Double(packet.count)
        if Int(current * 100) > Int((progress ?? 0) * 100) { progress = current }
        send()
    }
}
