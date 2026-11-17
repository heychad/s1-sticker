import UIKit
import CoreGraphics

struct VrettiOutput {
    let image: UIImage
    let packet: Data
}
struct VrettiInput: @unchecked Sendable {
    let text: String, image: UIImage?
    let dither: Bool, autoRotate: Bool, turns: Int, hasBlocks: Bool
}

enum VrettiPage {
    static let width = 812, height = 1218
    private enum Draw { case text(NSAttributedString, CGRect); case box(CGRect) }
    static func render(_ input: VrettiInput) throws -> VrettiOutput {
        guard !input.hasBlocks else { throw StickerRenderer.issue("Vretti does not yet support JSON layouts. Use text or an image.") }
        let rect = CGRect(x: 48, y: 48, width: width - 96, height: height - 96)
        let image: UIImage?
        if let source = input.image { image = try StickerImage.oriented(source, automatic: input.autoRotate, turns: input.turns) }
        else { image = nil }
        let text = input.text
        var draws: [Draw] = []
        if image == nil {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StickerRenderer.issue("Add text or an image first.") }
            var cursor = rect.minY
            func value(_ text:String,_ size:CGFloat,_ bold:Bool)->NSAttributedString {
                let paragraph=NSMutableParagraphStyle();paragraph.lineSpacing=3
                return NSAttributedString(string:text,attributes:[.font:UIFont.systemFont(ofSize:size,weight:bold ? .bold:.regular),.foregroundColor:UIColor.black,.paragraphStyle:paragraph])
            }
            func measured(_ value:NSAttributedString,_ width:CGFloat)->CGFloat {
                max(24,ceil(value.boundingRect(with:CGSize(width:width,height:.greatestFiniteMagnitude),options:[.usesLineFragmentOrigin,.usesFontLeading],context:nil).height))
            }
            for block in try LabelMarkup.parse(text) {
                switch block {
                case .text(let line,let heading):
                    let v=value(line,heading == 1 ? 44 : heading == 2 ? 36 : 32,heading>0)
                    let h=line.isEmpty ? CGFloat(16) : measured(v,rect.width)
                    guard cursor+h <= rect.maxY else {throw StickerRenderer.issue("Text exceeds one 4×6 label; shorten it before printing.")}
                    if !line.isEmpty {draws.append(.text(v,CGRect(x:rect.minX,y:cursor,width:rect.width,height:h)))}
                    cursor += h+8
                case .table(let rows):
                    let cellWidth=rect.width/CGFloat(rows[0].count)
                    for (rowIndex,row) in rows.enumerated() {
                        let cells=row.map{value($0,27,rowIndex==0)}
                        let h=(cells.map{measured($0,cellWidth-16)}.max() ?? 24)+16
                        guard cursor+h <= rect.maxY else {throw StickerRenderer.issue("Table exceeds one 4×6 label; shorten it before printing.")}
                        for (column,cell) in cells.enumerated() {
                            let box=CGRect(x:rect.minX+CGFloat(column)*cellWidth,y:cursor,width:cellWidth,height:h)
                            draws.append(.box(box));draws.append(.text(cell,box.insetBy(dx:8,dy:8)))
                        }
                        cursor += h
                    }
                    cursor += 12
                }
            }
        }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let canvas = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            if let image {
                let scale = min(rect.width / image.size.width, rect.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: rect.midX-size.width/2, y: rect.midY-size.height/2, width: size.width, height: size.height))
            } else {
                for draw in draws {switch draw {
                case .text(let value,let frame):value.draw(in:frame)
                case .box(let frame):UIColor.black.setStroke();let border=UIBezierPath(rect:frame);border.lineWidth=1.5;border.stroke()
                }}
            }
        }
        guard let cg = canvas.cgImage else { throw StickerRenderer.issue("Could not render the label.") }
        let w=width, h=height, stride=(w+7)/8
        var pixels=[UInt8](repeating:255,count:w*h)
        guard let ctx=CGContext(data:&pixels,width:w,height:h,bitsPerComponent:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else { throw StickerRenderer.issue("Could not prepare the preview.") }
        ctx.draw(cg,in:CGRect(x:0,y:0,width:w,height:h))
        var raster=Data(repeating:0,count:stride*h), errors=[Double](repeating:0,count:w+2), next=errors
        for y in 0..<h {
            for x in 0..<w {
                let value=min(255,max(0,Double(pixels[y*w+x])+(input.dither ? errors[x+1]:0)))
                let black=value<128
                if black {raster[y*stride+x/8] |= UInt8(0x80 >> (x%8))}
                pixels[y*w+x]=black ? 0:255
                if input.dither {let e=value-(black ? 0:255);errors[x+2]+=e*7/16;next[x]+=e*3/16;next[x+1]+=e*5/16;next[x+2]+=e/16}
            }
            errors=next;next=[Double](repeating:0,count:w+2)
        }
        guard let gray=CGContext(data:&pixels,width:w,height:h,bitsPerComponent:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue)?.makeImage() else { throw StickerRenderer.issue("Could not create the preview.") }
        var left=stride,right = -1,top=h,bottom = -1
        for y in 0..<h {for x in 0..<stride where raster[y*stride+x] != 0 {left=min(left,x);right=max(right,x);top=min(top,y);bottom=max(bottom,y)}}
        var packet=Data("^XA^PW812^LL1218".utf8)
        if right>=left && bottom>=top {
            let n=right-left+1,rows=max(1,60000/n)
            for start in Swift.stride(from:top,through:bottom,by:rows) {
                let end=min(bottom+1,start+rows);var block=Data()
                for y in start..<end {block.append(raster.subdata(in:(y*stride+left)..<(y*stride+right+1)))}
                packet.append(Data("^FO\(left*8),\(start)^GFA,\(block.count),\(block.count),\(n),".utf8))
                packet.append(Data(block.map{String(format:"%02X",$0)}.joined().utf8));packet.append(Data("^FS".utf8))
            }
        }
        packet.append(Data("^PQ1^XZ".utf8))
        return VrettiOutput(image:UIImage(cgImage:gray),packet:packet)
    }
}
