import Foundation
import Combine

@MainActor final class MacPrinter:ObservableObject {
    @Published private(set) var busy=false
    @Published var message="Ready for your next sticker"
    func check(){run(["--status"])}
    func printOutput(_ output:StickerOutput) {
        guard !busy else{return}
        do {
            try S1Files.save(output)
            let url=S1Files.directory.appendingPathComponent(UUID().uuidString+".raster")
            try output.raster.write(to:url,options:.atomic);run(["--raw",url.path],temporary:url)
        }catch{message=error.localizedDescription}
    }
    private func run(_ arguments:[String],temporary:URL?=nil) {
        guard !busy else{return};busy=true;message="Connecting to S1…"
        let executable=Bundle.main.executableURL!
        DispatchQueue.global(qos:.userInitiated).async {
            defer{if let temporary{try? FileManager.default.removeItem(at:temporary)}}
            let task=Process(),pipe=Pipe();task.executableURL=executable;task.arguments=arguments;task.standardOutput=pipe;task.standardError=Pipe()
            var message="Could not connect. Check the S1 and try again."
            do {
                try task.run()
                DispatchQueue.global().asyncAfter(deadline:.now()+100){if task.isRunning{task.terminate()}}
                let data=pipe.fileHandleForReading.readDataToEndOfFile();task.waitUntilExit()
                if let result=try JSONSerialization.jsonObject(with:data) as? [String:Any],let text=result["message"] as? String{message=text;if let battery=result["battery"] as? Int{message+=" · \(battery)% battery"}}
            }catch{message=error.localizedDescription}
            let finalMessage=message
            DispatchQueue.main.async{self.busy=false;self.message=finalMessage}
        }
    }
}
