import Foundation
import CoreBluetooth
import Combine

final class S1Bluetooth: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var message = "Ready for your next sticker" { didSet { saveDiagnostic() } }
    @Published var busy = false
    private var central: CBCentralManager!
    private var printer: CBPeripheral?
    private var writer: CBCharacteristic?
    private let transport = PrinterCreditQueue()
    private var phase = "idle"
    private var response = Data()
    private var pending: Data?
    private var generation = UUID()
    private var timeoutToken = UUID()
    private var readReady = false
    private var reportedMTU: Int?
    private var initialCredits: Int?
    private var flowReady = false
    private var finalDeadline = Date.distantPast
    private var lastDiagnostic = Date.distantPast

    override init() {
        super.init()
        transport.canSend = { [weak self] in self?.printer?.canSendWriteWithoutResponse ?? false }
        transport.send = { [weak self] data in
            guard let self, let printer=self.printer, let writer=self.writer else { return }
            printer.writeValue(data, for:writer, type:.withoutResponse)
        }
        central = CBCentralManager(delegate:self, queue:.main)
    }
    func printRaster(_ raster: Data) {
        guard !busy else { return }
        guard !raster.isEmpty, raster.count % 48 == 0, raster.count <= 48*2400 else {
            message="The sticker must be shorter than 300 mm.";return
        }
        guard central.state == .poweredOn else {
            message="Turn on Bluetooth and allow S1 Sticker to use it.";return
        }
        transport.reset();readReady=false;reportedMTU=nil;initialCredits=nil;flowReady=false
        pending=try? PrinterProtocol.encode(raster);busy=true;phase="connecting";generation=UUID()
        message="Looking for your S1…"
        armTimeout(15,"Could not find the S1. Turn it on and disconnect other printer apps.")
        central.scanForPeripherals(withServices:nil)
    }
    func cancel() { finish("Print cancelled. Check the paper before sending it again.") }
    private func armTimeout(_ seconds:Double,_ failure:String) {
        let token=UUID(), run=generation;timeoutToken=token
        DispatchQueue.main.asyncAfter(deadline:.now()+seconds) { [weak self] in
            guard let self,self.busy,self.generation==run,self.timeoutToken==token else{return}
            self.finish(failure)
        }
    }
    func centralManagerDidUpdateState(_ central:CBCentralManager) {
        if central.state == .unauthorized {message="Allow Bluetooth in Settings → Privacy & Security."}
        else if central.state == .poweredOff {message="Turn on Bluetooth to print."}
    }
    func centralManager(_ central:CBCentralManager,didDiscover peripheral:CBPeripheral,advertisementData:[String:Any],rssi RSSI:NSNumber) {
        let name=peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        guard busy,name.hasPrefix("S1-") else{return}
        central.stopScan();printer=peripheral;peripheral.delegate=self
        message="Connecting to \(name)…";central.connect(peripheral)
    }
    func centralManager(_ central:CBCentralManager,didConnect peripheral:CBPeripheral) {
        guard peripheral==printer else{return}
        phase="setup";message="Preparing the printer…"
        armTimeout(10,"The S1 did not finish connecting. Restart the printer and try again.")
        peripheral.discoverServices([CBUUID(string:"FF00")])
    }
    func centralManager(_ central:CBCentralManager,didFailToConnect peripheral:CBPeripheral,error:Error?) {
        finish("Cannot connect. Disconnect other printer apps and try again.")
    }
    func centralManager(_ central:CBCentralManager,didDisconnectPeripheral peripheral:CBPeripheral,error:Error?) {
        if busy,peripheral==printer {finish("Connection lost. Check the sticker before trying again.")}
    }
    func peripheral(_ peripheral:CBPeripheral,didDiscoverServices error:Error?) {
        guard error==nil,let service=peripheral.services?.first else{finish("S1 print service not found.");return}
        peripheral.discoverCharacteristics([CBUUID(string:"FF01"),CBUUID(string:"FF02"),CBUUID(string:"FF03")],for:service)
    }
    func peripheral(_ peripheral:CBPeripheral,didDiscoverCharacteristicsFor service:CBService,error:Error?) {
        writer=service.characteristics?.first{$0.uuid==CBUUID(string:"FF02")}
        guard error==nil,writer != nil,
              let read=service.characteristics?.first(where:{$0.uuid==CBUUID(string:"FF01")}),
              let flow=service.characteristics?.first(where:{$0.uuid==CBUUID(string:"FF03")}) else{
            finish("S1 print connection is incomplete.");return
        }
        peripheral.setNotifyValue(true,for:read)
        peripheral.setNotifyValue(true,for:flow)
    }
    func peripheral(_ peripheral:CBPeripheral,didUpdateNotificationStateFor characteristic:CBCharacteristic,error:Error?) {
        guard error==nil else{finish("Cannot subscribe to the printer.");return}
        if characteristic.uuid==CBUUID(string:"FF01") {readReady=characteristic.isNotifying}
        beginWhenReady()
    }
    private func beginWhenReady() {
        guard busy,!flowReady,readReady,let mtu=reportedMTU,let credits=initialCredits,let printer else{return}
        let limit=min(mtu,printer.maximumWriteValueLength(for:.withoutResponse))
        guard limit>0 else{finish("The printer reported an invalid transfer size.");return}
        transport.start(mtu:limit,credits:credits);flowReady=true
        phase="identity";query([0x1b,0x12,0x64])
    }
    private func query(_ bytes:[UInt8]) {
        response.removeAll()
        armTimeout(8,"The printer stopped responding. Restart it before trying again.")
        transport.enqueue(Data(bytes))
    }
    func peripheral(_ peripheral:CBPeripheral,didUpdateValueFor characteristic:CBCharacteristic,error:Error?) {
        guard busy,peripheral==printer,error==nil,let value=characteristic.value else{return}
        let bytes=[UInt8](value)
        if characteristic.uuid==CBUUID(string:"FF03") {
            guard bytes.count>=2 else{return}
            if bytes[0]==2,bytes.count>=3 {reportedMTU=Int(bytes[1])|(Int(bytes[2])<<8)}
            if bytes[0]==1 {
                if flowReady {transport.grant(Int(bytes[1]))}
                else {initialCredits=(initialCredits ?? 0)+Int(bytes[1])}
            }
            beginWhenReady();return
        }
        guard characteristic.uuid==CBUUID(string:"FF01"),["identity","before","after"].contains(phase) else{return}
        response.append(value)
        guard response.count<=4096 else{finish("Invalid printer response.");return}
        if phase=="identity",response.count>=143 {
            guard response.prefix(3)==Data([0x53,0x31,0]) else{finish("This device is not an iDPRT S1.");return}
            phase="before";query([0x1b,0x12,0x73]);return
        }
        guard phase=="before" || phase=="after",response.count>=17 else{return}
        let status=[UInt8](response)
        guard let start=(0...(status.count-17)).last(where:{Array(status[($0+14)...($0+16)])==[69,78,68]}) else{return}
        let flags=Int(status[start])|(Int(status[start+1])<<8)
        if flags != 0 {
            let names=["Load paper","Printer is too hot","Printer is too cold","Charge the battery","Close the cover","Battery error","Paper positioning error"]
            finish(names.enumerated().filter{flags&(1<<$0.offset) != 0}.map(\.element).joined(separator:" · "));return
        }
        if phase=="after" {
            if status[start+2]==1 {finish("Sticker printed · \(status[start+3])% battery")}
            else if Date()<finalDeadline {
                message="Finishing the sticker…";let run=generation
                DispatchQueue.main.asyncAfter(deadline:.now()+0.5){[weak self] in
                    guard let self,self.busy,self.generation==run else{return};self.query([0x1b,0x12,0x73])
                }
            } else {finish("Sent, but the printer is still busy. Check it before printing again.")}
            return
        }
        guard status[start+2]==1,let pending else{finish("The printer is busy. Try again in a moment.");return}
        phase="transferring";message="Printing · 0%"
        armTimeout(20,"The printer stopped accepting data. Check the sticker before trying again.")
        transport.enqueue(pending,progress:{[weak self] accepted,total in
            guard let self,self.busy else{return}
            let progress="Printing · \(accepted*100/total)%"
            if self.message != progress{self.message=progress}
            self.armTimeout(20,"The printer stopped accepting data. Check the sticker before trying again.")
        },completed:{[weak self] in
            guard let self,self.busy else{return}
            self.phase="after";self.finalDeadline=Date().addingTimeInterval(90)
            self.query([0x1b,0x12,0x73])
        })
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral:CBPeripheral) {transport.pump()}
    private func finish(_ message:String) {
        busy=false;phase="idle";pending=nil;transport.reset();generation=UUID();central.stopScan()
        self.message=message
        if let printer{central.cancelPeripheralConnection(printer)}
        printer=nil;writer=nil;flowReady=false
    }
    private func saveDiagnostic() {
        if busy,Date().timeIntervalSince(lastDiagnostic)<1{return}
        lastDiagnostic=Date()
        guard let dir=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first else{return}
        try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let snapshot:[String:Any]=["message":message,"phase":phase,"busy":busy,"date":ISO8601DateFormatter().string(from:Date()),"flowReady":flowReady,"mtu":reportedMTU ?? 0,"credits":transport.credits]
        if let data=try? JSONSerialization.data(withJSONObject:snapshot){try? data.write(to:dir.appendingPathComponent("last-print-status.json"),options:.atomic)}
    }
}
