import Foundation

enum ChatGPTError: LocalizedError {
    case message(String)
    var errorDescription:String? {if case let .message(value)=self{return value};return nil}
}
