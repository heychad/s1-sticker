import Foundation

public enum PrinterProtocol {
    public static let identity=Data([0x1b,0x12,0x64])
    public static let statusQuery=Data([0x1b,0x12,0x73])
    public static func encode(_ raster:Data,feedRows:Int=PrintFormat.feedRows)throws->Data {
        guard (0...160).contains(feedRows) else{throw StickerRenderer.issue("Finishing feed must be between 0 and 20 mm.")}
        guard !raster.isEmpty,raster.count%48==0,raster.count<=48*PrintFormat.maximumRows else{throw StickerRenderer.issue("Invalid raster: expected a 384-dot-wide sticker up to 300 mm long.")}
        var result=Data();result.reserveCapacity(raster.count+2048)
        func little(_ value:Int,_ count:Int)->[UInt8]{(0..<count).map{UInt8(truncatingIfNeeded:value >> ($0*8))}}
        for offset in stride(from:0,to:raster.count,by:1536) {
            let length=min(1536,raster.count-offset)
            var lzo=Data()
            if length<=238{lzo.append(UInt8(length+17))}
            else{lzo.append(0);var remaining=length-18;while remaining>255{lzo.append(0);remaining-=255};lzo.append(UInt8(remaining))}
            let start=raster.startIndex+offset
            lzo.append(raster.subdata(in:start..<start+length));lzo.append(contentsOf:[0x11,0,0])
            result.append(contentsOf:[0x1d,0x76,0x30,0x30]);result.append(contentsOf:little(48,2));result.append(contentsOf:little(length/48,2));result.append(contentsOf:little(lzo.count,4));result.append(lzo)
        }
        result.append(contentsOf:[0x1b,0x1b,0x01]);result.append(contentsOf:little(feedRows,2))
        return result
    }
    public static func status(_ data:Data)->(flags:Int,idle:Bool,battery:Int)? {
        let bytes=[UInt8](data)
        guard bytes.count>=17,let start=(0...(bytes.count-17)).last(where:{bytes[$0+14]==69&&bytes[$0+15]==78&&bytes[$0+16]==68}) else{return nil}
        return(Int(bytes[start])|(Int(bytes[start+1])<<8),bytes[start+2]==1,Int(bytes[start+3]))
    }
    public static func errors(_ flags:Int)->[String] {
        let names=["Out of paper","Print head too hot","Print head too cold","Battery too low","Cover open","Battery error","Paper positioning error"]
        return names.enumerated().filter{flags & (1 << $0.offset) != 0}.map(\.element)
    }
}
