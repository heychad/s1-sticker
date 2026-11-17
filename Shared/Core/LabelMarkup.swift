import Foundation

public enum LabelBlock: Equatable {
    case text(String, heading: Int)
    case table([[String]])
}

public enum LabelMarkup {
    public static func parse(_ text: String) throws -> [LabelBlock] {
        let lines = text.components(separatedBy: .newlines)
        var result: [LabelBlock] = [], index = 0
        func cells(_ line: String) -> [String] {
            var value = line.trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("|") { value.removeFirst() }
            if value.hasSuffix("|") { value.removeLast() }
            return value.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        while index < lines.count {
            let line = lines[index]
            if line.contains("|"), index + 1 < lines.count, lines[index+1].contains("---") {
                let header = cells(line)
                guard (1...3).contains(header.count) else { throw NSError(domain:"Vretti",code:1,userInfo:[NSLocalizedDescriptionKey:"Tables need one to three columns."]) }
                var rows = [header]; index += 2
                while index < lines.count, lines[index].contains("|") {
                    let row = cells(lines[index])
                    guard row.count == header.count else { throw NSError(domain:"Vretti",code:1,userInfo:[NSLocalizedDescriptionKey:"Each table row needs the same number of columns."]) }
                    rows.append(row); index += 1
                }
                result.append(.table(rows)); continue
            }
            if line.hasPrefix("# ") { result.append(.text(String(line.dropFirst(2)), heading: 1)) }
            else if line.hasPrefix("## ") { result.append(.text(String(line.dropFirst(3)), heading: 2)) }
            else if line.hasPrefix("- [ ] ") { result.append(.text("☐ " + line.dropFirst(6), heading: 0)) }
            else if line.hasPrefix("- [x] ") { result.append(.text("☑ " + line.dropFirst(6), heading: 0)) }
            else if line.hasPrefix("- ") { result.append(.text("• " + line.dropFirst(2), heading: 0)) }
            else { result.append(.text(line, heading: 0)) }
            index += 1
        }
        return result
    }
}
