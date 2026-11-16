import SwiftUI
import UniformTypeIdentifiers
import AppKit

@main @MainActor enum S1Main {
    static func main() {
        let arguments=CommandLine.arguments
        if arguments.count>1,arguments[1].hasPrefix("--") {
            // CLI work should not activate the app or place it in the Dock.
            NSApplication.shared.setActivationPolicy(.prohibited)
            Task{exit(await S1CommandLine.run(arguments))}
            RunLoop.main.run()
        }else{S1DesktopApp.main()}
    }
}

@MainActor final class DesktopDelegate:NSObject,NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
    func applicationDidFinishLaunching(_ notification:Notification){NSApp.setActivationPolicy(.regular);NSApp.activate(ignoringOtherApps:true)}
}

@MainActor struct S1DesktopApp:App {
    @NSApplicationDelegateAdaptor(DesktopDelegate.self) private var delegate
    @StateObject private var document=StickerDocumentModel(text:"# Hello from my Mac\n\n- [ ] Make a sticker\n- [ ] Put it somewhere useful\n\n| Item | Status |\n| --- | --- |\n| Bluetooth | Ready |\n| Sticker supply | Plenty |")
    @StateObject private var printer=MacPrinter()
    @StateObject private var ai=OpenAIStickerClient()
    var body:some Scene {
        Window("S1 Sticker",id:"main") {MacStickerView(document:document,printer:printer,ai:ai)}
            .defaultSize(width:900,height:790)
        Settings{MacAISettings(client:ai)}
    }
}

@MainActor struct MacStickerView:View {
    @ObservedObject var document:StickerDocumentModel
    @ObservedObject var printer:MacPrinter
    @ObservedObject var ai:OpenAIStickerClient
    @State private var choosingFile=false
    @State private var printWhenReady=false
    private var busy:Bool{printer.busy||ai.busy||printWhenReady}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                VStack(alignment:.leading,spacing:5){Text("Make it. Print it. Stick it.").font(.title2.bold());Text(document.error ?? printer.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)}
                Spacer()
            }
            HStack {
                Button("Open file…"){choosingFile=true}
                Button("Use clipboard"){do{document.setContent(try S1Files.clipboard())}catch{printer.message=error.localizedDescription}}
                Button("Use text"){document.useText()}
                Button("Check printer"){printer.check()}
                Spacer()
                Button("Pair iPhone"){do{NSWorkspace.shared.open(try S1Files.pairingPage())}catch{printer.message=error.localizedDescription}}
            }.disabled(busy)
            MacAIComposer(client:ai,printerBusy:printer.busy||printWhenReady){result,printNow in
                switch result{case .image(let image):document.setImage(image);case .text(let text):document.setText(text)}
                printWhenReady=printNow
            }
            HSplitView {
                VStack(alignment:.leading,spacing:8){Text("Content").font(.headline);PlainTextEditor(text:$document.text,editable:!ai.busy&&document.image==nil).padding(6);if document.image != nil{Text("Image selected. Choose Use text to edit a label.").font(.caption).foregroundStyle(.secondary)}}.frame(minWidth:280)
                VStack(alignment:.leading,spacing:8) {
                    HStack{Text("Print preview").font(.headline);Spacer();if document.rendering{ProgressView().controlSize(.small)}}
                    ScrollView([.vertical,.horizontal]) {
                        if let output=document.output{Image(nsImage:output.image).resizable().interpolation(.none).frame(width:384,height:CGFloat(output.height)).background(.white).padding(12)}
                    }.background(Color(nsColor:.underPageBackgroundColor)).frame(minWidth:320)
                }
            }.frame(minHeight:250)
            HStack {
                Picker("Print style",selection:$document.dither){Text("Sharp text").tag(false);Text("Dither grayscale").tag(true)}.pickerStyle(.segmented).frame(width:260)
                Toggle("Auto rotate",isOn:$document.autoRotate).disabled(document.image==nil)
                Button("Rotate 90°"){document.rotate()}.disabled(document.image==nil)
                Spacer()
                if let output=document.output{Text("48 × \(Int(round(Double(output.height)/8))) mm").foregroundStyle(.secondary)}
                Button("Print sticker"){printCurrent()}.buttonStyle(.borderedProminent).keyboardShortcut("p").disabled(busy||document.rendering||document.output==nil)
            }
        }.padding(22).frame(minWidth:850,minHeight:680).disableWritingOverlays()
            .fileImporter(isPresented:$choosingFile,allowedContentTypes:[.image,.pdf,.plainText,.json]){result in do{try document.load(result.get())}catch{printer.message=error.localizedDescription}}
            .onOpenURL{url in do{try document.load(url)}catch{printer.message=error.localizedDescription}}
            .dropDestination(for:URL.self){urls,_ in guard let url=urls.first else{return false};do{try document.load(url);return true}catch{printer.message=error.localizedDescription;return false}}
            .onReceive(document.$rendering){rendering in guard !rendering,printWhenReady else{return};printWhenReady=false;if document.error==nil{printCurrent()}}
    }
    private func printCurrent(){guard !document.rendering,let output=document.output else{return};printer.printOutput(output)}
}

@MainActor private struct MacAIComposer:View {
    @ObservedObject var client:OpenAIStickerClient
    let printerBusy:Bool
    let onResult:(StickerAIResult,Bool)->Void
    @AppStorage("s1-ai-prompt") private var prompt=""
    @AppStorage("s1-ai-kind") private var kindRaw=0
    @State private var settings=false
    @State private var task:Task<Void,Never>?
    @State private var preview:StickerAIResult?
    @State private var previewID=""
    @State private var error:String?
    private var inputID:String{"\(kindRaw)\n"+prompt.trimmingCharacters(in:.whitespacesAndNewlines)}
    private var current:Bool{preview != nil&&previewID==inputID}
    var body:some View {
        GroupBox {
            VStack(alignment:.leading,spacing:10) {
                HStack{Label("Ask for a sticker",systemImage:"sparkles").font(.headline);Spacer();Button("AI settings…"){settings=true}.disabled(client.busy)}
                TextField("Describe your sticker, checklist, or table…",text:$prompt).textFieldStyle(.roundedBorder).disabled(client.busy)
                HStack {
                    Picker("Type",selection:$kindRaw){Text("Artwork").tag(0);Text("Text & tables").tag(1)}.pickerStyle(.segmented).frame(width:230)
                    Button(current ? "New preview":"Preview"){generate(false)}.disabled(!canGenerate)
                    Button(current ? "Print preview":"Generate & Print"){generate(true)}.disabled(!canGenerate)
                    if client.busy{ProgressView().controlSize(.small);Text(client.message).foregroundStyle(.secondary);Button("Cancel"){task?.cancel()}}
                    Spacer()
                }
                if let error{Text(error).foregroundStyle(.red).font(.caption)}
                Text(client.configured ? "Uses your saved OpenAI key and API credits. Print preview reuses the generated result.":"Open AI settings to add your S1 project API key.").font(.caption).foregroundStyle(.secondary)
            }.padding(4)
        }.sheet(isPresented:$settings){MacAISettings(client:client)}
    }
    private var canGenerate:Bool{client.configured && !client.busy && !printerBusy && !prompt.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}
    private func generate(_ printNow:Bool) {
        guard task==nil else{return};error=nil
        if printNow,current,let preview{onResult(preview,true);return}
        let id=inputID
        task=Task {
            do{let result=try await client.generate(prompt,kind:kindRaw==0 ? .artwork:.text);try Task.checkCancellation();preview=result;previewID=id;onResult(result,printNow)}
            catch is CancellationError{error="Generation cancelled."}
            catch{self.error=error.localizedDescription}
            task=nil
        }
    }
}

@MainActor struct MacAISettings:View {
    @ObservedObject var client:OpenAIStickerClient
    @Environment(\.dismiss) private var dismiss
    @State private var key=""
    @State private var message=""
    var body:some View {
        Form {
            Text("OpenAI API access").font(.title2.bold())
            Text("Use the same S1 project API key as your iPhone. It stays in this Mac’s Keychain and is sent only to OpenAI.").foregroundStyle(.secondary)
            SecureField("Paste API key",text:$key).textFieldStyle(.roundedBorder)
            HStack {
                Button(client.busy ? "Checking…":"Save and check access"){Task{do{try await client.connect(key);key="";message="API access ready"}catch{message=error.localizedDescription}}}.disabled(client.busy||key.isEmpty)
                Button("Done"){dismiss()}
            }
            if !message.isEmpty{Text(message).textSelection(.enabled)}
            Link("Open API billing",destination:URL(string:"https://platform.openai.com/settings/organization/billing/overview")!)
            if client.configured{Button("Remove key from this Mac",role:.destructive){client.disconnect();message="Key removed from this Mac"}.disabled(client.busy)}
        }.padding(24).frame(width:460)
    }
}
