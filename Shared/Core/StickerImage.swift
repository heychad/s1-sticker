import Foundation
import CoreGraphics
import ImageIO
#if canImport(UIKit)
import UIKit
public typealias StickerPlatformImage=UIImage
typealias StickerFont=UIFont
typealias StickerColor=UIColor
#else
import AppKit
public typealias StickerPlatformImage=NSImage
typealias StickerFont=NSFont
typealias StickerColor=NSColor
#endif

public enum StickerImage {
    public static func decode(_ data:Data)->StickerPlatformImage? {
        guard let source=CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary) else{return nil}
        return thumbnail(source)
    }
    public static func decode(_ url:URL)->StickerPlatformImage? {
        guard let source=CGImageSourceCreateWithURL(url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary) else{return nil}
        return thumbnail(source)
    }
    private static func thumbnail(_ source:CGImageSource)->StickerPlatformImage? {
        let options:[CFString:Any]=[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:1536,kCGImageSourceShouldCacheImmediately:true]
        guard let image=CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary) else{return nil}
        return platformImage(image)
    }
    public static func platformImage(_ image:CGImage)->StickerPlatformImage {
        #if canImport(UIKit)
        return UIImage(cgImage:image)
        #else
        return NSImage(cgImage:image,size:CGSize(width:image.width,height:image.height))
        #endif
    }
    public static func cgImage(_ image:StickerPlatformImage)->CGImage? {
        #if canImport(UIKit)
        return image.cgImage
        #else
        return image.cgImage(forProposedRect:nil,context:nil,hints:nil)
        #endif
    }
    public static func pngData(_ image:StickerPlatformImage)->Data? {
        guard let cg=cgImage(image) else{return nil}
        let data=NSMutableData()
        guard let destination=CGImageDestinationCreateWithData(data,"public.png" as CFString,1,nil) else{return nil}
        CGImageDestinationAddImage(destination,cg,nil)
        return CGImageDestinationFinalize(destination) ? data as Data:nil
    }
    public static func oriented(_ image:StickerPlatformImage,automatic:Bool,turns:Int)throws->StickerPlatformImage {
        let rotation=PrintFormat.quarterTurns(width:image.size.width,height:image.size.height,automatic:automatic,manual:turns)
        guard rotation != 0 else{return image}
        let size=rotation%2==1 ? CGSize(width:image.size.height,height:image.size.width):image.size
        return platformImage(try canvas(size:size){context in
            context.translateBy(x:size.width/2,y:size.height/2)
            context.rotate(by:CGFloat(rotation) * .pi / 2)
            draw(image,in:CGRect(x:-image.size.width/2,y:-image.size.height/2,width:image.size.width,height:image.size.height))
        })
    }
    static func draw(_ image:StickerPlatformImage,in rect:CGRect) {
        #if canImport(UIKit)
        image.draw(in:rect)
        #else
        image.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])
        #endif
    }
    static func canvas(size:CGSize,draw:(CGContext)->Void)throws->CGImage {
        #if canImport(UIKit)
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
        let image=UIGraphicsImageRenderer(size:size,format:format).image{context in
            UIColor.white.setFill();context.fill(CGRect(origin:.zero,size:size));draw(context.cgContext)
        }
        guard let cg=image.cgImage else{throw StickerRenderer.issue("Could not draw this sticker.")};return cg
        #else
        guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width),pixelsHigh:Int(size.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:Int(size.width)*4,bitsPerPixel:32),let graphics=NSGraphicsContext(bitmapImageRep:bitmap) else{throw StickerRenderer.issue("Could not draw this sticker.")}
        NSGraphicsContext.saveGraphicsState();defer{NSGraphicsContext.restoreGraphicsState()}
        let cg=graphics.cgContext
        cg.setFillColor(CGColor(gray:1,alpha:1));cg.fill(CGRect(origin:.zero,size:size))
        cg.translateBy(x:0,y:size.height);cg.scaleBy(x:1,y:-1)
        NSGraphicsContext.current=NSGraphicsContext(cgContext:cg,flipped:true)
        draw(cg)
        guard let image=bitmap.cgImage else{throw StickerRenderer.issue("Could not draw this sticker.")};return image
        #endif
    }
}
