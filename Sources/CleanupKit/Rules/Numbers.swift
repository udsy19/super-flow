import Foundation

/// Spoken numbers, times, dates, money and percentages written the way people type them (behaviour.md §8.1):
/// "twenty five" → "25", "three point five percent" → "3.5%", "ten thirty pm" → "10:30 PM", "march third twenty
/// twenty six" → "March 3, 2026". Numbers under ten stay words in running text ("three ideas") unless they carry a
/// unit, a time or a date. Digits read out one by one become one number, never half of one ("one twenty three Main
/// Street" → "123 Main Street", "five five five, one two three, four five six seven" → "555-123-4567").
enum NumberWords {
    static let ones: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
        "nineteen": 19,
    ]
    static let tens: [String: Int] = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]
    static let scales: [String: Int] = ["thousand": 1_000, "million": 1_000_000, "billion": 1_000_000_000]
    static let ordinalOnes: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10,
        "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14, "fifteenth": 15, "sixteenth": 16, "seventeenth": 17,
        "eighteenth": 18, "nineteenth": 19,
    ]
    static let ordinalTens: [String: Int] = [
        "twentieth": 20, "thirtieth": 30, "fortieth": 40, "fiftieth": 50, "sixtieth": 60, "seventieth": 70, "eightieth": 80, "ninetieth": 90,
    ]
    private static let meridiem: [String: String] = ["am": "AM", "pm": "PM", "a.m.": "AM", "p.m.": "PM"]
    private static let timePrepositions: Set<String> = ["at", "by", "around", "until", "till", "from", "before", "after", "since", "to"]
    private static let monthPrepositions: Set<String> = ["in", "of", "since", "until", "till", "by", "last", "next", "this", "early", "late", "mid", "from", "through"]

    /// A number word or digits ("3", "3:30", "1,000").
    static func isNumeric(_ lower: String) -> Bool {
        if let first = lower.unicodeScalars.first, CharacterSet.decimalDigits.contains(first) { return true }
        return lower.split(separator: "-").allSatisfy {
            let part = String($0)
            return ones[part] != nil || tens[part] != nil || part == "hundred" || scales[part] != nil || ordinalOnes[part] != nil || ordinalTens[part] != nil
        }
    }

    /// `codes`: the text goes where status codes and versions are common (documents, AI and coding apps, terminals), so
    /// "four oh four" is 404.
    static func apply(_ words: inout Words, codes: Bool = false) {
        var i = 0
        while i < words.count {
            if let step = rewrite(words, at: i, codes: codes) {
                words.replace(i..<i + step.consumed, with: step.words)
                if step.yearComma { words[i + 1].gap = ", " }
                if let month = step.capitalizeMonthBefore { words[month].text = words[month].text.capitalized }
                i += step.words.count
            } else {
                if isMonth(words, at: i) { words[i].text = words[i].text.capitalized }
                i += 1
            }
        }
    }

    // MARK: Parsing

    private struct Part { var word: Int; var text: String }

    /// The hyphen-split parts of the words from `index` on, while the words are joined by plain spaces.
    private static func parts(_ words: Words, from index: Int) -> [Part] {
        var result: [Part] = []
        var i = index
        while i < words.count && !words[i].isPlaceholder && (i == index || Gap.isSpace(words[i].gap)) {
            result += words[i].lower.split(separator: "-").map { Part(word: i, text: String($0)) }
            i += 1
            if result.count > 12 { break }
        }
        return result
    }

    struct Parsed {
        var value: Int
        /// Parts consumed.
        var length: Int
        var isOrdinal = false
        /// "nineteen ninety nine", "twenty oh five".
        var isYear = false
        /// "three point five" → "3.5".
        var decimal: String?
    }

    /// Reads the longest number at the start of `parts`.
    private static func parse(_ parts: [String]) -> Parsed? {
        guard let first = parts.first else { return nil }
        if let year = parseYear(parts) { return year }
        if parts.count >= 4, parts.prefix(4).allSatisfy({ (ones[$0] ?? 10) < 10 }) {
            // A run of single digits ("five five five one two") is read out digit by digit: a code or a phone number.
            let run = parts.prefix { (ones[$0] ?? 10) < 10 }
            return Parsed(value: -1, length: run.count, decimal: run.map { String(ones[$0]!) }.joined())
        }
        guard ones[first] != nil || tens[first] != nil || ordinalOnes[first] != nil || ordinalTens[first] != nil else { return nil }

        var total = 0, current = 0, used = 0, lastScale = Int.max
        enum Last { case none, unit, teen, ten, hundred, scale }
        var last = Last.none
        var ordinal = false
        loop: while used < parts.count {
            let part = parts[used]
            if part == "and", last == .hundred || last == .scale, used + 1 < parts.count,
               ones[parts[used + 1]] != nil || tens[parts[used + 1]] != nil || ordinalOnes[parts[used + 1]] != nil {
                used += 1; continue
            }
            if let v = ones[part] ?? ordinalOnes[part] {
                if last == .unit || last == .teen || (last == .ten && v >= 10) { break loop }
                current += v; last = v < 10 ? .unit : .teen
                ordinal = ordinalOnes[part] != nil
            } else if let v = tens[part] ?? ordinalTens[part] {
                if last == .unit || last == .teen || last == .ten { break loop }
                current += v; last = .ten
                ordinal = ordinalTens[part] != nil
            } else if part == "hundred" || part == "hundredth" {
                if current == 0 || current >= 100 || last == .hundred { break loop }
                current *= 100; last = .hundred
                ordinal = part == "hundredth"
            } else if let scale = scales[part] {
                if current == 0 || scale >= lastScale { break loop }
                total += current * scale; current = 0; lastScale = scale; last = .scale
            } else { break loop }
            used += 1
            if ordinal { break }
        }
        guard used > 0 else { return nil }
        var parsed = Parsed(value: total + current, length: used, isOrdinal: ordinal)
        // "three point five", "zero point two five".
        // "three point five", "zero point two five", and versions: "two point four point one" → "2.4.1".
        var decimal = String(parsed.value)
        while !ordinal, parsed.length + 1 < parts.count, parts[parsed.length] == "point" {
            let digits = parts[(parsed.length + 1)...].prefix { (ones[$0] ?? 10) < 10 || $0 == "oh" }
            guard !digits.isEmpty else { break }
            decimal += "." + digits.map { $0 == "oh" ? "0" : String(ones[$0]!) }.joined()
            parsed.decimal = decimal
            parsed.length += 1 + digits.count
        }
        return parsed
    }

    /// "nineteen ninety nine" → 1999, "twenty twenty six" → 2026, "twenty oh five" → 2005.
    private static func parseYear(_ parts: [String]) -> Parsed? {
        guard parts.count >= 2, let century = ["nineteen": 19, "twenty": 20][parts[0]] else { return nil }
        let rest = parts[1]
        if rest == "oh", parts.count >= 3, let unit = ones[parts[2]], unit < 10 {
            return Parsed(value: century * 100 + unit, length: 3, isYear: true)
        }
        if let teen = ones[rest], teen >= 10 { return Parsed(value: century * 100 + teen, length: 2, isYear: true) }
        if let ten = tens[rest] {
            if parts.count >= 3, let unit = ones[parts[2]], unit > 0, unit < 10 {
                return Parsed(value: century * 100 + ten + unit, length: 3, isYear: true)
            }
            return Parsed(value: century * 100 + ten, length: 2, isYear: true)
        }
        return nil
    }

    // MARK: Rendering

    private struct Rewrite {
        var consumed: Int
        var words: [String]
        var capitalizeMonthBefore: Int?
        /// "March 3, 2026": the year follows a comma.
        var yearComma = false
    }

    private static func rewrite(_ words: Words, at i: Int, codes: Bool) -> Rewrite? {
        if let phone = digitGroups(words, at: i) { return phone }
        let partList = parts(words, from: i)
        var texts = partList.map(\.text)
        // "a hundred dollars" → "$100": "a" counts as one before a scale, for amounts only.
        let indefinite = texts.first == "a" && texts.count > 1 && (texts[1] == "hundred" || scales[texts[1]] != nil)
        if indefinite { texts[0] = "one" }
        guard let parsed = parse(texts) else { return nil }
        // Only whole words are rewritten: "twenty-something" stays.
        let lastPart = parsed.length - 1
        guard lastPart + 1 == partList.count || partList[lastPart].word != partList[lastPart + 1].word else { return nil }
        let end = partList[lastPart].word + 1
        let next = end < words.count && Gap.isSpace(words[end].gap) ? words[end].lower : nil
        let afterNext = end + 1 < words.count && Gap.isSpace(words[end + 1].gap) ? words[end + 1].lower : nil
        let previous = i > 0 ? words[i - 1].lower : nil

        if let digits = parsed.decimal, parsed.value == -1 { return Rewrite(consumed: end - i, words: [digits]) }
        let number = parsed.decimal ?? format(parsed.value)

        if !parsed.isOrdinal && !parsed.isYear {
            // Percentages and money.
            if next == "percent" { return Rewrite(consumed: end - i + 1, words: ["\(number)%"]) }
            if next == "per", afterNext == "cent" { return Rewrite(consumed: end - i + 2, words: ["\(number)%"]) }
            // "one point two million dollars" → "$1.2 million".
            if parsed.decimal != nil, let next, let scale = ["million", "billion"].first(where: { $0 == next }),
               afterNext == "dollars" || afterNext == "dollar" {
                return Rewrite(consumed: end - i + 2, words: ["$\(number)", scale])
            }
            if next == "dollars" || next == "dollar" {
                if let cents = centsAfter(words, at: end + 1) { return Rewrite(consumed: cents.end - i, words: ["$\(number).\(cents.text)"]) }
                return Rewrite(consumed: end - i + 1, words: ["$\(number)"])
            }
            if next == "euros" || next == "euro" { return Rewrite(consumed: end - i + 1, words: ["€\(number)"]) }
            if next == "cents" { return Rewrite(consumed: end - i, words: [number]) }
            if indefinite { return nil }
            // Times: "three pm", "ten thirty a.m.", "seven forty five pm", "three o'clock", "at three thirty".
            if parsed.decimal == nil, (1...12).contains(parsed.value), let time = time(words, hour: parsed.value, from: i, end: end) {
                return time
            }
            if parsed.decimal == nil, parsed.length == 1, (1...9).contains(parsed.value),
               let read = digitRead(partList, unit: parsed.value, codes: codes),
               read.end == partList.count || partList[read.end].word != partList[read.end - 1].word {
                return Rewrite(consumed: partList[read.end - 1].word + 1 - i, words: [read.text])
            }
        }
        // Dates: "March third" → "March 3", with an optional year → "March 3, 2026".
        if let previous, isMonthName(previous), parsed.decimal == nil, !parsed.isYear, (1...31).contains(parsed.value) {
            if let year = yearAfter(words, at: end) {
                return Rewrite(consumed: year.end - i, words: [String(parsed.value), String(year.value)], capitalizeMonthBefore: i - 1,
                               yearComma: true)
            }
            return Rewrite(consumed: end - i, words: [String(parsed.value)], capitalizeMonthBefore: i - 1)
        }
        if parsed.isYear { return Rewrite(consumed: end - i, words: [String(parsed.value)]) }
        if parsed.isOrdinal {
            // "the third of March" → "the 3rd of March"; other ordinals under ten stay words ("first", "second").
            let beforeMonth = next == "of" && afterNext.map(isMonthName) == true
            guard parsed.value >= 10 || beforeMonth else { return nil }
            return Rewrite(consumed: end - i, words: [ordinal(parsed.value)])
        }
        if parsed.decimal != nil { return Rewrite(consumed: end - i, words: [number]) }
        if parsed.value >= 1_000_000, parsed.value % 1_000_000 == 0 {
            let (amount, name) = parsed.value % 1_000_000_000 == 0 ? (parsed.value / 1_000_000_000, "billion") : (parsed.value / 1_000_000, "million")
            if amount < 1000 { return Rewrite(consumed: end - i, words: [String(amount), name]) }
        }
        guard parsed.value >= 10 else { return nil }
        return Rewrite(consumed: end - i, words: [number])
    }

    /// A digit read out before a two-digit number: "one twenty three" → "123" (an address, a room, a flight), and with
    /// `codes` "four oh four" → "404". Times were tried first ("at one twenty three" is 1:23). `end` is the index in
    /// `parts` after the read.
    private static func digitRead(_ parts: [Part], unit: Int, codes: Bool) -> (text: String, end: Int)? {
        guard parts.count >= 2 else { return nil }
        let second = parts[1].text
        if codes, second == "oh", parts.count >= 3, let last = ones[parts[2].text], last < 10 {
            return ("\(unit)0\(last)", 3)
        }
        if let ten = tens[second], parts.count >= 3, let last = ones[parts[2].text], (1...9).contains(last) {
            return (String(unit * 100 + ten + last), 3)
        }
        return nil
    }

    /// Groups of digits read one by one with the commas speech engines put between them, as in a phone number
    /// ("five five five, one two three, four five six seven" → "555-123-4567"): the whole run or nothing.
    private static func digitGroups(_ words: Words, at i: Int) -> Rewrite? {
        func digit(_ k: Int, first: Bool) -> String? {
            guard !words[k].isPlaceholder else { return nil }
            let lower = words[k].lower
            if let value = ones[lower], value < 10 { return String(value) }
            if !first, lower == "oh" { return "0" }
            if lower.count == 1, lower.allSatisfy(\.isNumber) { return lower }
            return nil
        }
        var groups: [String] = []
        var end = i
        var j = i
        while j < words.count {
            var group = ""
            var k = j
            while k < words.count, k == j || Gap.isSpace(words[k].gap), let d = digit(k, first: k == j) { group += d; k += 1 }
            guard (3...4).contains(group.count) else { break }
            groups.append(group)
            end = k
            guard k < words.count, Gap.hasComma(words[k].gap), Gap.withoutCommas(words[k].gap) == " " else { break }
            j = k
        }
        guard groups.count >= 2, groups.joined().count >= 7 else { return nil }
        return Rewrite(consumed: end - i, words: [groups.joined(separator: "-")])
    }

    private static func time(_ words: Words, hour: Int, from i: Int, end: Int) -> Rewrite? {
        var cursor = end
        var minutes: Int?
        let minuteParts = parts(words, from: cursor)
        if cursor < words.count, Gap.isSpace(words[cursor].gap), let first = minuteParts.first?.text {
            if first == "oh", minuteParts.count >= 2, let unit = ones[minuteParts[1].text], unit < 10 {
                minutes = unit; cursor = minuteParts[1].word + 1
            } else if let parsed = parse(minuteParts.map(\.text)), !parsed.isOrdinal, !parsed.isYear, parsed.decimal == nil,
                      (10...59).contains(parsed.value) {
                minutes = parsed.value; cursor = minuteParts[parsed.length - 1].word + 1
            }
        }
        let clock = minutes.map { "\(hour):" + String(format: "%02d", $0) } ?? String(hour)
        let nextWord = cursor < words.count && Gap.isSpace(words[cursor].gap) ? words[cursor].lower : nil
        let afterPreposition = i > 0 && timePrepositions.contains(words[i - 1].lower)
        // Bare "am" is also the verb ("which one am I"), so it needs minutes or "at"/"by"… before the hour.
        if let next = nextWord, let mark = meridiem[next], next != "am" || minutes != nil || afterPreposition {
            return Rewrite(consumed: cursor + 1 - i, words: [clock, mark])
        }
        if nextWord == "a" || nextWord == "p", cursor + 1 < words.count, words[cursor + 1].lower == "m", Gap.isSpace(words[cursor + 1].gap) {
            return Rewrite(consumed: cursor + 2 - i, words: [clock, nextWord == "a" ? "AM" : "PM"])
        }
        if nextWord == "o'clock" || nextWord == "o’clock", minutes == nil { return Rewrite(consumed: cursor + 1 - i, words: [clock, "o'clock"]) }
        if minutes != nil, afterPreposition { return Rewrite(consumed: cursor - i, words: [clock]) }
        return nil
    }

    /// "and fifty cents" after "dollars".
    private static func centsAfter(_ words: Words, at index: Int) -> (text: String, end: Int)? {
        guard index < words.count, words[index].lower == "and" else { return nil }
        let list = parts(words, from: index + 1)
        guard let parsed = parse(list.map(\.text)), !parsed.isOrdinal, parsed.decimal == nil, (1...99).contains(parsed.value) else { return nil }
        let end = list[parsed.length - 1].word + 1
        guard end < words.count, words[end].lower == "cents" || words[end].lower == "cent" else { return nil }
        return (String(format: "%02d", parsed.value), end + 1)
    }

    /// A year after a date: "twenty twenty six" or "two thousand twenty six".
    private static func yearAfter(_ words: Words, at index: Int) -> (value: Int, end: Int)? {
        guard index < words.count, Gap.isSpace(words[index].gap) || Gap.hasComma(words[index].gap) else { return nil }
        if let digits = Int(words[index].text), (1000...2999).contains(digits) { return (digits, index + 1) }
        let list = parts(words, from: index)
        guard let parsed = parse(list.map(\.text)), !parsed.isOrdinal, parsed.decimal == nil,
              parsed.isYear || (1000...2999).contains(parsed.value) else { return nil }
        return (parsed.value, list[parsed.length - 1].word + 1)
    }

    private static func isMonthName(_ lower: String) -> Bool { Lexicon.months.contains(lower) }

    /// A month name used as a month: before a day number, or after "in", "since", "next"…; "may" and "march" stay
    /// verbs elsewhere.
    private static func isMonth(_ words: Words, at i: Int) -> Bool {
        let lower = words[i].lower
        guard isMonthName(lower), words[i].text.first?.isLowercase == true else { return false }
        if i > 0, monthPrepositions.contains(words[i - 1].lower), Gap.isSpace(words[i].gap) { return lower != "may" || words[i - 1].lower != "this" }
        // "march 3" from an engine that already wrote the day in digits.
        return i + 1 < words.count && Gap.isSpace(words[i + 1].gap) && words[i + 1].text.first?.isNumber == true
    }

    static func format(_ value: Int) -> String {
        guard value >= 10_000 else { return String(value) }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func ordinal(_ value: Int) -> String {
        let suffix: String
        switch (value % 10, value % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(value)\(suffix)"
    }
}
