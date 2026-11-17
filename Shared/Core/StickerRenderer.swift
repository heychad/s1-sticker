import Foundation
import CoreGraphics
import PDFKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

public struct StickerOutput:@unchecked Sendable {
    public let image:StickerPlatformImage
    public let raster:Data
    public let height:Int
    public var sourceSize:CGSize = .zero
    public var quarterTurns:Int = 0
}

// A render job owns this value snapshot; its platform image is read-only.
public struct StickerContent:@unchecked Sendable {
    public var text:String=""
    public var image:StickerPlatformImage?
    public var blocks:[[String:Any]]?
    public init(text:String="",image:StickerPlatformImage?=nil,blocks:[[String:Any]]?=nil){self.text=text;self.image=image;self.blocks=blocks}
}

public enum StickerRenderer {
    public static func issue(_ message:String)->NSError {NSError(domain:"S1Sticker",code:1,userInfo:[NSLocalizedDescriptionKey:message])}

    public static func load(_ url:URL)throws->StickerContent {
        let ext=url.pathExtension.lowercased()
        if ext=="json" {
            let data=try Data(contentsOf:url)
            guard let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],var blocks=root["blocks"] as? [[String:Any]] else{throw issue("The sticker JSON must contain a blocks array.")}
            for i in blocks.indices {if let path=blocks[i]["path"] as? String,!path.hasPrefix("/"){blocks[i]["path"]=url.deletingLastPathComponent().appendingPathComponent(path).path}}
            return StickerContent(blocks:blocks)
        }
        if ["txt","md","markdown"].contains(ext){return StickerContent(text:try String(contentsOf:url,encoding:.utf8))}
        if ext=="pdf" {
            guard let document=PDFDocument(url:url),let page=document.page(at:0) else{throw issue("This PDF has no readable first page.")}
            let size=page.bounds(for:.cropBox).size
            return StickerContent(image:page.thumbnail(of:CGSize(width:768,height:768*size.height/size.width),for:.cropBox))
        }
        if let image=StickerImage.decode(url){return StickerContent(image:image)}
        throw issue("Choose an image, PDF, Markdown, text, or sticker JSON file.")
    }

    public static func render(text:String,image:StickerPlatformImage?,dither:Bool,autoRotate:Bool=true,turns:Int=0)throws->StickerOutput {
        try render(StickerContent(text:text,image:image),dither:dither,autoRotate:autoRotate,turns:turns)
    }

    public static func render(_ content:StickerContent,dither:Bool,autoRotate:Bool=true,turns:Int=0,allowWide:Bool=false)throws->StickerOutput {
        if let image=content.image {
            guard image.size.width>0,image.size.height>0 else{throw issue("The image has no printable size.")}
            let rotation=PrintFormat.quarterTurns(width:image.size.width,height:image.size.height,automatic:autoRotate,manual:turns)
            let oriented=try StickerImage.oriented(image,automatic:autoRotate,turns:turns)
            let maxHeight = rotation % 2 == 1 && !allowWide ? PrintFormat.notebookSidewaysMaxRows-PrintFormat.feedRows : nil
            var output=try renderBlocks([["type":"image","image":oriented]],dither:dither,maxImageRows:maxHeight)
            output.sourceSize=image.size;output.quarterTurns=rotation;return output
        }
        if let blocks=content.blocks{return try renderBlocks(blocks,dither:dither)}
        guard !content.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{throw issue("Add text or an image first.")}
        return try renderBlocks(markdown(content.text),dither:dither)
    }

    private static func cells(_ line:String)->[String] {
        var line=line.trimmingCharacters(in:.whitespaces)
        if line.hasPrefix("|"){line.removeFirst()};if line.hasSuffix("|"){line.removeLast()}
        return line.components(separatedBy:"|").map{$0.trimmingCharacters(in:.whitespaces)}
    }
    private static func markdown(_ text:String)->[[String:Any]] {
        let lines=text.components(separatedBy:.newlines);var blocks:[[String:Any]]=[];var i=0
        while i<lines.count {
            var line=lines[i]
            if line.contains("|"),i+1<lines.count,lines[i+1].contains("---") {
                let headers=cells(line);var rows:[[String]]=[];i+=2
                while i<lines.count,lines[i].contains("|"){rows.append(cells(lines[i]));i+=1}
                blocks.append(["type":"table","headers":headers,"rows":rows]);continue
            }
            if line.hasPrefix("# "){blocks.append(["type":"heading","text":String(line.dropFirst(2))])}
            else if line.hasPrefix("## "){blocks.append(["type":"subheading","text":String(line.dropFirst(3))])}
            else if line=="---"{blocks.append(["type":"divider"])}
            else {
                if line.hasPrefix("- [ ] "){line="☐ "+line.dropFirst(6)}
                else if line.hasPrefix("- [x] "){line="☑ "+line.dropFirst(6)}
                else if line.hasPrefix("- "){line="• "+line.dropFirst(2)}
                blocks.append(["type":"text","text":line])
            }
            i+=1
        }
        return blocks
    }

    private enum Draw {
        case text(String,CGRect,[NSAttributedString.Key:Any])
        case border(CGRect)
        case image(StickerPlatformImage,CGRect)
    }
    private static func style(_ size:CGFloat,bold:Bool=false,center:Bool=false)->[NSAttributedString.Key:Any] {
        let p=NSMutableParagraphStyle();p.lineBreakMode = .byWordWrapping;p.lineSpacing=3;p.alignment=center ? .center:.left
        return [.font:StickerFont.systemFont(ofSize:size,weight:bold ? .bold:.regular),.foregroundColor:StickerColor.black,.paragraphStyle:p]
    }
    private static func textHeight(_ text:String,attrs:[NSAttributedString.Key:Any],width:CGFloat)->CGFloat {
        ceil((text as NSString).boundingRect(with:CGSize(width:width,height:10000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attrs,context:nil).height)+3
    }
    private static func renderBlocks(_ blocks:[[String:Any]],dither:Bool,maxImageRows:Int?=nil)throws->StickerOutput {
        var draws:[Draw]=[];var y:CGFloat=12
        for block in blocks {
            let type=block["type"] as? String ?? "text"
            switch type {
            case "divider":draws.append(.border(CGRect(x:12,y:y+5,width:360,height:1)));y+=14
            case "image":
                let image=(block["image"] as? StickerPlatformImage) ?? (block["path"] as? String).flatMap{StickerImage.decode(URL(fileURLWithPath:$0))}
                guard let image,image.size.width>0,image.size.height>0 else{throw issue("A sticker image could not be read.")}
                let ratio=image.size.height/image.size.width
                let width=maxImageRows.map { min(CGFloat(384),CGFloat(max(1,$0-34))/ratio) } ?? 384
                let h=ceil(width*ratio)
                draws.append(.image(image,CGRect(x:(384-width)/2,y:y,width:width,height:h)));y+=h+10
            case "table":
                guard let rawHeaders=block["headers"] as? [Any],(1...4).contains(rawHeaders.count),let rawRows=block["rows"] as? [[Any]] else{throw issue("Use one to four short table columns.")}
                let headers=rawHeaders.map{String(describing:$0)},rows=rawRows.map{$0.map{String(describing:$0)}}
                let cw:CGFloat=360/CGFloat(headers.count)
                for (index,row) in ([headers]+rows).enumerated() {
                    guard row.count==headers.count else{throw issue("Table rows must match the number of columns.")}
                    let attrs=style(headers.count>2 ? 17:20,bold:index==0)
                    let h=max(24,row.map{textHeight($0,attrs:attrs,width:cw-12)+12}.max() ?? 24)
                    for (column,cell) in row.enumerated(){let rect=CGRect(x:12+CGFloat(column)*cw,y:y,width:cw,height:h);draws.append(.border(rect));draws.append(.text(cell,rect.insetBy(dx:6,dy:6),attrs))}
                    y+=h
                }
                y+=12
            case "text","heading","subheading":
                let text=block["text"] as? String ?? ""
                let requested=(block["size"] as? NSNumber)?.doubleValue
                let size:CGFloat=requested.map{min(48,max(16,$0))} ?? (type=="heading" ? 30:type=="subheading" ? 24:22)
                let attrs=style(size,bold:type != "text",center:block["align"] as? String=="center")
                let h=text.isEmpty ? 12:textHeight(text,attrs:attrs,width:360)
                draws.append(.text(text,CGRect(x:12,y:y,width:360,height:h),attrs));y+=h+(type=="heading" ? 10:5)
            default:throw issue("Unknown sticker block: \(type).")
            }
            guard y<=2388 else{throw issue("Split this into stickers shorter than 300 mm.")}
        }
        let height=max(48,Int(ceil(y+12)))
        let drawn=try StickerImage.canvas(size:CGSize(width:384,height:height)){context in
            context.setStrokeColor(CGColor(gray:0,alpha:1));context.setLineWidth(1)
            for draw in draws {
                switch draw {
                case .text(let text,let rect,let attrs):(text as NSString).draw(with:rect,options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attrs,context:nil)
                case .border(let rect):context.stroke(rect)
                case .image(let image,let rect):StickerImage.draw(image,in:rect)
                }
            }
        }
        let mono=try StickerRaster.monochrome(drawn,dither:dither)
        return StickerOutput(image:StickerImage.platformImage(mono.image),raster:mono.raster,height:mono.image.height)
    }
}
