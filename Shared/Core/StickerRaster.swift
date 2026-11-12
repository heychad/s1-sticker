import Foundation
import CoreGraphics

public enum StickerRaster {
    /// Two error rows replace the old full-height floating-point image buffer.
    public static func monochrome(_ image:CGImage,dither:Bool,leadingBlankRows:Int=PrintFormat.leadingBlankRows)throws->(image:CGImage,raster:Data) {
        let width=image.width,height=image.height
        guard width==PrintFormat.width,height>0,height<=PrintFormat.maximumRows else{throw StickerRenderer.issue("The sticker must be 384 pixels wide and shorter than 300 mm.")}
        let colorSpace=CGColorSpaceCreateDeviceRGB()
        let info=CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue
        var rgba=[UInt8](repeating:255,count:width*height*4)
        let drawn=rgba.withUnsafeMutableBytes{memory->Bool in
            guard let context=CGContext(data:memory.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:colorSpace,bitmapInfo:info) else{return false}
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height));return true
        }
        guard drawn else{throw StickerRenderer.issue("Could not convert this sticker.")}
        var bits=Data(count:width/8*height)
        var current=[Float](repeating:0,count:width),next=current
        bits.withUnsafeMutableBytes{(buffer:UnsafeMutableRawBufferPointer) in
            let output=buffer.bindMemory(to:UInt8.self)
            for row in 0..<height {
                for column in 0..<width {
                    let p=(row*width+column)*4
                    let before=0.2126*Float(rgba[p])+0.7152*Float(rgba[p+1])+0.0722*Float(rgba[p+2])+(dither ? current[column]:0)
                    let value:UInt8=before<(dither ? 127.5:160) ? 0:255
                    if value==0{output[row*(width/8)+column/8] |= UInt8(1 << (7-column%8))}
                    rgba[p]=value;rgba[p+1]=value;rgba[p+2]=value;rgba[p+3]=255
                    if dither {
                        let error=before-Float(value)
                        if column+1<width{current[column+1]+=error*7/16}
                        if column>0{next[column-1]+=error*3/16}
                        next[column]+=error*5/16
                        if column+1<width{next[column+1]+=error/16}
                    }
                }
                swap(&current,&next)
                for column in 0..<width{next[column]=0}
            }
        }
        // Whitespace embedded in an imported image is paper advance too.
        // Remove only fully blank leading raster rows; add no top margin.
        let firstInk=bits.firstIndex(where:{$0 != 0}).map{$0/(width/8)}
        let trimmedRows=max(0,(firstInk ?? 0)-leadingBlankRows)
        let outputHeight=height-trimmedRows
        if trimmedRows>0{bits=Data(bits.dropFirst(trimmedRows*(width/8)))}
        let outputPixels=Data(rgba.dropFirst(trimmedRows*width*4))
        guard let provider=CGDataProvider(data:outputPixels as CFData),let mono=CGImage(width:width,height:outputHeight,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:colorSpace,bitmapInfo:CGBitmapInfo(rawValue:info),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else{throw StickerRenderer.issue("Could not prepare the preview.")}
        return(mono,bits)
    }
}
