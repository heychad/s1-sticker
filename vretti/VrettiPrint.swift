import Foundation
import AppKit
import PDFKit
import CoreBluetooth
import Darwin

// A 4×6-inch page at 203 dpi. Keep the full page; never trim blank rows.
enum VrettiPage {
    static let width = 812, height = 1218
    static func render(url: URL, dither: Bool) throws -> (Data, Data) {
        let ext = url.pathExtension.lowercased()
        let rect = NSRect(x: 48, y: 48, width: width - 96, height: height - 96)
        let canvas = NSImage(size: NSSize(width: width, height: height))
        canvas.lockFocus()
        var focused = true
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
        defer { if focused { canvas.unlockFocus() } }
        if ["txt", "md", "markdown"].contains(ext) {
            let text = try String(contentsOf: url, encoding: .utf8)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw issue("The text file is empty.") }
            var cursor = rect.maxY
            func value(_ text: String, _ size: CGFloat, _ bold: Bool) -> NSAttributedString {
                let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 3
                return NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular), .foregroundColor: NSColor.black, .paragraphStyle: paragraph])
            }
            func height(_ value: NSAttributedString, width: CGFloat) -> CGFloat {
                max(24, ceil(value.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height))
            }
            for block in try LabelMarkup.parse(text) {
                switch block {
                case .text(let line, let heading):
                    let v = value(line, heading == 1 ? 44 : heading == 2 ? 36 : 32, heading > 0)
                    let h = line.isEmpty ? CGFloat(16) : height(v, width: rect.width)
                    guard cursor-h >= rect.minY else { throw issue("Text exceeds one 4×6 label; shorten it before printing.") }
                    if !line.isEmpty { v.draw(in: NSRect(x: rect.minX, y: cursor-h, width: rect.width, height: h)) }
                    cursor -= h + 8
                case .table(let rows):
                    let cellWidth = rect.width / CGFloat(rows[0].count)
                    for (rowIndex,row) in rows.enumerated() {
                        let cells = row.map { value($0, 27, rowIndex == 0) }
                        let h = (cells.map { height($0, width: cellWidth - 16) }.max() ?? 24) + 16
                        guard cursor-h >= rect.minY else { throw issue("Table exceeds one 4×6 label; shorten it before printing.") }
                        for (column, cell) in cells.enumerated() {
                            let x = rect.minX + CGFloat(column)*cellWidth
                            let cellRect = NSRect(x: x, y: cursor-h, width: cellWidth, height: h)
                            NSColor.black.setStroke(); let border=NSBezierPath(rect:cellRect);border.lineWidth=1.5;border.stroke()
                            cell.draw(in: cellRect.insetBy(dx: 8, dy: 8))
                        }
                        cursor -= h
                    }
                    cursor -= 12
                }
            }
        } else {
            let source: NSImage
            if ext == "pdf" {
                guard let page = PDFDocument(url: url)?.page(at: 0) else { throw issue("The PDF has no readable first page.") }
                let size = page.bounds(for: .cropBox).size
                guard size.width > 0, size.height > 0 else { throw issue("The PDF page has invalid dimensions.") }
                source = page.thumbnail(of: NSSize(width: CGFloat(width), height: CGFloat(width) * size.height / size.width), for: .cropBox)
            } else {
                guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else { throw issue("Choose a readable image, PDF, or text file.") }
                source = image
            }
            let scale = min(rect.width / source.size.width, rect.height / source.size.height)
            let size = NSSize(width: source.size.width * scale, height: source.size.height * scale)
            source.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
        }
        canvas.unlockFocus(); focused = false
        guard let tiff = canvas.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let cg = bitmap.cgImage else { throw issue("Could not render the label.") }
        let w = width, h = height, rowBytes = (w + 7) / 8
        var pixels = [UInt8](repeating: 255, count: w * h)
        guard let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw issue("Could not create grayscale preview.") }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var raster = Data(repeating: 0, count: rowBytes * h)
        var errors = [Double](repeating: 0, count: w + 2), next = errors
        for y in 0..<h {
            for x in 0..<w {
                let value = min(255, max(0, Double(pixels[y*w+x]) + (dither ? errors[x+1] : 0)))
                let black = value < 128
                if black { raster[y*rowBytes+x/8] |= UInt8(0x80 >> (x % 8)) }
                pixels[y*w+x] = black ? 0 : 255
                if dither {
                    let e = value - (black ? 0 : 255)
                    errors[x+2] += e * 7/16; next[x] += e * 3/16; next[x+1] += e * 5/16; next[x+2] += e/16
                }
            }
            errors = next; next = [Double](repeating: 0, count: w + 2)
        }
        guard let gray = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)?.makeImage(),
              let png = NSBitmapImageRep(cgImage: gray).representation(using: .png, properties: [:]) else { throw issue("Could not save the preview.") }
        return (png, raster)
    }
    static func issue(_ message: String) -> NSError { NSError(domain: "Vretti", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    static func zpl(_ raster: Data) -> Data {
        let stride = (width + 7) / 8
        var left = stride, right = -1, top = height, bottom = -1
        for y in 0..<height { for x in 0..<stride where raster[y*stride+x] != 0 {
            left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
        } }
        guard right >= left, bottom >= top else { return Data("^XA^PW812^LL1218^PQ1^XZ".utf8) }
        let croppedStride = right - left + 1
        let rowsPerBlock = max(1, 60000 / croppedStride)
        var result = Data("^XA^PW812^LL1218".utf8)
        for start in Swift.stride(from: top, through: bottom, by: rowsPerBlock) {
            let end = min(bottom + 1, start + rowsPerBlock)
            var cropped = Data(); cropped.reserveCapacity(croppedStride * (end - start))
            for y in start..<end { cropped.append(raster.subdata(in: (y*stride+left)..<(y*stride+right+1))) }
            result.append(Data("^FO\(left*8),\(start)^GFA,\(cropped.count),\(cropped.count),\(croppedStride),".utf8))
            result.append(Data(cropped.map { String(format: "%02X", $0) }.joined().utf8))
            result.append(Data("^FS".utf8))
        }
        result.append(Data("^PQ1^XZ".utf8)); return result
    }
}

final class VrettiJob: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    let identifier: UUID, packet: Data
    var central: CBCentralManager!, device: CBPeripheral?, writer: CBCharacteristic?
    var offset = 0, currentChunk = 0, started = false
    init(identifier: UUID, packet: Data) { self.identifier = identifier; self.packet = packet; super.init(); central = CBCentralManager(delegate: self, queue: .main) }
    func finish(_ ok: Bool, _ message: String) -> Never {
        let result: [String: Any] = ["ok": ok, "sent": ok ? true : started, "message": message, "bytes_acknowledged": offset]
        if let json = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), let line = String(data: json, encoding: .utf8) { print(line); fflush(stdout) }
        exit(ok ? 0 : 1)
    }
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn {
            if let p = c.retrievePeripherals(withIdentifiers: [identifier]).first { device = p; p.delegate = self; c.connect(p) }
            else { c.scanForPeripherals(withServices: nil) }
        } else if c.state == .poweredOff || c.state == .unauthorized { finish(false, "Bluetooth unavailable or not authorized.") }
    }
    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        guard p.identifier == identifier else { return }; c.stopScan(); device = p; p.delegate = self; c.connect(p)
    }
    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) { p.discoverServices([CBUUID(string: "18F0")]) }
    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { finish(false, "Could not connect to Vretti.") }
    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) { finish(false, "Disconnected. Check the label before retrying.") }
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = p.services?.first else { finish(false, "Printer service unavailable.") }
        p.discoverCharacteristics([CBUUID(string: "2AF1")], for: service)
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let c = service.characteristics?.first, c.properties.contains(.write) else { finish(false, "Printer write characteristic unavailable.") }
        writer = c; send()
    }
    func send() {
        guard let p = device, let c = writer else { finish(false, "Printer connection unavailable.") }
        if offset == packet.count { finish(true, "Bluetooth transfer acknowledged. Check the physical label.") }
        currentChunk = min(p.maximumWriteValueLength(for: .withResponse), packet.count - offset)
        guard currentChunk > 0 else { finish(false, "Invalid Bluetooth chunk size.") }
        started = true; p.writeValue(packet.subdata(in: offset..<(offset + currentChunk)), for: c, type: .withResponse)
    }
    func peripheral(_ p: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else { finish(false, "Bluetooth write failed. Check the label before retrying.") }
        offset += currentChunk; send()
    }
}

func output(_ value: [String: Any], code: Int32) -> Never {
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
    exit(code)
}
let args = CommandLine.arguments
guard args.count >= 2, ["--render", "--print", "--clipboard"].contains(args[1]), args[1] == "--clipboard" || args.count >= 3 else { output(["ok": false, "sent": false, "message": "Use --render or --print FILE, or --clipboard [--dither]."], code: 1) }
var clipboardDirectory: URL?
do {
    let source:URL
    if args[1] == "--clipboard" {
        let board=NSPasteboard.general
        if let urls=board.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL],let url=urls.first {source=url}
        else {
            let directory=FileManager.default.temporaryDirectory.appendingPathComponent("vretti-clipboard-"+UUID().uuidString)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);clipboardDirectory=directory
            if let image=NSImage(pasteboard:board),let tiff=image.tiffRepresentation,let data=NSBitmapImageRep(data:tiff)?.representation(using:.png,properties:[:]) {
                source=directory.appendingPathComponent("clipboard.png");try data.write(to:source,options:.atomic)
            } else if let text=board.string(forType:.string),!text.isEmpty {
                source=directory.appendingPathComponent("clipboard.txt");try text.write(to:source,atomically:true,encoding:.utf8)
            } else {throw VrettiPage.issue("Copy an image, file, or text first.")}
        }
    } else {source=URL(fileURLWithPath: args[2])}
    if args[1] == "--render", !args.contains("--output") { throw VrettiPage.issue("Preview requires --output PNG.") }
    if let index = args.firstIndex(of: "--output") {
        guard index + 1 < args.count else { throw VrettiPage.issue("Choose an output PNG path.") }
        guard source.resolvingSymlinksInPath().standardizedFileURL != URL(fileURLWithPath: args[index+1]).resolvingSymlinksInPath().standardizedFileURL else { throw VrettiPage.issue("Preview must not overwrite the source.") }
    }
    if let index = args.firstIndex(of: "--zpl-output") {
        guard args[1] == "--render", index + 1 < args.count else { throw VrettiPage.issue("ZPL export is available only for previews and needs a path.") }
        let target=URL(fileURLWithPath: args[index+1]).resolvingSymlinksInPath().standardizedFileURL
        guard target != source.resolvingSymlinksInPath().standardizedFileURL else { throw VrettiPage.issue("ZPL export must not overwrite the source.") }
        if let other=args.firstIndex(of: "--output"), other+1<args.count,
           target == URL(fileURLWithPath: args[other+1]).resolvingSymlinksInPath().standardizedFileURL { throw VrettiPage.issue("Choose separate preview and ZPL paths.") }
    }
    let (png, raster) = try VrettiPage.render(url: source, dither: args.contains("--dither"))
    if let index = args.firstIndex(of: "--output"), index + 1 < args.count { try png.write(to: URL(fileURLWithPath: args[index+1]), options: .atomic) }
    if let index = args.firstIndex(of: "--zpl-output"), index + 1 < args.count { try VrettiPage.zpl(raster).write(to: URL(fileURLWithPath: args[index+1]), options: .atomic) }
    if let directory=clipboardDirectory {try? FileManager.default.removeItem(at:directory);clipboardDirectory=nil}
    if args[1] == "--render" { output(["ok": true, "sent": false, "width": VrettiPage.width, "height": VrettiPage.height, "message": "Preview ready"], code: 0) }
    let plist = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/local.chad.VrettiKeepReady.plist")
    guard let dict = NSDictionary(contentsOf: plist), let arguments = dict["ProgramArguments"] as? [String], arguments.count >= 2,
          let identifier = UUID(uuidString: arguments[1]) else { throw VrettiPage.issue("Install Vretti Keep Ready with the printer UUID first.") }
    let lockURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/S1Sticker/vretti-print.lock")
    try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
    guard fd >= 0, flock(fd, LOCK_EX | LOCK_NB) == 0 else { if fd >= 0 { close(fd) }; throw VrettiPage.issue("Vretti is handling another print job.") }
    let job = VrettiJob(identifier: identifier, packet: VrettiPage.zpl(raster))
    DispatchQueue.main.asyncAfter(deadline: .now() + 180) { job.finish(false, job.started ? "Timed out during transfer. Check the label before retrying." : "Timed out before sending; turn on the Vretti and check Bluetooth.") }
    dispatchMain()
} catch { if let directory=clipboardDirectory {try? FileManager.default.removeItem(at:directory)};output(["ok": false, "sent": false, "message": error.localizedDescription], code: 1) }
