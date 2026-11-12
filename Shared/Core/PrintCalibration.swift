import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

public enum PrintCalibration {
    public static func sample(_ name:String)throws->(output:StickerOutput,feedRows:Int) {
        let id=name.uppercased()
        let settings=["A":(0,56),"B":(4,56),"C":(4,72),"D":(24,56),"E":(8,80)]
        guard let (leading,feed)=settings[id] else{throw StickerRenderer.issue("Choose calibration A, B, C, D, or E.")}
        let leadingLabel=String(format:"%g",Double(leading)/8)
        let inset=id=="E" ? 0:8
        let frameWidth=id=="E" ? 48:46
        let contentHeight=192
        let height=contentHeight+leading
        let image=try StickerImage.canvas(size:CGSize(width:384,height:height)){cg in
            cg.setStrokeColor(CGColor(gray:0,alpha:1));cg.setLineWidth(1)
            // E reaches both printhead edges; earlier samples keep 1 mm inset.
            cg.stroke(CGRect(x:CGFloat(inset)+0.5,y:CGFloat(leading)+0.5,width:CGFloat(383-2*inset),height:191))
            for mm in 1..<frameWidth {
                let x=CGFloat(inset+mm*8)+0.5
                let length:CGFloat=mm%5==0 ? 10:5
                cg.move(to:CGPoint(x:x,y:CGFloat(leading)));cg.addLine(to:CGPoint(x:x,y:CGFloat(leading)+length));cg.strokePath()
            }
            let title:[NSAttributedString.Key:Any]=[.font:StickerFont.boldSystemFont(ofSize:26),.foregroundColor:StickerColor.black]
            let text:[NSAttributedString.Key:Any]=[.font:StickerFont.systemFont(ofSize:18),.foregroundColor:StickerColor.black]
            ("CALIBRATION \(id)" as NSString).draw(at:CGPoint(x:22,y:CGFloat(leading+22)),withAttributes:title)
            ("Lead \(leadingLabel) mm | Post \(feed/8) mm" as NSString).draw(at:CGPoint(x:22,y:CGFloat(leading+64)),withAttributes:text)
            ("Frame: \(frameWidth) × 24 mm" as NSString).draw(at:CGPoint(x:22,y:CGFloat(leading+100)),withAttributes:text)
            ("1 mm ticks · cut at normal edge" as NSString).draw(at:CGPoint(x:22,y:CGFloat(leading+137)),withAttributes:text)
        }
        let mono=try StickerRaster.monochrome(image,dither:false,leadingBlankRows:leading)
        return(StickerOutput(image:StickerImage.platformImage(mono.image),raster:mono.raster,height:mono.image.height),feed)
    }
}
