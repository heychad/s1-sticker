import Foundation
import Security
import Combine
#if canImport(UIKit)
import UIKit
typealias StickerAIImage=UIImage
#else
import AppKit
typealias StickerAIImage=NSImage
#endif

enum StickerAIKind:String,CaseIterable,Identifiable {
    case artwork="Artwork"
    case text="Text & tables"
    var id:String{rawValue}
}
enum StickerAIResult {
    case image(StickerAIImage)
    case text(String)
}

private enum OpenAIAPIKey {
    #if canImport(UIKit)
    static let service="local.chad.S1Pocket.OpenAI"
    #else
    static let service="local.chad.S1Sticker.OpenAI"
    #endif
    static func read()->String? {
        var result:CFTypeRef?
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"personal-api-key",kSecReturnData as String:true]
        guard SecItemCopyMatching(query as CFDictionary,&result)==errSecSuccess,let data=result as? Data else{return nil}
        return String(data:data,encoding:.utf8)
    }
    static func save(_ key:String)throws {
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"personal-api-key"]
        let values:[String:Any]=[kSecValueData as String:Data(key.utf8),kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status=SecItemUpdate(query as CFDictionary,values as CFDictionary)
        if status==errSecItemNotFound {var add=query;values.forEach{add[$0.key]=$0.value};status=SecItemAdd(add as CFDictionary,nil)}
        guard status==errSecSuccess else{throw ChatGPTError.message("Could not save the API key securely.")}
    }
    static func remove(){SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"personal-api-key"] as CFDictionary)}
}

@MainActor final class OpenAIStickerClient:ObservableObject {
    @Published private(set) var configured=false
    @Published private(set) var busy=false
    @Published private(set) var message=""
    private var key:String?
    private var imageModel="gpt-image-2.5-flare"
    private var textModel="gpt-6.1-sol"
    private let session:URLSession
    private let installationID:String

    init() {
        let configuration=URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest=180
        configuration.timeoutIntervalForResource=240
        session=URLSession(configuration:configuration)
        key=OpenAIAPIKey.read();configured=key != nil
        let defaults=UserDefaults.standard
        if let saved=defaults.string(forKey:"s1-ai-installation-id"){installationID=saved}
        else{installationID=UUID().uuidString;defaults.set(installationID,forKey:"s1-ai-installation-id")}
        imageModel=defaults.string(forKey:"s1-ai-image-model") ?? imageModel
        textModel=defaults.string(forKey:"s1-ai-text-model") ?? textModel
    }
    func connect(_ entered:String)async throws {
        guard !busy else{return}
        let candidate=entered.trimmingCharacters(in:.whitespacesAndNewlines)
        guard (20...1000).contains(candidate.count),!candidate.contains(where:{$0.isWhitespace}) else{throw ChatGPTError.message("Enter a valid personal OpenAI API key.")}
        busy=true;message="Checking API access…";defer{busy=false}
        var request=URLRequest(url:URL(string:"https://api.openai.com/v1/models")!)
        request.setValue("Bearer "+candidate,forHTTPHeaderField:"Authorization")
        let (data,response)=try await session.data(for:request)
        try check(response,data:data)
        let root=try JSONSerialization.jsonObject(with:data) as? [String:Any]
        let ids=Set((root?["data"] as? [[String:Any]] ?? []).compactMap{$0["id"] as? String})
        if let available=["gpt-image-2.5-flare","gpt-image-2.5-sunburst","gpt-image-2","gpt-image-1.5"].first(where:{ids.contains($0)}){imageModel=available}
        if let available=["gpt-6.1-sol","gpt-6-sol","gpt-5.1","gpt-5"].first(where:{ids.contains($0)}){textModel=available}
        try OpenAIAPIKey.save(candidate)
        key=candidate;configured=true;message="API access ready"
        UserDefaults.standard.set(imageModel,forKey:"s1-ai-image-model")
        UserDefaults.standard.set(textModel,forKey:"s1-ai-text-model")
    }
    func disconnect(){OpenAIAPIKey.remove();key=nil;configured=false;message="API access removed from this device"}
    func generate(_ prompt:String,kind:StickerAIKind)async throws->StickerAIResult {
        guard let key else{throw ChatGPTError.message("Set up API access first.")}
        let prompt=prompt.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !prompt.isEmpty,prompt.count<=4000 else{throw ChatGPTError.message("Describe the sticker in 1–4,000 characters.")}
        guard !busy else{throw ChatGPTError.message("A request is already in progress.")}
        let printerInstructions=try PrintFormat.instructions()
        busy=true;defer{busy=false}
        if kind == .artwork {
            message="Drawing your sticker…"
            let instruction=printerInstructions+"\n\nCreate one finished artwork image following that printer profile. User request: "+prompt
            let body:[String:Any]=["model":imageModel,"prompt":instruction,"size":"auto","quality":"low","n":1,"output_format":"png","background":"opaque","safety_identifier":installationID]
            let request=try request(path:"images/generations",key:key,body:body)
            let (data,response)=try await session.data(for:request)
            try check(response,data:data);try Task.checkCancellation()
            let root=try JSONSerialization.jsonObject(with:data) as? [String:Any]
            guard let result=(root?["data"] as? [[String:Any]])?.first,
                  let encoded=result["b64_json"] as? String,let bytes=Data(base64Encoded:encoded),let image=decodeImage(bytes) else{
                throw ChatGPTError.message("OpenAI did not return a usable image. Nothing printed.")
            }
            message="Artwork ready";return .image(image)
        }
        message="Writing your sticker…"
        let instructions=printerInstructions+"\n\nReturn only final Markdown, without a code fence or explanation. Supported formatting: # heading, ## subheading, short paragraphs, bullets, - [ ] checkboxes, and tables with 1–3 short columns. Prefer fewer than 1,200 characters. Do not generate an image; produce the requested label, note, list, or table as text."
        let body:[String:Any]=["model":textModel,"instructions":instructions,"input":[["role":"user","content":prompt]],"stream":true,"store":false]
        let request=try request(path:"responses",key:key,body:body)
        let (bytes,response)=try await session.bytes(for:request)
        if let http=response as? HTTPURLResponse,!(200..<300).contains(http.statusCode) {
            var failure=Data()
            for try await byte in bytes {failure.append(byte);if failure.count>=16384{break}}
            try check(response,data:failure)
        }
        var text=try await ChatGPTStream.read(bytes).trimmingCharacters(in:.whitespacesAndNewlines)
        if text.hasPrefix("```"),text.hasSuffix("```") {
            var lines=text.components(separatedBy:"\n")
            if lines.count>=3 {lines.removeFirst();lines.removeLast();text=lines.joined(separator:"\n")}
        }
        message="Text ready";return .text(text)
    }
    private func decodeImage(_ data:Data)->StickerAIImage? {
        #if canImport(UIKit)
        return StickerImage.decode(data)
        #else
        return NSImage(data:data)
        #endif
    }
    private func request(path:String,key:String,body:[String:Any])throws->URLRequest {
        var request=URLRequest(url:URL(string:"https://api.openai.com/v1/"+path)!)
        request.httpMethod="POST";request.setValue("Bearer "+key,forHTTPHeaderField:"Authorization")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody=try JSONSerialization.data(withJSONObject:body);return request
    }
    private func check(_ response:URLResponse,data:Data?=nil)throws {
        guard let http=response as? HTTPURLResponse else{throw ChatGPTError.message("OpenAI returned an invalid response.")}
        var detail=""
        if let data,let root=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
           let failure=root["error"] as? [String:Any],let code=failure["code"] as? String,
           code.count<=80,code.unicodeScalars.allSatisfy({CharacterSet.alphanumerics.union(CharacterSet(charactersIn:"_-.")).contains($0)}) {
            detail=" (\(code))"
        }
        switch http.statusCode {
        case 200..<300:return
        case 401:throw ChatGPTError.message("The API key is invalid or expired. Update API access in settings.")
        case 402,429:throw ChatGPTError.message("OpenAI API credits or a usage limit need attention. Check API billing, then try again.")
        case 403:throw ChatGPTError.message("This API project does not have access to the selected model. Check permissions or account verification.")
        default:throw ChatGPTError.message("OpenAI could not complete this request (HTTP \(http.statusCode))\(detail). Nothing printed.")
        }
    }
}
