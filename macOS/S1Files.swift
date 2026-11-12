import Foundation
import AppKit
import CoreImage
import Darwin

enum S1Files {
    static var directory:URL {
        let url=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/S1Sticker")
        try? FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        return url
    }
    static func save(_ output:StickerOutput)throws {
        guard let png=StickerImage.pngData(output.image) else{throw StickerRenderer.issue("Could not save the preview.")}
        try png.write(to:directory.appendingPathComponent("last-preview.png"),options:.atomic)
        try output.raster.write(to:directory.appendingPathComponent("last-preview.raster"),options:.atomic)
    }
    static func clipboard()throws->StickerContent {
        let clipboard=NSPasteboard.general
        if let urls=clipboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL],let url=urls.first{return try StickerRenderer.load(url)}
        if let image=NSImage(pasteboard:clipboard){return StickerContent(image:image)}
        if let text=clipboard.string(forType:.string),!text.isEmpty{return StickerContent(text:text)}
        throw StickerRenderer.issue("Copy an image, file, or text first.")
    }
    static func pairingPage()throws->URL {
        let link=try String(contentsOf:directory.appendingPathComponent("phone-link.txt"),encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines)
        guard !link.isEmpty,let filter=CIFilter(name:"CIQRCodeGenerator") else{throw StickerRenderer.issue("The phone bridge has not started yet.")}
        filter.setValue(link.data(using:.utf8),forKey:"inputMessage");filter.setValue("M",forKey:"inputCorrectionLevel")
        guard let code=filter.outputImage?.transformed(by:CGAffineTransform(scaleX:8,y:8)),let cg=CIContext().createCGImage(code,from:code.extent),let data=StickerImage.pngData(StickerImage.platformImage(cg)) else{throw StickerRenderer.issue("Could not create pairing QR.")}
        let html="""
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>Pair iPhone with S1</title><style>body{font:19px system-ui;background:#f4f2ec;color:#203a2d;text-align:center;padding:40px}main{max-width:520px;margin:auto}img{width:310px;max-width:90%;image-rendering:pixelated;border:22px solid white;border-radius:16px}p{line-height:1.5}a{color:#203a2d}</style><main><h1>Your phone → your S1</h1><p>Use the same Wi-Fi, then scan this private QR with Camera.</p><img src="data:image/png;base64,\(data.base64EncodedString())"><p>In Safari, tap Share → Add to Home Screen.</p><p>Keep this Mac awake and the printer nearby.</p><p><a href="\(link)">Open printer page on this Mac</a></p><small>This QR grants access to your printer. Keep it private.</small></main>
        """
        let url=directory.appendingPathComponent("phone-setup.html");try html.write(to:url,atomically:true,encoding:.utf8)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
        return url
    }
}

final class FileLease {
    private let descriptor:Int32
    init(_ name:String,busyMessage:String="An AI sticker is already being prepared. Wait for it to finish.")throws {
        descriptor=open(S1Files.directory.appendingPathComponent(name).path,O_CREAT|O_RDWR,0o600)
        guard descriptor>=0 else{throw StickerRenderer.issue("Cannot open the printer job lock.")}
        guard flock(descriptor,LOCK_EX|LOCK_NB)==0 else{close(descriptor);throw StickerRenderer.issue(busyMessage)}
    }
    deinit{flock(descriptor,LOCK_UN);close(descriptor)}
}
