import Foundation

struct ChatGPTStream {
    private(set) var text=""
    private(set) var completed=false
    static func read<Bytes:AsyncSequence>(_ bytes:Bytes)async throws->String where Bytes.Element==UInt8 {
        var stream=ChatGPTStream()
        // Foundation's AsyncLineSequence drops blank lines. OpenAI puts one JSON
        // event on each data: line, so consume each immediately, not at a blank line.
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if line.hasPrefix("data:") {
                try stream.consume(String(line.dropFirst(5)).trimmingCharacters(in:.whitespaces))
            }
        }
        return try stream.result()
    }
    mutating func consume(_ data:String)throws {
        guard data != "[DONE]" else{return}
        guard let bytes=data.data(using:.utf8),let event=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any] else{
            throw ChatGPTError.message("OpenAI returned an unreadable response. Nothing was printed.")
        }
        let type=event["type"] as? String ?? ""
        if type=="response.output_text.delta",let delta=event["delta"] as? String {text+=delta}
        if type=="response.completed" {completed=true}
        if type=="response.failed" || type=="error" {
            let response=event["response"] as? [String:Any] ?? event
            let error=response["error"] as? [String:Any] ?? event
            let code=error["code"] as? String ?? ""
            if code.contains("usage_limit") || code.contains("usage_unavailable") || code.contains("quota") || code.contains("rate_limit") {throw ChatGPTError.message("OpenAI API credits or a usage limit need attention. Check API billing, then try again.")}
            throw ChatGPTError.message("OpenAI could not finish this sticker. Nothing was printed.")
        }
        if type=="response.incomplete" {throw ChatGPTError.message("OpenAI's response was incomplete. Nothing was printed.")}
    }
    func result()throws->String {
        guard completed else{throw ChatGPTError.message("The connection ended before OpenAI finished. Nothing was printed.")}
        guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{throw ChatGPTError.message("OpenAI returned no printable content.")}
        guard text.utf8.count<=50000 else{throw ChatGPTError.message("The generated sticker was too long. Ask for a shorter version.")}
        return text
    }
}
