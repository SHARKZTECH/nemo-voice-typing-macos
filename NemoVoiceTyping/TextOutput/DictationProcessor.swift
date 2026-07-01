import Foundation

public class DictationProcessor {
    private var wordBuf = ""
    private var emitted: [String] = []
    private var lastWordTime: CFAbsoluteTime = 0
    private var lastPieceTime: CFAbsoluteTime = 0
    private var sentenceStart = true
    
    private var pendingCommand: String? = nil
    private var pendingCommandTyped: String? = nil
    private var pendingCommandTime: CFAbsoluteTime = 0
    
    private let commandWindow: TimeInterval = 1.5
    private let bufferIdleFlush: TimeInterval = 1.2
    
    public init() {}
    
    public func flushBuffer() {
        if !wordBuf.isEmpty {
            flushWord()
        }
        if pendingCommand != nil {
            clearPending(commit: true)
        }
    }
    
    public func reset() {
        wordBuf = ""
        emitted.removeAll()
        sentenceStart = true
        pendingCommand = nil
        pendingCommandTyped = nil
        lastWordTime = 0
        lastPieceTime = 0
    }
    
    public func push(piece: String) {
        guard !piece.isEmpty else { return }
        
        let boundary = piece.hasPrefix("\u{2581}")
        let clean = boundary ? String(piece.dropFirst()) : piece
        
        if boundary && !wordBuf.isEmpty {
            flushWord()
        }
        
        if !clean.isEmpty {
            wordBuf += clean
        }
        
        lastPieceTime = CFAbsoluteTimeGetCurrent()
    }
    
    public func tick() {
        let now = CFAbsoluteTimeGetCurrent()
        
        if !wordBuf.isEmpty && (now - lastPieceTime > bufferIdleFlush) {
            flushWord()
        }
        
        if pendingCommand != nil, (now - pendingCommandTime > commandWindow) {
            clearPending(commit: true)
        }
    }
    
    private func flushWord() {
        let raw = wordBuf
        wordBuf = ""
        guard !raw.isEmpty else { return }
        
        lastWordTime = CFAbsoluteTimeGetCurrent()
        
        // Punctuation check: if purely non-alphanumeric, treat as model's punctuation
        let hasAlphanumeric = raw.rangeOfCharacter(from: .alphanumerics) != nil
        if !hasAlphanumeric {
            let mark = raw.first
            if let mark = mark, "?!.,;:".contains(mark), !emitted.isEmpty {
                let prev = emitted.last ?? ""
                if !prev.isEmpty {
                    let prevTail = prev.last
                    // Upgrade weaker auto-punctuation to model's stronger choice.
                    if prevTail == "." && (mark == "?" || mark == "!") {
                        TextInjector.backspace(count: 1)
                        TextInjector.type(String(mark))
                        emitted[emitted.count - 1] = String(prev.dropLast()) + String(mark)
                        sentenceStart = true
                        return
                    }
                    if prevTail == mark { return } // swallow duplicate
                }
            }
            attachPunctuation(raw)
            return
        }
        
        let lower = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,?!;:"))
        
        // Two-word commands (second word check)
        if let pending = pendingCommand {
            if CFAbsoluteTimeGetCurrent() - pendingCommandTime <= commandWindow {
                if (pending == "scratch" || pending == "delete") && lower == "that" {
                    clearPending(commit: false)
                    deleteLastSentence()
                    return
                }
                if pending == "delete" && lower == "last" {
                    clearPending(commit: false)
                    deleteLastWord()
                    return
                }
                if pending == "new" && lower == "line" {
                    clearPending(commit: false)
                    insertEnter(blankLines: 1)
                    return
                }
                if pending == "new" && lower == "paragraph" {
                    clearPending(commit: false)
                    insertEnter(blankLines: 2)
                    return
                }
                if pending == "question" && lower == "mark" {
                    clearPending(commit: false)
                    attachPunctuation("?")
                    return
                }
                if pending == "exclamation" && (lower == "mark" || lower == "point") {
                    clearPending(commit: false)
                    attachPunctuation("!")
                    return
                }
            }
            clearPending(commit: true)
        }
        
        // Single-word spoken punctuation commands
        switch lower {
        case "period", "fullstop", "dot":
            attachPunctuation(".")
            return
        case "comma":
            attachPunctuation(",")
            return
        case "colon":
            attachPunctuation(":")
            return
        case "semicolon":
            attachPunctuation(";")
            return
        default:
            break
        }
        
        // Start of two-word command (hold and watch)
        if ["scratch", "delete", "new", "question", "exclamation"].contains(lower) {
            let typed = typeWord(raw)
            pendingCommand = lower
            pendingCommandTyped = typed
            pendingCommandTime = CFAbsoluteTimeGetCurrent()
            return
        }
        
        // Regular word
        _ = typeWord(raw)
    }
    
    private func typeWord(_ word: String) -> String {
        var sb = ""
        let needSpace = !emitted.isEmpty && !sentenceStart && !lastEndsWithSoftBreak()
        
        if !emitted.isEmpty && sentenceStart && !lastEndsWithHardBreak() {
            sb += " "
        } else if needSpace {
            sb += " "
        }
        
        // Capitalize start of sentence (only if model generated it lowercase)
        let containsUppercase = word.contains { $0.isUppercase }
        if sentenceStart && !containsUppercase && word.first?.isLowercase == true {
            let firstCap = word.prefix(1).uppercased()
            sb += firstCap + word.dropFirst()
        } else {
            sb += word
        }
        
        let text = sb
        TextInjector.type(text)
        emitted.append(text)
        
        if let lastChar = text.last {
            sentenceStart = ".?!".contains(lastChar)
        }
        return text
    }
    
    private func attachPunctuation(_ punct: String) {
        TextInjector.type(punct)
        if !emitted.isEmpty {
            emitted[emitted.count - 1] += punct
        } else {
            emitted.append(punct)
        }
        
        if ".?!".contains(punct) {
            sentenceStart = true
        }
    }
    
    private func insertEnter(blankLines: Int) {
        for _ in 0..<blankLines {
            TextInjector.pressEnter()
        }
        emitted.append(String(repeating: "\n", count: blankLines))
        sentenceStart = true
    }
    
    private func deleteLastSentence() {
        guard !emitted.isEmpty else { return }
        var totalToDelete = 0
        
        while !emitted.isEmpty {
            let seg = emitted.removeLast()
            totalToDelete += seg.count
            
            if !emitted.isEmpty {
                let prev = emitted.last ?? ""
                if let c = prev.last, ".?!".contains(c) {
                    break
                }
            }
        }
        TextInjector.backspace(count: totalToDelete)
        sentenceStart = true
    }
    
    private func deleteLastWord() {
        guard !emitted.isEmpty else { return }
        let seg = emitted.removeLast()
        TextInjector.backspace(count: seg.count)
        if emitted.isEmpty {
            sentenceStart = true
        }
    }
    
    private func clearPending(commit: Bool) {
        if !commit, let typed = pendingCommandTyped {
            TextInjector.backspace(count: typed.count)
            if !emitted.isEmpty && emitted.last == typed {
                emitted.removeLast()
                if emitted.isEmpty {
                    sentenceStart = true
                } else {
                    let prev = emitted.last ?? ""
                    if let c = prev.last {
                        sentenceStart = ".?!".contains(c)
                    }
                }
            }
        }
        pendingCommand = nil
        pendingCommandTyped = nil
    }
    
    private func lastEndsWithHardBreak() -> Bool {
        guard let last = emitted.last else { return true }
        return last.hasSuffix("\n")
    }
    
    private func lastEndsWithSoftBreak() -> Bool {
        return lastEndsWithHardBreak()
    }
}
