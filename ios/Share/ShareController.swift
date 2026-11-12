import UIKit
import SwiftUI
import UniformTypeIdentifiers
import PDFKit

final class ShareController:UIViewController {
    private var didLoadInput=false
    override func viewDidAppear(_ animated:Bool) {
        super.viewDidAppear(animated)
        guard !didLoadInput else{return};didLoadInput=true
        let items=extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers=items.flatMap{$0.attachments ?? []}
        guard let provider=providers.first(where:{$0.hasItemConformingToTypeIdentifier(UTType.image.identifier)||$0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)||$0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)}) else {
            if let text=items.compactMap({$0.attributedContentText?.string}).first,!text.isEmpty {show(StickerView(text:text,image:nil))}
            else {showFailure("Choose an image or text to print.")}
            return
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            let type=provider.registeredTypeIdentifiers.first{UTType($0)?.conforms(to:.image)==true} ?? UTType.image.identifier
            provider.loadFileRepresentation(forTypeIdentifier:type){url,_ in
                if let url,let image=StickerImage.decode(url){DispatchQueue.main.async{self.show(StickerView(text:"",image:image))};return}
                provider.loadDataRepresentation(forTypeIdentifier:type){data,_ in
                    let image=data.flatMap(StickerImage.decode)
                    DispatchQueue.main.async{
                        if let image {self.show(StickerView(text:"",image:image))}
                        else {self.showFailure("The shared image could not be loaded. Try sharing it from Photos again.")}
                    }
                }
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier:UTType.pdf.identifier){data,_ in
                let page=data.flatMap(PDFDocument.init(data:))?.page(at:0)
                let image=page.map{page in let bounds=page.bounds(for:.cropBox);return page.thumbnail(of:CGSize(width:768,height:768*bounds.height/bounds.width),for:.cropBox)}
                DispatchQueue.main.async{if let image{self.show(StickerView(text:"",image:image))}else{self.showFailure("The shared PDF could not be loaded.")}}
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadItem(forTypeIdentifier:UTType.plainText.identifier,options:nil){value,_ in
                DispatchQueue.main.async{self.show(StickerView(text:value as? String ?? "",image:nil))}
            }
        } else {showFailure("Choose an image or text to print.")}
    }
    private func show(_ view:StickerView) {
        let host=UIHostingController(rootView:view);addChild(host);host.view.frame=self.view.bounds;host.view.autoresizingMask=[.flexibleWidth,.flexibleHeight];self.view.addSubview(host.view);host.didMove(toParent:self)
    }
    private func showFailure(_ message:String) {
        let alert=UIAlertController(title:"Could not load sticker",message:message,preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"Close",style:.default){_ in self.extensionContext?.completeRequest(returningItems:nil)})
        present(alert,animated:true)
    }
}
