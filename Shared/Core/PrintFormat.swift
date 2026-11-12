import Foundation

public enum PrintFormat {
    public static let width=384
    public static let maximumRows=2400
    public static let feedRows=80
    public static let leadingBlankRows=0
    public static func quarterTurns(width:Double,height:Double,automatic:Bool,manual:Int)->Int {
        if automatic{return width>height ? 1:0}
        return (manual%4+4)%4
    }
    public static func extractInstructions(_ source:String)throws->String {
        let start="<!-- S1_PRINT_PROFILE_START -->",end="<!-- S1_PRINT_PROFILE_END -->"
        guard let a=source.range(of:start),let b=source.range(of:end,range:a.upperBound..<source.endIndex) else{
            throw NSError(domain:"S1Sticker",code:2,userInfo:[NSLocalizedDescriptionKey:"The printer formatting profile is missing. Rebuild S1 Sticker."])
        }
        let profile=String(source[a.upperBound..<b.lowerBound]).trimmingCharacters(in:.whitespacesAndNewlines)
        guard !profile.isEmpty else{throw NSError(domain:"S1Sticker",code:2,userInfo:[NSLocalizedDescriptionKey:"The printer formatting profile is empty."])}
        return profile
    }
    public static func instructions()throws->String {
        guard let url=Bundle.main.url(forResource:"AGENTS",withExtension:"md") else{
            throw NSError(domain:"S1Sticker",code:2,userInfo:[NSLocalizedDescriptionKey:"The printer formatting profile is missing. Rebuild S1 Sticker."])
        }
        return try extractInstructions(String(contentsOf:url,encoding:.utf8))
    }
}
