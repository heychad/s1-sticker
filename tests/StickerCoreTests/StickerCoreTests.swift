import XCTest
import CoreGraphics
@testable import StickerCore

final class StickerCoreTests:XCTestCase {
    func testVrettiMarkupKeepsHeadingsChecksAndTableCells() throws {
        let parsed = try LabelMarkup.parse("# Header\n- [ ] Task\n| Item | Status |\n| --- | --- |\n| Printer | Ready |")
        XCTAssertEqual(parsed, [.text("Header", heading: 1), .text("☐ Task", heading: 0), .table([["Item", "Status"], ["Printer", "Ready"]])])
        XCTAssertThrowsError(try LabelMarkup.parse("| A | B | C | D |\n| --- | --- | --- | --- |"))
        XCTAssertThrowsError(try LabelMarkup.parse("| A | B |\n| --- | --- |\n| only one |"))
    }
    func testProtocolRoundTripAndFeed()throws {
        for rows in [1,4,31,32,33,2400] {
            let input=Data((0..<(rows*48)).map{UInt8(truncatingIfNeeded:$0*17)})
            let encoded=try PrinterProtocol.encode(input)
            XCTAssertEqual(encoded.suffix(5),Data([0x1b,0x1b,1,80,0]))
            var position=0,decoded=Data()
            let bytes=[UInt8](encoded)
            func read(_ at:Int,_ count:Int)->Int{(0..<count).reduce(0){$0|(Int(bytes[at+$1])<<($1*8))}}
            while position<encoded.count-5 {
                XCTAssertEqual(Array(bytes[position..<position+4]),[0x1d,0x76,0x30,0x30])
                XCTAssertEqual(read(position+4,2),48)
                let height=read(position+6,2),length=read(position+8,4)
                let end=position+12+length
                var p=position+12,n=0
                if bytes[p]>17{n=Int(bytes[p])-17;p+=1}
                else{p+=1;while bytes[p]==0{n+=255;p+=1};n+=18+Int(bytes[p]);p+=1}
                XCTAssertEqual(n,height*48)
                decoded.append(contentsOf:bytes[p..<p+n]);p+=n
                XCTAssertEqual(Array(bytes[p..<end]),[0x11,0,0])
                position=end
            }
            XCTAssertEqual(decoded,input)
        }
        XCTAssertThrowsError(try PrinterProtocol.encode(Data()))
        XCTAssertThrowsError(try PrinterProtocol.encode(Data(count:49)))
        XCTAssertThrowsError(try PrinterProtocol.encode(Data(count:48*2401)))
        var sliced=Data(repeating:19,count:96)
        sliced.removeFirst(48)
        XCTAssertEqual(try PrinterProtocol.encode(sliced),try PrinterProtocol.encode(Data(repeating:19,count:48)))
    }
    func testStatusParsing() {
        var status=Data([0,0,1,92]+[UInt8](repeating:0,count:10)+[69,78,68])
        status.insert(contentsOf:[255,254],at:0)
        let parsed=PrinterProtocol.status(status)
        XCTAssertEqual(parsed?.battery,92);XCTAssertEqual(parsed?.flags,0);XCTAssertEqual(parsed?.idle,true)
        XCTAssertNil(PrinterProtocol.status(Data([0,1])))
    }
    func testOrientationPolicy() {
        XCTAssertEqual(PrintFormat.quarterTurns(width:200,height:100,automatic:true,manual:0),1)
        XCTAssertEqual(PrintFormat.quarterTurns(width:100,height:200,automatic:true,manual:0),0)
        XCTAssertEqual(PrintFormat.quarterTurns(width:100,height:100,automatic:true,manual:3),0)
        XCTAssertEqual(PrintFormat.quarterTurns(width:200,height:100,automatic:false,manual:-1),3)
    }
    func testDitheringAndLimits()throws {
        let pixels=Data((0..<(384*200)).flatMap{_ in [UInt8(128),128,128,255]})
        let provider=try XCTUnwrap(CGDataProvider(data:pixels as CFData))
        let gray=try XCTUnwrap(CGImage(width:384,height:200,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:384*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent))
        let output=try StickerRaster.monochrome(gray,dither:true)
        let count=output.raster.reduce(0){$0+$1.nonzeroBitCount}
        XCTAssertEqual(Double(count)/Double(384*200),0.5,accuracy:0.03)
        XCTAssertEqual(output.raster.count,48*200)
        XCTAssertThrowsError(try StickerRenderer.render(text:"",image:nil,dither:false))
    }
    func testMarkdownAndJSON()throws {
        let table=try StickerRenderer.render(text:"# Ready\n\n| Item | Status |\n| --- | --- |\n| Printer | Ready |",image:nil,dither:false)
        XCTAssertGreaterThan(table.height,60);XCTAssertLessThan(table.height,400)
        XCTAssertEqual(table.raster.count,48*table.height)
        let numeric=try StickerRenderer.render(StickerContent(blocks:[["type":"table","headers":["Item","Qty"],"rows":[["Stickers",12]]]]),dither:false)
        XCTAssertGreaterThan(numeric.height,48)
        XCTAssertThrowsError(try StickerRenderer.render(StickerContent(blocks:[["type":"table","headers":["a","b"],"rows":[["one"]]]]),dither:false))
    }
    func testTrimsOnlyLeadingEmptyRows()throws {
        let pixels=Data((0..<(384*40)).flatMap{index -> [UInt8] in
            let value:UInt8=index/384==16 ? 0:255
            return [value,value,value,255]
        })
        let provider=try XCTUnwrap(CGDataProvider(data:pixels as CFData))
        let image=try XCTUnwrap(CGImage(width:384,height:40,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:384*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent))
        let output=try StickerRaster.monochrome(image,dither:false)
        XCTAssertEqual(output.image.height,24)
        XCTAssertEqual(output.raster.count,48*24)
        XCTAssertEqual(output.raster.firstIndex(where:{$0 != 0}),0)
        XCTAssertTrue(output.raster.prefix(48).allSatisfy{$0==255})
        XCTAssertEqual(output.raster.filter{$0 != 0}.count,48)
        XCTAssertEqual(output.raster.startIndex,0)
        XCTAssertNoThrow(try PrinterProtocol.encode(output.raster))
    }
    func testCalibrationDimensionsAndFeeds()throws {
        for (name,leading,feed) in [("A",0,56),("B",4,56),("C",4,72),("D",24,56),("E",8,80)] {
            let sample=try PrintCalibration.sample(name)
            XCTAssertEqual(sample.output.height,192+leading)
            XCTAssertEqual(sample.feedRows,feed)
            XCTAssertEqual(sample.output.raster.firstIndex(where:{$0 != 0}).map{$0/48},leading)
            XCTAssertEqual(try PrinterProtocol.encode(sample.output.raster,feedRows:feed).suffix(2),Data([UInt8(feed),0]))
            if name=="E" {
                XCTAssertEqual(sample.output.raster[leading*48],255)
                XCTAssertEqual(sample.output.raster[leading*48+47],255)
            }
        }
    }
}
