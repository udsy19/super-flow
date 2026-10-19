import Foundation
import SuperFlowCore

/// Symbols people say out loud when they dictate code, commands and file names. Terminals and AI/coding apps get
/// "dash", "dash dash", "slash", "underscore" and "python three"; every app gets "<name> dot <extension>".
enum SpokenSymbols {
    static let extensions: Set<String> = [
        "tsx", "ts", "js", "jsx", "json", "yaml", "yml", "md", "py", "swift", "txt", "csv", "html", "css", "sh", "go", "rs", "java",
        "kt", "rb", "toml", "lock", "xml", "sql", "png", "jpg", "pdf", "mdx", "vue", "c", "h", "cpp", "m", "plist", "zip",
    ]
    /// Dot-files said on their own ("dot venv" → ".venv").
    static let dotfiles: Set<String> = ["venv", "env", "gitignore", "zshrc", "bashrc", "npmrc", "ssh", "vscode", "github", "config"]
    private static let versioned: Set<String> = ["python", "pip"]

    static func apply(_ words: inout Words, category: AppCategory) {
        let code = category == .terminal || category == .ai
        var i = 0
        while i < words.count {
            let w = words[i].lower
            let hasNext = i + 1 < words.count && !words[i + 1].isPlaceholder && Gap.isSpace(words[i + 1].gap)
            if w == "dot", hasNext {
                let next = words[i + 1].lower
                if extensions.contains(next), i > 0, Gap.isSpace(words[i].gap), !words[i - 1].isPlaceholder {
                    words[i - 1].text += "." + next
                    words.items.removeSubrange(i..<i + 2)
                    continue
                }
                if code && dotfiles.contains(next) {
                    let gap = words[i].gap
                    words.items.remove(at: i)
                    words[i].text = "." + next
                    words[i].gap = gap
                    i += 1
                    continue
                }
            }
            guard code else { i += 1; continue }
            if w == "dash", hasNext {
                var j = i
                var prefix = "-"
                if words[i + 1].lower == "dash", i + 2 < words.count, Gap.isSpace(words[i + 2].gap) { prefix = "--"; j = i + 1 }
                let target = j + 1
                // "--save dash dev" → "--save-dev": a dash right after a flag continues it.
                if prefix == "-", i > 0, words[i - 1].text.hasPrefix("-"), Gap.isSpace(words[i].gap) {
                    words[i - 1].text += "-" + words[target].text
                    words.items.removeSubrange(i...target)
                    continue
                }
                let gap = words[i].gap
                words[target].text = prefix + words[target].text
                words[target].gap = gap
                words.items.removeSubrange(i..<target)
                i += 1
                continue
            }
            if (w == "slash" || w == "underscore"), hasNext, i > 0, Gap.isSpace(words[i].gap) {
                words[i - 1].text += (w == "slash" ? "/" : "_") + words[i + 1].text
                words.items.removeSubrange(i..<i + 2)
                continue
            }
            if category == .terminal, versioned.contains(w), hasNext, ["two", "three", "2", "3"].contains(words[i + 1].lower) {
                words[i].text += words[i + 1].lower == "two" || words[i + 1].lower == "2" ? "2" : "3"
                words.items.remove(at: i + 1)
            }
            i += 1
        }
    }
}
