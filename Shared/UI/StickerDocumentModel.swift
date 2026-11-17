import Foundation
import Combine

@MainActor final class StickerDocumentModel:ObservableObject {
    @Published var text:String {didSet{blocks=nil;scheduleRender()}}
    @Published private(set) var image:StickerPlatformImage?
    @Published var dither=false {didSet{scheduleRender()}}
    @Published var autoRotate=true {didSet{scheduleRender()}}
    @Published var turns=0 {didSet{scheduleRender()}}
    @Published var allowWide=false {didSet{scheduleRender()}}
    @Published private(set) var output:StickerOutput?
    @Published private(set) var rendering=false
    @Published private(set) var error:String?
    private var blocks:[[String:Any]]?
    var hasStructuredBlocks:Bool { blocks != nil }
    private var generation=UUID()
    private var debounce:Task<Void,Never>?
    private let renderer=DispatchQueue(label:"local.chad.s1.render",qos:.userInitiated)

    init(text:String="# Hello from S1\n\n- [ ] Dream it up\n- [ ] Print it out",image:StickerPlatformImage?=nil){self.text=text;self.image=image;self.dither=image != nil;scheduleRender()}
    func useText(){image=nil;blocks=nil;autoRotate=true;turns=0;dither=false;scheduleRender()}
    func setText(_ value:String){if image != nil || text != value {image=nil;blocks=nil;autoRotate=true;turns=0;dither=false;text=value};scheduleRender()}
    func setImage(_ value:StickerPlatformImage){if image !== value{image=value;blocks=nil;autoRotate=true;turns=0;dither=true};scheduleRender()}
    func setContent(_ content:StickerContent){text=content.text;image=content.image;blocks=content.blocks;autoRotate=true;turns=0;dither=image != nil;scheduleRender()}
    func load(_ url:URL)throws {
        let content=try StickerRenderer.load(url)
        text=content.text;image=content.image;blocks=content.blocks;autoRotate=true;turns=0;dither=content.image != nil;scheduleRender()
    }
    func rotate(){guard let image else{return};let current=PrintFormat.quarterTurns(width:image.size.width,height:image.size.height,automatic:autoRotate,manual:turns);autoRotate=false;turns=(current+1)%4}
    private func scheduleRender() {
        debounce?.cancel();generation=UUID();let token=generation;rendering=true
        debounce=Task{[weak self] in
            try? await Task.sleep(nanoseconds:90_000_000)
            guard !Task.isCancelled,let self else{return}
            let content=StickerContent(text:self.text,image:self.image,blocks:self.blocks)
            let dither=self.dither,autoRotate=self.autoRotate,turns=self.turns,allowWide=self.allowWide
            self.renderer.async {[weak self] in
                let result=Result{try StickerRenderer.render(content,dither:dither,autoRotate:autoRotate,turns:turns,allowWide:allowWide)}
                DispatchQueue.main.async{[weak self] in
                    guard let self,self.generation==token else{return}
                    switch result{case .success(let output):self.output=output;self.error=nil;case .failure(let failure):self.output=nil;self.error=failure.localizedDescription}
                    self.rendering=false
                }
            }
        }
    }
}
