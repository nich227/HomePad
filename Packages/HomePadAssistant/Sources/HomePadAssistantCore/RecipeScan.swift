import Foundation

enum RecipeUnit: String, Sendable {
    case teaspoon, tablespoon, cup, fluidOunce, ounce, pound, gram, kilogram, milligram
    case milliliter, liter, pint, quart, gallon, inch, centimeter, millimeter
    case fahrenheit, celsius, degree, second, minute, hour, day, percent

    /// Seconds in one of this unit, for the units a kitchen timer counts.
    var seconds: Int? {
        switch self {
        case .second: 1
        case .minute: 60
        case .hour: 3_600
        default: nil
        }
    }

    /// Units that measure an ingredient.
    var measuresFood: Bool {
        switch self {
        case .teaspoon, .tablespoon, .cup, .fluidOunce, .ounce, .pound, .gram, .kilogram, .milligram, .milliliter, .liter, .pint, .quart, .gallon:
            true
        default:
            false
        }
    }

    /// Units that "a" or "an" in front of them makes an amount of one. "A second" is left out:
    /// it is nearly always the one after the first.
    var followsArticle: Bool {
        measuresFood || self == .minute || self == .hour
    }

    /// Every spelling that means the same unit. Two texts agree on an amount when the number
    /// and the unit behind the spelling are the same.
    static let aliases: [String: RecipeUnit] = {
        let spellings: [RecipeUnit: [String]] = [
            .teaspoon: ["teaspoon", "teaspoons", "tsp", "tsps"],
            .tablespoon: ["tablespoon", "tablespoons", "tbsp", "tbsps", "tbs", "tbl"],
            .cup: ["cup", "cups"],
            .ounce: ["ounce", "ounces", "oz"],
            .pound: ["pound", "pounds", "lb", "lbs"],
            .gram: ["gram", "grams", "g", "gr"],
            .kilogram: ["kilogram", "kilograms", "kg", "kilo", "kilos"],
            .milligram: ["milligram", "milligrams", "mg"],
            .milliliter: ["milliliter", "milliliters", "millilitre", "millilitres", "ml"],
            .liter: ["liter", "liters", "litre", "litres", "l"],
            .pint: ["pint", "pints", "pt"],
            .quart: ["quart", "quarts", "qt", "qts"],
            .gallon: ["gallon", "gallons", "gal"],
            .inch: ["inch", "inches"],
            .centimeter: ["centimeter", "centimeters", "centimetre", "centimetres", "cm"],
            .millimeter: ["millimeter", "millimeters", "millimetre", "millimetres", "mm"],
            .fahrenheit: ["f", "fahrenheit"],
            .celsius: ["celsius", "centigrade"],
            .second: ["second", "seconds", "sec", "secs"],
            .minute: ["minute", "minutes", "min", "mins"],
            .hour: ["hour", "hours", "hr", "hrs", "h"],
            .day: ["day", "days"],
            .percent: ["%", "percent"],
        ]
        var table: [String: RecipeUnit] = [:]
        for (unit, words) in spellings {
            for word in words {
                table[word] = unit
            }
        }
        return table
    }()
}

/// A number in a recipe and the unit that follows it, if any.
struct RecipeQuantity: Equatable, Sendable {
    /// What two quantities are compared by: the value to a thousandth, and the unit.
    struct Key: Hashable, Sendable {
        let thousandths: Int
        let unit: RecipeUnit?
    }

    let value: Double
    var unit: RecipeUnit?
    /// Written as a word, such as "two".
    let isSpelled: Bool
    /// Positions of the number and of the token after its unit, among the scan's tokens.
    let start: Int
    let end: Int

    /// A page can hold a digit string of any length. The value is capped so that it always
    /// fits the integers it is turned into.
    init(value: Double, unit: RecipeUnit?, isSpelled: Bool, start: Int, end: Int) {
        self.value = value.isFinite ? min(value, 1_000_000) : 1_000_000
        self.unit = unit
        self.isSpelled = isSpelled
        self.start = start
        self.end = end
    }

    var key: Key {
        Key(thousandths: Int((value * 1_000).rounded()), unit: unit)
    }
}

/// A time a text states. A range such as "8 to 10 minutes" is one expression.
struct RecipeDuration: Equatable, Sendable {
    /// The time itself, or the low end of a range.
    let seconds: Int
    /// Every value a timer for this expression may take.
    let alternatives: [Int]
}

/// One reading of a text: its numbers with their units, and the words that carry meaning.
struct RecipeScan: Sendable {
    enum Token: Equatable, Sendable {
        case number(Double, spelled: Bool)
        case word(String)
        case dash
        case mark(Character)
    }

    let quantities: [RecipeQuantity]
    /// Stems of the words that are not numbers, units, or function words, in order.
    let words: [String]
    private let tokens: [Token]
    /// For each token, the stem it adds to `words`, or nil.
    private let stems: [String?]

    init(_ text: String) {
        let tokens = Self.tokens(of: text)
        var quantities: [RecipeQuantity] = []
        var unitTokens: Set<Int> = []
        for (index, token) in tokens.enumerated() {
            switch token {
            case .number(let value, let spelled):
                var next = index + 1
                if next < tokens.count, tokens[next] == .dash {
                    next += 1
                }
                var unit: RecipeUnit?
                var end = index + 1
                if let found = Self.unit(at: next, in: tokens, value: value) {
                    unit = found.unit
                    end = next + found.length
                    unitTokens.formUnion(next..<end)
                }
                quantities.append(RecipeQuantity(value: value, unit: unit, isSpelled: spelled, start: index, end: end))
            case .word("a"), .word("an"):
                // "a cup" and "an hour" state an amount of one. A one-letter or two-letter
                // spelling after the article is far more often a word than a unit.
                guard let word = Self.word(at: index + 1, in: tokens), word.count > 2,
                      let unit = RecipeUnit.aliases[word], unit.followsArticle else { continue }
                unitTokens.insert(index + 1)
                quantities.append(RecipeQuantity(value: 1, unit: unit, isSpelled: true, start: index, end: index + 2))
            default:
                continue
            }
        }
        // "8 to 10 minutes" and "9x13-inch" give the first number the unit of the second.
        for index in stride(from: quantities.count - 2, through: 0, by: -1) where quantities[index].unit == nil {
            let next = quantities[index + 1]
            if let unit = next.unit, Self.isRangeConnector(tokens[quantities[index].end..<next.start]) {
                quantities[index].unit = unit
            }
        }
        let stems: [String?] = tokens.enumerated().map { index, token in
            guard case .word(let word) = token, !unitTokens.contains(index) else { return nil }
            guard word.count > 1, !RecipeWords.functionWords.contains(word) else { return nil }
            return RecipeWords.stem(word)
        }
        self.tokens = tokens
        self.quantities = quantities
        self.stems = stems
        words = stems.compactMap { $0 }
    }

    /// The amounts a rewrite must carry over, in order: every number in digits, every number
    /// with a unit, and every number word except a bare "one", which is as often a pronoun.
    var required: [RecipeQuantity] {
        quantities.filter { !$0.isSpelled || $0.unit != nil || $0.value != 1 }
    }

    /// How often each required amount occurs.
    var requiredCounts: [RecipeQuantity.Key: Int] {
        required.reduce(into: [:]) { $0[$1.key, default: 0] += 1 }
    }

    /// The words next to an amount, which say what it measures: up to three before it and up
    /// to three after it, without crossing another number or the end of a sentence.
    func context(of quantity: RecipeQuantity) -> (before: Set<String>, after: Set<String>) {
        var before: Set<String> = []
        var index = quantity.start - 1
        while index >= 0, before.count < 3, !Self.endsContext(tokens[index]) {
            if let stem = stems[index] {
                before.insert(stem)
            }
            index -= 1
        }
        var after: Set<String> = []
        index = quantity.end
        while index < tokens.count, after.count < 3, !Self.endsContext(tokens[index]) {
            if let stem = stems[index] {
                after.insert(stem)
            }
            index += 1
        }
        return (before, after)
    }

    private static func endsContext(_ token: Token) -> Bool {
        switch token {
        case .number: true
        case .mark(let mark): ".;!?".contains(mark)
        case .word, .dash: false
        }
    }

    /// Every quantity, counting numbers written as words.
    var allKeys: Set<RecipeQuantity.Key> {
        Set(quantities.map(\.key))
    }

    /// Whether the text opens with a measured amount, as an ingredient line does.
    var startsWithMeasure: Bool {
        guard let first = quantities.first else { return false }
        return first.start == 0 && first.unit?.measuresFood == true
    }

    /// The times the text states, in order. "1 hour 30 minutes" is one time, and so is a range.
    var durations: [RecipeDuration] {
        let timed = quantities.compactMap { quantity in
            quantity.unit?.seconds.map { (quantity: quantity, unit: $0, seconds: Int((quantity.value * Double($0)).rounded())) }
        }
        var result: [RecipeDuration] = []
        var index = 0
        while index < timed.count {
            let first = timed[index]
            if index + 1 < timed.count {
                let second = timed[index + 1]
                let between = tokens[first.quantity.end..<second.quantity.start]
                if Self.isRangeConnector(between) {
                    result.append(RecipeDuration(seconds: min(first.seconds, second.seconds), alternatives: [first.seconds, second.seconds]))
                    index += 2
                    continue
                }
                let joins = between.isEmpty || between.elementsEqual([.word("and")]) || between.elementsEqual([.mark(",")])
                if joins, first.unit > second.unit {
                    let total = first.seconds + second.seconds
                    result.append(RecipeDuration(seconds: total, alternatives: [total]))
                    index += 2
                    continue
                }
            }
            result.append(RecipeDuration(seconds: first.seconds, alternatives: [first.seconds]))
            index += 1
        }
        return result
    }

    /// The timer for a text nobody rewrote: its one stated time, or none when it states
    /// several and there is no telling which one a cook would time.
    var singleTimer: Int? {
        let durations = durations
        guard durations.count == 1, RecipeScan.isTimer(durations[0].seconds) else { return nil }
        return durations[0].seconds
    }

    static func isTimer(_ seconds: Int) -> Bool {
        (1...RecipeLimits.maxTimerSeconds).contains(seconds)
    }

    // MARK: Units

    private static func word(at index: Int, in tokens: [Token]) -> String? {
        guard index < tokens.count, case .word(let word) = tokens[index] else { return nil }
        return word
    }

    private static func unit(at index: Int, in tokens: [Token], value: Double) -> (unit: RecipeUnit, length: Int)? {
        guard let word = word(at: index, in: tokens) else { return nil }
        switch word {
        case "\u{00B0}", "degree", "degrees", "deg":
            switch self.word(at: index + 1, in: tokens) {
            case "f", "fahrenheit": return (.fahrenheit, 2)
            case "c", "celsius", "centigrade": return (.celsius, 2)
            default: return (.degree, 1)
            }
        case "c":
            // A lone "c" is cups in a small amount and Celsius in an oven setting.
            return (value >= 60 ? .celsius : .cup, 1)
        case "fl", "fluid":
            var next = index + 1
            if next < tokens.count, tokens[next] == .mark(".") {
                next += 1
            }
            guard let ounce = self.word(at: next, in: tokens), RecipeUnit.aliases[ounce] == .ounce else { return nil }
            return (.fluidOunce, next - index + 1)
        default:
            return RecipeUnit.aliases[word].map { ($0, 1) }
        }
    }

    private static func isRangeConnector(_ between: ArraySlice<Token>) -> Bool {
        guard between.count == 1, let token = between.first else { return false }
        return token == .dash || [.word("to"), .word("or"), .word("x"), .word("by")].contains(token)
    }

    // MARK: Tokens

    private static let fractions: [Character: String] = [
        "\u{00BD}": "1/2", "\u{2153}": "1/3", "\u{2154}": "2/3", "\u{00BC}": "1/4", "\u{00BE}": "3/4",
        "\u{2155}": "1/5", "\u{2156}": "2/5", "\u{2157}": "3/5", "\u{2158}": "4/5", "\u{2159}": "1/6",
        "\u{215A}": "5/6", "\u{215B}": "1/8", "\u{215C}": "3/8", "\u{215D}": "5/8", "\u{215E}": "7/8",
    ]

    private static let spelledNumbers: [String: Double] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
    ]

    /// Rewrites the characters that spell the same thing in more than one way, so that "½" and
    /// "1/2", or two kinds of dash, read alike.
    private static func normalized(_ text: String) -> [Character] {
        var result: [Character] = []
        for character in text.lowercased() {
            if let fraction = fractions[character] {
                if result.last?.isWhitespace != true {
                    result.append(" ")
                }
                result.append(contentsOf: fraction)
            } else if "\u{2010}\u{2011}\u{2012}\u{2013}\u{2014}\u{2212}".contains(character) {
                result.append("-")
            } else if character == "\u{2044}" {
                result.append("/")
            } else if character == "\u{00BA}" || character == "\u{02DA}" {
                result.append("\u{00B0}")
            } else if character == "\u{00D7}" {
                result.append("x")
            } else {
                result.append(character)
            }
        }
        return result
    }

    private static func digit(_ character: Character) -> Double? {
        guard character.isASCII, let value = character.wholeNumberValue else { return nil }
        return Double(value)
    }

    private static func isDigit(_ characters: [Character], _ index: Int) -> Bool {
        index < characters.count && digit(characters[index]) != nil
    }

    /// Reads a run of digits starting at `index` and moves `index` past it.
    private static func whole(_ characters: [Character], _ index: inout Int) -> Double {
        var value = 0.0
        while index < characters.count, let digit = digit(characters[index]) {
            value = value * 10 + digit
            index += 1
        }
        return value
    }

    /// Reads "12", "1,000", "1.5", "1/2", "1 1/2", or "1-1/2" starting at a digit.
    private static func number(_ characters: [Character], _ index: inout Int) -> Double {
        var value = whole(characters, &index)
        while isDigit(characters, index + 1), isDigit(characters, index + 2), isDigit(characters, index + 3),
              !isDigit(characters, index + 4), characters[index] == "," {
            index += 1
            value = value * 1_000 + whole(characters, &index)
        }
        if isDigit(characters, index + 1), characters[index] == "." {
            index += 1
            let start = index
            let fraction = whole(characters, &index)
            return value + fraction / pow(10, Double(index - start))
        }
        if isDigit(characters, index + 1), characters[index] == "/" {
            index += 1
            let denominator = whole(characters, &index)
            return denominator == 0 ? value : value / denominator
        }
        // A whole number followed by a fraction is one amount: "1 1/2" and "1-1/2".
        var ahead = index + 1
        if isDigit(characters, ahead), characters[index] == " " || characters[index] == "-" {
            let numerator = whole(characters, &ahead)
            if isDigit(characters, ahead + 1), characters[ahead] == "/" {
                ahead += 1
                let denominator = whole(characters, &ahead)
                if denominator != 0 {
                    index = ahead
                    return value + numerator / denominator
                }
            }
        }
        return value
    }

    private static func tokens(of text: String) -> [Token] {
        let characters = normalized(text)
        var tokens: [Token] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if digit(character) != nil {
                tokens.append(.number(number(characters, &index), spelled: false))
            } else if character.isLetter {
                var word = ""
                while index < characters.count, characters[index].isLetter || "'\u{2019}".contains(characters[index]) {
                    if characters[index].isLetter {
                        word.append(characters[index])
                    }
                    index += 1
                }
                if let value = spelledNumbers[word] {
                    tokens.append(.number(value, spelled: true))
                } else {
                    tokens.append(.word(word))
                }
            } else {
                if character == "\u{00B0}" || character == "%" {
                    tokens.append(.word(String(character)))
                } else if character == "-" {
                    tokens.append(.dash)
                } else if !character.isWhitespace {
                    tokens.append(.mark(character))
                }
                index += 1
            }
        }
        return tokens
    }
}

/// Which words carry a recipe's meaning, and how two forms of one word are matched.
enum RecipeWords {
    /// Words a rewrite may add or drop freely. Words that change what a cook does, such as
    /// "not", "or", "before", and "until", are deliberately absent.
    static let functionWords: Set<String> = [
        "the", "an", "and", "of", "to", "in", "into", "on", "onto", "at", "by", "for", "from", "with",
        "as", "it", "its", "them", "they", "this", "that", "these", "those", "is", "are", "be", "been",
        "was", "will", "should", "can", "you", "your", "then", "so", "if", "but", "up", "out", "off",
        "over", "about", "each", "all", "when", "while", "once", "again", "also", "just", "now", "next",
        "first", "finally", "lastly", "meanwhile",
    ]

    /// Words whose loss turns an instruction into a different one: the ones that reverse or
    /// order it, and the ones that set the heat or the lid.
    static let protected: Set<String> = Set([
        "not", "no", "never", "without", "dont", "before", "after", "until", "unless", "or",
        "low", "medium", "high", "covered", "uncovered",
    ].map(stem))

    /// Plain verbs a short step may use even when the page did not. None names a food, an
    /// amount, or a technique.
    static let neutralVerbs: Set<String> = Set(["add", "combine", "mix", "place", "put", "set", "let", "use", "make", "take", "keep", "start", "begin", "continue", "finish", "serve", "prepare", "prep"].map(stem))

    /// Words in an ingredient line that describe or portion the ingredient and do not name it.
    static let descriptors: Set<String> = Set([
        "chopped", "diced", "minced", "sliced", "grated", "shredded", "peeled", "crushed", "melted",
        "softened", "beaten", "divided", "fresh", "freshly", "finely", "roughly", "thinly", "lightly",
        "large", "small", "medium", "taste", "optional", "needed", "room", "temperature", "cut",
        "piece", "more", "plus", "such", "packed", "cold", "warm", "or", "other", "serving", "garnish",
        "clove", "sprig", "stalk", "bunch", "stick", "pinch", "dash", "slice", "package", "jar",
        "bottle", "handful", "head",
    ].map(stem))

    /// Reduces a word to a form shared by its plural and its verb endings, so that "bake",
    /// "baked", and "baking" match. It is only ever used to compare two texts of one recipe.
    static func stem(_ word: String) -> String {
        var stem = word
        if stem.count > 4, stem.hasSuffix("ies") {
            stem.removeLast(3)
            stem.append("y")
        } else if stem.count > 4, ["ches", "shes", "sses", "xes", "zes", "oes"].contains(where: stem.hasSuffix) {
            stem.removeLast(2)
        } else if stem.count > 3, stem.hasSuffix("s"), !stem.hasSuffix("ss") {
            stem.removeLast()
        }
        if stem.count > 4, stem.hasSuffix("ing") {
            stem.removeLast(3)
        } else if stem.count > 3, stem.hasSuffix("ed") {
            stem.removeLast(2)
        }
        if stem.count > 3, stem.hasSuffix("e") {
            stem.removeLast()
        }
        if stem.count > 2, stem.dropLast().last == stem.last {
            stem.removeLast()
        }
        return stem
    }
}
