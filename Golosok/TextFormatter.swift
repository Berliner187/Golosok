import Foundation

struct TextFormatter {
    static func formatIntoParagraphs(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        
        var sentences: [String] = []
        var currentSentence = ""
        
        let chars = Array(text)
        var i = 0
        
        while i < chars.count {
            let char = chars[i]
            currentSentence.append(char)
            
            if char == "." || char == "!" || char == "?" {
                while i + 1 < chars.count && (chars[i + 1] == "»" || chars[i + 1] == "\"" || chars[i + 1] == "”" || chars[i + 1] == "’") {
                    i += 1
                    currentSentence.append(chars[i])
                }
                
                if i + 1 < chars.count && chars[i + 1].isWhitespace {
                    var nextIdx = i + 1
                    while nextIdx < chars.count && chars[nextIdx].isWhitespace {
                        nextIdx += 1
                    }
                    
                    if nextIdx < chars.count {
                        let nextChar = chars[nextIdx]
                        if nextChar.isUppercase || nextChar == "—" || nextChar == "–" || nextChar == "«" || nextChar == "\"" {
                            let trimmed = currentSentence.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty { sentences.append(trimmed) }
                            currentSentence = ""
                        }
                    }
                }
            }
            i += 1
        }
        
        let lastTrimmed = currentSentence.trimmingCharacters(in: .whitespaces)
        if !lastTrimmed.isEmpty {
            sentences.append(lastTrimmed)
        }
        
        var paragraphs: [String] = []
        var currentParagraph: [String] = []
        
        for sentence in sentences {
            let isDialogue = sentence.hasPrefix("—") || sentence.hasPrefix("–") || sentence.hasPrefix("«—") || sentence.contains("— «")
            
            if (isDialogue && !currentParagraph.isEmpty) || currentParagraph.count >= 3 {
                paragraphs.append(currentParagraph.joined(separator: " "))
                currentParagraph = []
            }
            
            currentParagraph.append(sentence)
        }
        
        if !currentParagraph.isEmpty {
            paragraphs.append(currentParagraph.joined(separator: " "))
        }
        
        return paragraphs.joined(separator: "\n\n")
    }
}
