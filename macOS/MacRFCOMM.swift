import Foundation
import IOBluetooth
import Darwin

private final class RFCOMMReceiver:NSObject,IOBluetoothRFCOMMChannelDelegate {
    var received=Data()
    func rfcommChannelData(_ rfcommChannel:IOBluetoothRFCOMMChannel!,data dataPointer:UnsafeMutableRawPointer!,length dataLength:Int){received.append(dataPointer.assumingMemoryBound(to:UInt8.self),count:dataLength)}
}

enum MacRFCOMM {
    /// IOBluetooth's synchronous open pumps callbacks. Run it as a run-loop
    /// block after the Swift task yields, never inside an active actor job.
    @MainActor static func perform(raster:Data?=nil,feedRows:Int=PrintFormat.feedRows,keepAliveDuration:Double?=nil,keepAliveInterval:Double=60)async->[String:Any] {
        await withCheckedContinuation{continuation in
            CFRunLoopPerformBlock(CFRunLoopGetMain(),CFRunLoopMode.defaultMode.rawValue){continuation.resume(returning:run(raster:raster,feedRows:feedRows,keepAliveDuration:keepAliveDuration,keepAliveInterval:keepAliveInterval))}
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
    }
    static func run(raster:Data?=nil,feedRows:Int=PrintFormat.feedRows,keepAliveDuration:Double?=nil,keepAliveInterval:Double=60)->[String:Any] {
        // Foreground requests hold this lease until their transaction completes.
        // The keep-awake session watches it and yields its channel promptly.
        let intent=open(S1Files.directory.appendingPathComponent("printer-intent.lock").path,O_CREAT|O_RDWR,0o600)
        guard intent>=0 else{return failure("Cannot open the printer request lock.")}
        defer{close(intent)}
        if keepAliveDuration == nil {
            let deadline=ProcessInfo.processInfo.systemUptime+15
            while flock(intent,LOCK_EX|LOCK_NB) != 0 {
                if ProcessInfo.processInfo.systemUptime>=deadline{return failure("The S1 is handling another request. Try again in a moment.")}
                spin(0.1)
            }
        }
        defer{if keepAliveDuration == nil {flock(intent,LOCK_UN)}}
        let path=S1Files.directory.appendingPathComponent("printer.lock").path
        let lock=open(path,O_CREAT|O_RDWR,0o600)
        guard lock>=0 else{return failure("Cannot open the printer lock.")}
        let lockDeadline=ProcessInfo.processInfo.systemUptime+15
        while flock(lock,LOCK_EX|LOCK_NB) != 0 {
            if keepAliveDuration != nil || ProcessInfo.processInfo.systemUptime>=lockDeadline {close(lock);return failure("The S1 is handling another request. Try again in a moment.")}
            spin(0.1)
        }
        defer{flock(lock,LOCK_UN);close(lock)}
        guard let device=(IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice])?.first(where:{$0.name?.hasPrefix("S1-")==true}) else{return failure("Pair the S1 in System Settings → Bluetooth, then try again.")}
        var channelID:BluetoothRFCOMMChannelID=0
        for service in device.services as? [IOBluetoothSDPServiceRecord] ?? [] {
            var found:BluetoothRFCOMMChannelID=0
            if service.getRFCOMMChannelID(&found)==kIOReturnSuccess,found>0,(channelID==0||found<channelID){channelID=found}
        }
        guard channelID>0 else{return failure("Reconnect the S1 in Bluetooth settings to discover its printing service.")}
        let receiver=RFCOMMReceiver();var channel:IOBluetoothRFCOMMChannel?
        func openChannel()->IOReturn {
            if !device.isConnected() {
                let linkResult=device.openConnection()
                guard linkResult==kIOReturnSuccess || device.isConnected() else{return linkResult}
            }
            return device.openRFCOMMChannelSync(&channel,withChannelID:channelID,delegate:receiver)
        }
        var result=openChannel()
        if result != kIOReturnSuccess || channel?.isOpen() != true {
            channel?.close();device.closeConnection();spin(0.3);channel=nil
            result=openChannel()
        }
        guard result==kIOReturnSuccess,let channel,channel.isOpen() else{device.closeConnection();var error=failure("Cannot connect. Turn on the S1 and disconnect printing apps on your phone.");error["connectionCode"]=Int(result);return error}
        defer{channel.close();device.closeConnection()}
        func query(_ command:Data,count:Int)->Data? {
            receiver.received.removeAll(keepingCapacity:true)
            let written=command.withUnsafeBytes{channel.writeSync(UnsafeMutableRawPointer(mutating:$0.baseAddress!),length:UInt16($0.count))}
            guard written==kIOReturnSuccess else{return nil}
            let deadline=Date().addingTimeInterval(3)
            while receiver.received.count<count,deadline>Date(){spin(0.02)}
            return receiver.received.count>=count ? receiver.received:nil
        }
        func readStatus()->(flags:Int,idle:Bool,battery:Int)? {query(PrinterProtocol.statusQuery,count:17).flatMap(PrinterProtocol.status)}
        guard let identity=query(PrinterProtocol.identity,count:143),identity.prefix(3)==Data([0x53,0x31,0]) else{return failure("The connected device did not identify as an S1. Nothing printed.")}
        guard let before=readStatus() else{return failure("The S1 did not return valid status. Nothing printed.")}
        var response:[String:Any]=["ok":true,"flags":before.flags,"idle":before.idle ? 1:0,"battery":before.battery,"printer":device.name ?? "S1","errors":PrinterProtocol.errors(before.flags)]
        if let duration=keepAliveDuration {
            let deadline=ProcessInfo.processInfo.systemUptime+duration
            var checks=1
            print("Status check 1: connected; battery \(before.battery)%");fflush(stdout)
            while ProcessInfo.processInfo.systemUptime<deadline {
                let next=min(deadline,ProcessInfo.processInfo.systemUptime+keepAliveInterval)
                while ProcessInfo.processInfo.systemUptime<next {
                    if flock(intent,LOCK_EX|LOCK_NB) != 0 {return ["ok":true,"sent":false,"handoff":true,"checks":checks]}
                    flock(intent,LOCK_UN)
                    spin(min(0.2,next-ProcessInfo.processInfo.systemUptime))
                }
                if ProcessInfo.processInfo.systemUptime>=deadline {break}
                guard let status=readStatus() else {
                    var failed=failure("Keep-alive stopped: no valid status response.");failed["checks"]=checks;return failed
                }
                checks+=1
                print("Status check \(checks): connected; battery \(status.battery)%");fflush(stdout)
            }
            return ["ok":true,"sent":false,"checks":checks,"message":"Keep-alive finished. No print job sent."]
        }
        guard let raster else{response["message"]="Connected";return response}
        guard before.flags==0 else{return failure(PrinterProtocol.errors(before.flags).joined(separator:" · "))}
        guard before.idle else{return failure("The S1 is busy. Wait for the current print to finish.")}
        let packet:Data
        do{packet=try PrinterProtocol.encode(raster,feedRows:feedRows)}catch{return failure(error.localizedDescription)}
        var offset=0
        while offset<packet.count {
            let count=min(min(Int(channel.getMTU()),512),packet.count-offset)
            guard count>0 else{return failure("Bluetooth reported an invalid packet size.")}
            let written=packet.withUnsafeBytes{channel.writeSync(UnsafeMutableRawPointer(mutating:$0.baseAddress!.advanced(by:offset)),length:UInt16(count))}
            guard written==kIOReturnSuccess else{return ["ok":false,"sent":true,"message":"Bluetooth disconnected during printing. Check the sticker; it was not resent."]}
            offset+=count;spin(0.015)
        }
        spin(0.5);let deadline=Date().addingTimeInterval(50);var after=readStatus()
        while let status=after,!status.idle,status.flags==0,Date()<deadline{spin(0.4);after=readStatus()}
        response["sent"]=true
        if let after {
            response["flags"]=after.flags;response["idle"]=after.idle ? 1:0;response["battery"]=after.battery
            if after.flags != 0 {response["ok"]=false;response["message"]="Sent, but printer reports: "+PrinterProtocol.errors(after.flags).joined(separator:" · ")}
            else{response["message"]=after.idle ? "Sticker sent · printer is ready":"Sticker sent · check the printer"}
        }else{response["message"]="Sticker sent · check the printer"}
        return response
    }
    private static func spin(_ seconds:Double){RunLoop.current.run(until:Date().addingTimeInterval(seconds))}
    private static func failure(_ message:String)->[String:Any]{["ok":false,"sent":false,"message":message]}
}
