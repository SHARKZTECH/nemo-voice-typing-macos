import Foundation

public class Tokenizer {
    private var pieces: [String] = []
    
    public var vocabSize: Int {
        return pieces.count
    }
    
    public init(vocabURL: URL) throws {
        let content = try String(contentsOf: vocabURL, encoding: .utf8)
        self.pieces = content.components(separatedBy: .newlines)
        // Clean trailing empty element if present
        if self.pieces.last?.isEmpty == true {
            self.pieces.removeLast()
        }
    }
    
    public func piece(id: Int) -> String {
        guard id >= 0 && id < pieces.count else { return "" }
        return pieces[id]
    }
    
    public func detokenize(ids: [Int]) -> String {
        var result = ""
        for id in ids {
            let p = piece(id: id)
            if p.isEmpty { continue }
            
            if p.hasPrefix("\u{2581}") {
                result += " "
                result += p.dropFirst()
            } else {
                result += p
            }
        }
        return result
    }
}
