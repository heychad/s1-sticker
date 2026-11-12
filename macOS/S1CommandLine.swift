import Foundation
import AppKit
import Darwin

@MainActor enum S1CommandLine {
    static func run(_ args:[String])async->Int32 {
        do {
            let mode=args[1]
            func value(_ option:String)->String?{guard let i=args.firstIndex(of:option),i+1<args.count else{return nil};return args[i+1]}
            let rotation=value("--rotate") ?? "auto"
            guard ["auto","0","90","180","270"].contains(rotation) else{throw StickerRenderer.issue("Use --rotate auto, 0, 90, 180, or 270.")}
            let automatic=rotation=="auto",turns=(Int(rotation) ?? 0)/90
            if mode=="--calibrate" {
                guard args.count>2 else{throw StickerRenderer.issue("Choose calibration A, B, C, D, or E.")}
                let sample=try PrintCalibration.sample(args[2])
                if let path=value("--output"),let png=StickerImage.pngData(sample.output.image){try png.write(to:URL(fileURLWithPath:path),options:.atomic)}
                if args.contains("--preview-only"){return finish(["ok":true,"sent":false,"message":"Calibration preview ready","height":sample.output.height,"feedRows":sample.feedRows])}
                try S1Files.save(sample.output)
                return finish(await MacRFCOMM.perform(raster:sample.output.raster,feedRows:sample.feedRows))
            }
            if mode=="--status"{return finish(await MacRFCOMM.perform())}
            if mode=="--keep-awake" {
                let durationText=value("--duration") ?? "3600"
                let intervalText=value("--interval") ?? "60"
                guard let duration=Int(durationText),(1...86400).contains(duration),
                      let interval=Int(intervalText),(15...300).contains(interval) else {
                    throw StickerRenderer.issue("Use --duration 1…86400 and --interval 15…300 (seconds).")
                }
                let keepAliveLease=try FileLease("keep-awake.lock",busyMessage:"An S1 keep-alive session is already running.")
                defer{withExtendedLifetime(keepAliveLease){}}
                print("Experimental S1 keep-alive: status only. Keep plugged in. Ctrl-C stops; stop before using your phone.")
                fflush(stdout)
                let deadline=ProcessInfo.processInfo.systemUptime+Double(duration)
                var checks=0
                var reconnectFailures=0
                while ProcessInfo.processInfo.systemUptime<deadline {
                    let result=await MacRFCOMM.perform(keepAliveDuration:deadline-ProcessInfo.processInfo.systemUptime,keepAliveInterval:Double(interval))
                    checks += result["checks"] as? Int ?? 0
                    if result["handoff"] as? Bool == true {
                        reconnectFailures=0
                        print("Printer request detected; yielding connection.");fflush(stdout)
                        let intent=open(S1Files.directory.appendingPathComponent("printer-intent.lock").path,O_CREAT|O_RDWR,0o600)
                        guard intent>=0 else{return finish(["ok":false,"sent":false,"message":"Cannot wait for the printer request."])}
                        while flock(intent,LOCK_EX|LOCK_NB) != 0 && ProcessInfo.processInfo.systemUptime<deadline {
                            try await Task.sleep(nanoseconds:200_000_000)
                        }
                        flock(intent,LOCK_UN);close(intent)
                        if ProcessInfo.processInfo.systemUptime<deadline {try await Task.sleep(nanoseconds:500_000_000)}
                        continue
                    }
                    if result["ok"] as? Bool != true {
                        reconnectFailures += 1
                        if reconnectFailures>=3{return finish(result)}
                        print("Status connection failed; retrying without sending a print job.");fflush(stdout)
                        try await Task.sleep(nanoseconds:5_000_000_000)
                        continue
                    }
                    break
                }
                return finish(["ok":true,"sent":false,"checks":checks,"message":"Keep-alive finished. No print job sent."])
            }
            if mode=="--pairing-page"{let url=try S1Files.pairingPage();return finish(["ok":true,"path":url.path])}
            if mode=="--raw"{
                guard args.count>2 else{throw StickerRenderer.issue("Specify a raster file.")}
                return finish(await MacRFCOMM.perform(raster:try Data(contentsOf:URL(fileURLWithPath:args[2]))))
            }
            var content:StickerContent
            var dither=args.contains("--dither")
            var lease:FileLease?
            if mode=="--ai-image"||mode=="--ai-text" {
                guard args.count>2,!args[2].isEmpty,args[2].count<=4000 else{throw StickerRenderer.issue("Describe the sticker in 1–4,000 characters.")}
                let preview=args.contains("--preview-only")
                guard !preview||value("--output") != nil else{throw StickerRenderer.issue("Preview requires --output PNG.")}
                lease=try FileLease("ai-job.lock")
                let client=OpenAIStickerClient()
                guard client.configured else{throw StickerRenderer.issue("Add your API key in S1 Sticker → AI settings first.")}
                if args.contains("--compact") {
                    print(preview ? "Making your sticker…":"Making and printing your sticker…")
                    fflush(stdout)
                }
                if !preview{var status=await MacRFCOMM.perform();if status["ok"] as? Bool != true{status["stage"]="printer preflight";return finish(status)}}
                let result=try await client.generate(args[2],kind:mode=="--ai-image" ? .artwork:.text)
                switch result{case .image(let image):content=StickerContent(image:image);dither = !args.contains("--sharp");case .text(let text):content=StickerContent(text:text)}
            }else if mode=="--clipboard"{content=try S1Files.clipboard()}
            else if mode=="--text",args.count>2{content=StickerContent(text:args[2])}
            else if ["--print","--render"].contains(mode),args.count>2{content=try StickerRenderer.load(URL(fileURLWithPath:args[2]))}
            else{throw StickerRenderer.issue("Use --ai-image PROMPT, --ai-text PROMPT, --print FILE, --text TEXT, --clipboard, --status, --keep-awake [--duration SECONDS] [--interval SECONDS], or --render FILE --output PNG.")}
            let output=try StickerRenderer.render(content,dither:dither,autoRotate:automatic,turns:turns)
            if let path=value("--output") {
                guard let png=StickerImage.pngData(output.image) else{throw StickerRenderer.issue("Could not save the preview.")}
                try png.write(to:URL(fileURLWithPath:path),options:.atomic)
            }
            if mode=="--render"||args.contains("--preview-only") {
                guard value("--output") != nil else{throw StickerRenderer.issue("Specify --output PNG.")}
                return withExtendedLifetime(lease){finish(["ok":true,"sent":false,"message":"Preview ready","width":384,"height":output.height,"rotation":output.quarterTurns*90])}
            }
            try S1Files.save(output)
            var result=await MacRFCOMM.perform(raster:output.raster)
            result["stage"]="printing"
            if result["ok"] as? Bool != true{result["message"]=(result["message"] as? String ?? "Print failed")+" The preview is saved; no automatic retry was made."}
            return withExtendedLifetime(lease){finish(result)}
        }catch{return finish(["ok":false,"sent":false,"message":error.localizedDescription])}
    }
    private static func finish(_ result:[String:Any])->Int32 {
        if CommandLine.arguments.contains("--compact") {
            print(result["message"] as? String ?? "Check S1 Sticker for the result.")
        }else if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]),let text=String(data:data,encoding:.utf8){print(text)}
        return result["ok"] as? Bool==true ? 0:1
    }
}
