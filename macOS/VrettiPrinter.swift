import Foundation
import AppKit
import Combine

@MainActor final class VrettiPrinter: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var rendering = false
    @Published private(set) var preview: NSImage?
    @Published var message = "Ready for a 4×6 label"
    private var generation = UUID()
    private var snapshot: URL?
    private var dither = false
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VrettiMac-\(UUID().uuidString)")
    private var executable: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Vretti Print.app/Contents/MacOS/VrettiPrint") }

    func update(_ document: StickerDocumentModel) {
        let token = UUID(); generation = token; rendering = true; preview = nil; snapshot = nil
        do {
            guard !document.hasStructuredBlocks else { throw StickerRenderer.issue("Vretti preview does not yet support JSON layouts. Use text or an image.") }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let source: URL
            if let image = document.image {
                let oriented = try StickerImage.oriented(image, automatic: document.autoRotate, turns: document.turns)
                guard let data = StickerImage.pngData(oriented) else { throw StickerRenderer.issue("Could not prepare the image.") }
                source = directory.appendingPathComponent("\(token).png"); try data.write(to: source, options: .atomic)
            } else {
                source = directory.appendingPathComponent("\(token).txt"); try document.text.write(to: source, atomically: true, encoding: .utf8)
            }
            let target = directory.appendingPathComponent("\(token)-preview.png")
            let selectedDither = document.dither
            let program = executable
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process(), pipe = Pipe(); process.executableURL = program
                process.arguments = ["--render", source.path, "--output", target.path] + (selectedDither ? ["--dither"] : [])
                process.standardOutput = pipe; process.standardError = Pipe()
                var image: NSImage?, failure = "Could not prepare the 4×6 preview."
                do {
                    try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                    if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any], let text = result["message"] as? String { failure = text }
                    if process.terminationStatus == 0 { image = NSImage(contentsOf: target) }
                } catch { failure = error.localizedDescription }
                let rendered = image, resultMessage = failure
                DispatchQueue.main.async {
                    guard self.generation == token else { return }
                    self.rendering = false; self.preview = rendered
                    if rendered != nil { self.snapshot = source; self.dither = selectedDither; self.message = "4×6 preview ready" }
                    else { self.message = resultMessage }
                }
            }
        } catch { rendering = false; message = error.localizedDescription }
    }

    func printPreview() {
        guard !busy, !rendering, let source = snapshot else { return }
        busy = true; message = "Sending to Vretti…"
        let program = executable, options = dither ? ["--dither"] : []
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process(), pipe = Pipe(); process.executableURL = program
            process.arguments = ["--print", source.path] + options; process.standardOutput = pipe; process.standardError = Pipe()
            var message = "Print result unavailable. Check the label before retrying."
            do {
                try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any], let text = result["message"] as? String { message = text }
            } catch { message = error.localizedDescription }
            let resultMessage = message
            DispatchQueue.main.async { self.busy = false; self.message = resultMessage }
        }
    }
}
