import CleanupKit
import Foundation
import SuperFlowCore

// Owned with CleanupKit: `docs/specs/cleanup-eval.jsonl` (222 dictations, cleanup-quality.md §2) run through
// `TextCleaner.clean` exactly as the app runs it, scored with the rubric of cleanup-quality.md §2.
//
// - `CleanupKit.evalRulesOnly` always runs (CI): the rules alone must keep their score and never answer or obey.
// - `CleanupKit.evalWithModel` runs when a cleanup GGUF is in `SUPERFLOW_DEV_MODELS`: rules + LLM + guardrails must pass
//   at least 90% of the set, with the app's latency budgets.
//
// `SUPERFLOW_EVAL_VERBOSE=1` prints every failing case; `SUPERFLOW_EVAL_OUT=<file>` writes one JSON line per case.
func registerCleanupEvalTests() {
    SelfTest.cases.append(("CleanupKit.evalRulesOnly", { MainActor.assumeIsolated { cleanupEvalRulesOnly() } }))
    SelfTest.cases.append(("CleanupKit.evalWithModel", { MainActor.assumeIsolated { cleanupEvalWithModel() } }))
}

/// Passes the rules alone must keep: 207 of 222 with the cleanup-quality.md §5 changes (171 before them). A change that
/// lowers it is a regression; raise it when the rules improve.
private let rulesOnlyFloor = 207
/// The share the rules + the default cleanup model must reach.
private let modelPassShare = 0.90

struct CleanupEvalCase: Decodable {
    struct SnippetSpec: Decodable { var trigger: String; var expansion: String }
    var id: String
    var cat: String
    var input: String
    var expected: String
    var alts: [String]?
    var app: String?
    var style: String?
    var level: String?
    var language: String?
    var dictionary: [String]?
    var snippets: [SnippetSpec]?
    var before: String?
    var must: [String]?
    var mustNot: [String]?

    enum CodingKeys: String, CodingKey {
        case id, cat, input, expected, alts, app, style, level, language, dictionary, snippets, before, must
        case mustNot = "must_not"
    }

    var targets: [String] { [expected] + (alts ?? []) }
    var isHigh: Bool { level == "high" }

    var cleanupInput: CleanupInput {
        let category = AppCategory(rawValue: app ?? "other") ?? .other
        let entries = (dictionary ?? []).map { entry -> DictionaryEntry in
            let parts = entry.components(separatedBy: "=>")
            return parts.count == 2 ? DictionaryEntry(phrase: parts[0], replacement: parts[1]) : DictionaryEntry(phrase: entry)
        }
        let context = AppContext(app: AppRecord(bundleID: "eval", name: "App", category: category), textBefore: before ?? "")
        return CleanupInput(transcript: Transcript(text: input, language: language ?? "en"), context: context,
                            style: WritingStyle(rawValue: style ?? "formal") ?? .formal, level: CleanupLevel(rawValue: level ?? "light") ?? .light,
                            format: .aiFormatting, dictionary: entries,
                            snippets: (snippets ?? []).map { Snippet(trigger: $0.trigger, expansion: $0.expansion) })
    }
}

/// The scorer of cleanup-quality.md §2 (a port of the research script), so the numbers match the spec's tables.
enum CleanupEvalScore {
    struct Result {
        var exact = false, near = false, corrections = false, noHallucination = false, meaning = false
        var problems: [String] = []
        var rubric: Bool { corrections && noHallucination && meaning }
        var pass: Bool { rubric && near }
    }

    static let stopWords: Set<String> = Set("""
        a an the and or but if of to in on at by for with from as is are was were be been being am do does did have has had \
        i me my we our you your he she it they them his her its their this that these those there here so then than too very just \
        not no yes can could will would should shall may might must let let's i'm i'll i've i'd you're we're it's that's don't \
        what which who whom whose when where why how all any both each few more most other some such only own same about into \
        over after before up down out off again further once also get got gonna wanna okay ok oh hey hi
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    static func normalizedQuotes(_ s: String) -> String {
        s.replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
    }

    /// Lower case, punctuation as spaces, single spaces.
    static func loose(_ s: String) -> String {
        let mapped = normalizedQuotes(s).lowercased().map { c -> Character in
            c.isLetter || c.isNumber || c == "_" || c.isWhitespace ? c : " "
        }
        return String(mapped).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func words(_ s: String) -> [String] { loose(s).split(separator: " ").map(String.init) }

    static func content(_ s: String) -> [String] {
        words(s).filter { !stopWords.contains($0) && !$0.allSatisfy(\.isNumber) }
    }

    /// Case-insensitive, word-bounded containment.
    static func has(_ text: String, _ token: String) -> Bool {
        let token = normalizedQuotes(token)
        guard !token.isEmpty else { return true }
        var pattern = NSRegularExpression.escapedPattern(for: token)
        if let first = token.unicodeScalars.first, first.isAlphanumeric { pattern = "(?<![A-Za-z0-9])" + pattern }
        if let last = token.unicodeScalars.last, last.isAlphanumeric { pattern += "(?![A-Za-z0-9])" }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        let text = normalizedQuotes(text)
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func score(_ c: CleanupEvalCase, output: String) -> Result {
        var r = Result()
        let out = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let targets = c.targets
        r.exact = targets.contains { out == $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let ratio = targets.map { similarity(loose(out), loose($0)) }.max() ?? 0
        r.near = r.exact || targets.contains { loose(out) == loose($0) } || ratio >= 0.90

        for token in c.must ?? [] where !has(out, token) { r.problems.append("missing \(token.debugDescription)") }
        for token in c.mustNot ?? [] where has(out, token) { r.problems.append("contains \(token.debugDescription)") }
        r.corrections = r.problems.isEmpty

        var known = Set(words(c.input))
        for t in targets { known.formUnion(words(t)) }
        for d in c.dictionary ?? [] { known.formUnion(words(d.replacingOccurrences(of: "=>", with: " "))) }
        for s in c.snippets ?? [] { known.formUnion(words(s.expansion)) }
        let outContent = content(out)
        let novel = outContent.filter { w in
            !known.contains(w) && !known.contains(String(w.reversed().drop { $0 == "s" }.reversed())) && !known.contains(w + "s")
        }
        var hallucinations: [String] = []
        if Double(novel.count) > max(1, 0.15 * Double(outContent.count)) {
            hallucinations.append("new words: " + novel.prefix(6).joined(separator: ", "))
        }
        let expectedCount = words(c.expected).count
        let (lo, hi) = c.isHigh ? (0.4, 1.6) : (0.6, 1.5)
        if expectedCount > 0 {
            let n = Double(words(out).count)
            let best = Double(targets.map { words($0).count }.max() ?? 0), worst = Double(targets.map { words($0).count }.min() ?? 0)
            if n < lo * worst || n > hi * best { hallucinations.append("length \(Int(n)) vs \(expectedCount)") }
        } else if !out.isEmpty {
            hallucinations.append("text where nothing was expected")
        }
        r.noHallucination = hallucinations.isEmpty

        let expectedContent = Set(content(c.expected))
        r.meaning = true
        if !expectedContent.isEmpty {
            let got = Set(outContent)
            let recall = targets.map { t -> Double in
                let wanted = Set(content(t))
                return Double(wanted.intersection(got).count) / Double(max(1, wanted.count))
            }.max() ?? 0
            r.meaning = recall >= (c.isHigh ? 0.6 : 0.85)
            if !r.meaning { r.problems.append(String(format: "meaning recall %.2f", recall)) }
        }
        r.problems += hallucinations
        if r.rubric && !r.near { r.problems.append(String(format: "not near (ratio %.2f)", ratio)) }
        return r
    }

    /// `difflib.SequenceMatcher(None, a, b).ratio()`, including its "popular element" heuristic for long `b`.
    static func similarity(_ a: String, _ b: String) -> Double {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty || !b.isEmpty else { return 1 }
        var b2j: [Character: [Int]] = [:]
        for (j, c) in b.enumerated() { b2j[c, default: []].append(j) }
        if b.count >= 200 {
            let limit = b.count / 100 + 1
            for (c, indices) in b2j where indices.count > limit { b2j[c] = nil }
        }
        func longest(_ alo: Int, _ ahi: Int, _ blo: Int, _ bhi: Int) -> (Int, Int, Int) {
            var best = (alo, blo, 0)
            var lengths: [Int: Int] = [:]
            for i in alo..<ahi {
                var next: [Int: Int] = [:]
                for j in b2j[a[i]] ?? [] {
                    if j < blo { continue }
                    if j >= bhi { break }
                    let k = (lengths[j - 1] ?? 0) + 1
                    next[j] = k
                    if k > best.2 { best = (i - k + 1, j - k + 1, k) }
                }
                lengths = next
            }
            while best.0 > alo, best.1 > blo, a[best.0 - 1] == b[best.1 - 1] { best = (best.0 - 1, best.1 - 1, best.2 + 1) }
            while best.0 + best.2 < ahi, best.1 + best.2 < bhi, a[best.0 + best.2] == b[best.1 + best.2] { best.2 += 1 }
            return best
        }
        var matched = 0
        var queue = [(0, a.count, 0, b.count)]
        while let (alo, ahi, blo, bhi) = queue.popLast() {
            let (i, j, k) = longest(alo, ahi, blo, bhi)
            guard k > 0 else { continue }
            matched += k
            if alo < i && blo < j { queue.append((alo, i, blo, j)) }
            if i + k < ahi && j + k < bhi { queue.append((i + k, ahi, j + k, bhi)) }
        }
        return 2 * Double(matched) / Double(a.count + b.count)
    }
}

private extension Unicode.Scalar {
    var isAlphanumeric: Bool { properties.isAlphabetic || properties.numericType != nil }
}

/// The evaluation set, from the repository (the self-test runs from a checkout).
func cleanupEvalCases() -> [CleanupEvalCase] {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    guard let text = try? String(contentsOf: root.appendingPathComponent("docs/specs/cleanup-eval.jsonl"), encoding: .utf8) else { return [] }
    return text.split(separator: "\n").compactMap { try? JSONDecoder().decode(CleanupEvalCase.self, from: Data($0.utf8)) }
}

private struct EvalRun {
    var c: CleanupEvalCase
    var output: CleanupOutput
    var milliseconds: Double
    var score: CleanupEvalScore.Result
}

/// Runs every case as the app does: the prefix warmed first (key-down), then `clean` with the app's budget.
@MainActor private func runCleanupEval(_ cases: [CleanupEvalCase], cleaner: TextCleaner, warm: Bool) -> [EvalRun] {
    var runs: [EvalRun] = []
    for c in cases {
        let input = c.cleanupInput
        if warm { _ = complete(60) { await cleaner.warm(style: input.style, level: input.level, category: input.context.app?.category ?? .other) } }
        let started = Date()
        let budget = DictationLimits.cleanupBudget(words: Dictation.countWords(c.input))
        guard case .success(let output)? = complete(30, { await cleaner.clean(input, budget: budget) }) else {
            check(false, "\(c.id): clean did not finish")
            continue
        }
        let ms = Date().timeIntervalSince(started) * 1000
        runs.append(EvalRun(c: c, output: output, milliseconds: ms, score: CleanupEvalScore.score(c, output: output.text)))
    }
    return runs
}

/// Prints the totals and the per-category table; returns the number of passes.
private func report(_ runs: [EvalRun], label: String) -> Int {
    let passes = runs.filter(\.score.pass).count
    let exact = runs.filter(\.score.exact).count
    print("  \(label): \(passes)/\(runs.count) pass (\(String(format: "%.1f", 100 * Double(passes) / Double(max(1, runs.count))))%), "
          + "\(exact) exact, \(runs.filter(\.score.rubric).count) rubric")
    var categories: [String] = []
    for run in runs where !categories.contains(run.c.cat) { categories.append(run.c.cat) }
    let table = categories.map { cat -> String in
        let rows = runs.filter { $0.c.cat == cat }
        return "\(cat) \(rows.filter(\.score.pass).count)/\(rows.count)"
    }
    print("    " + table.joined(separator: " · "))
    let llm = runs.filter { $0.output.skipReason == nil }.map(\.milliseconds).sorted()
    if !llm.isEmpty {
        print(String(format: "    LLM used on %d: p50 %.0f ms, p90 %.0f ms, max %.0f ms", llm.count, llm[llm.count / 2],
                     llm[Int(0.9 * Double(llm.count - 1))], llm.last ?? 0))
        var reasons: [String: Int] = [:]
        for run in runs { reasons[run.output.skipReason?.rawValue ?? "llm", default: 0] += 1 }
        print("    " + reasons.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
    }
    let verbose = ProcessInfo.processInfo.environment["SUPERFLOW_EVAL_VERBOSE"] != nil
    let failed = runs.filter { !$0.score.pass }
    if verbose {
        for run in failed {
            print("    ✗ \(run.c.id) [\(run.output.skipReason?.rawValue ?? "llm")] \(run.output.text.debugDescription) — "
                  + run.score.problems.joined(separator: "; "))
        }
    } else if !failed.isEmpty {
        print("    failing: " + failed.map(\.c.id).joined(separator: " "))
    }
    if let path = ProcessInfo.processInfo.environment["SUPERFLOW_EVAL_OUT"] {
        let lines = runs.compactMap { run -> String? in
            let record: [String: Any] = ["id": run.c.id, "output": run.output.text, "skip": run.output.skipReason?.rawValue ?? "llm",
                                         "ms": Int(run.milliseconds.rounded())]
            return (try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) }
        }
        try? (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
    return passes
}

/// Dictated questions are never answered and dictated instructions never obeyed, whatever else the output does.
private func checkNeverObeys(_ runs: [EvalRun], label: String) {
    for run in runs where ["questions", "injection"].contains(run.c.cat) {
        check(!(run.c.mustNot ?? []).contains { CleanupEvalScore.has(run.output.text, $0) },
              "\(label) \(run.c.id) answered or obeyed: \(run.output.text.debugDescription)")
    }
}

@MainActor private func cleanupEvalRulesOnly() {
    let cases = cleanupEvalCases()
    guard cases.count >= 200 else { check(false, "docs/specs/cleanup-eval.jsonl has \(cases.count) cases"); return }
    // The scorer itself, on cases whose verdict is known.
    check(CleanupEvalScore.similarity("abcd", "bcde") == 0.75 && CleanupEvalScore.similarity("", "") == 1, "difflib ratio")
    check(CleanupEvalScore.has("Use --save-dev here", "--save-dev") && !CleanupEvalScore.has("unhappy", "happy"), "word-bounded match")
    let runs = runCleanupEval(cases, cleaner: TextCleaner(), warm: false)
    let passes = report(runs, label: "rules only")
    check(passes >= rulesOnlyFloor, "rules-only passes \(passes) fell below \(rulesOnlyFloor)")
    checkNeverObeys(runs, label: "rules only")
}

@MainActor private func cleanupEvalWithModel() {
    guard let (url, id) = devGGUF() else { print("  (skipped: no cleanup GGUF in the dev model folders)"); return }
    let cases = cleanupEvalCases()
    guard !cases.isEmpty else { check(false, "no evaluation cases"); return }
    let engine = LlamaEngine(modelURL: url)
    guard case .success? = complete(300, { try await engine.load() }) else { check(false, "\(url.lastPathComponent) loads"); return }
    let cleaner = TextCleaner(model: engine, modelID: id)
    // One untimed run so the Metal pipelines are compiled before anything is measured.
    let warmUp = CleanupInput(transcript: Transcript(text: "so this is a warm up run for the model please ignore it"))
    _ = complete(60) { await cleaner.clean(warmUp, budget: 30) }
    let runs = runCleanupEval(cases, cleaner: cleaner, warm: true)
    let passes = report(runs, label: "rules + \(id)")
    if id == ModelCatalog.qwen35_2B.id || id == ModelCatalog.qwen35_4B.id {
        check(Double(passes) >= modelPassShare * Double(runs.count), "\(id) passes \(passes)/\(runs.count), below \(Int(modelPassShare * 100))%")
    }
    checkNeverObeys(runs, label: id)
    _ = complete { await engine.unload() }
}
