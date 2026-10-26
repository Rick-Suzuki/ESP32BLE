import Foundation

enum EnglishHomophones {
    // MARK: - BM:🅱️ Each group is a direct pronunciation equivalence. A spelling may appear in multiple groups, and matching checks only for a shared group ID rather than transitive membership.
    static let groups: [[String]] = [
        ["right", "write", "rite"],
        ["hi", "high"],
        ["there", "their", "they're"],
        ["to", "too", "two"],
        ["hear", "here"],
        ["no", "know"],
        ["your", "you're"],
        ["by", "buy", "bye"],
        ["one", "won"],
        ["sea", "see"],
        ["sun", "son"],
        ["flower", "flour"],
        ["pair", "pear", "pare"],
        ["peace", "piece"],
        ["plain", "plane"],
        ["week", "weak"],
        ["brake", "break"],
        ["blue", "blew"],
        ["be", "bee"],
        ["ate", "eight"],
        ["for", "four", "fore"],
        ["road", "rode"],
        ["weather", "whether"],
        ["which", "witch"],
        ["where", "wear", "ware"],
        ["new", "knew"],
        ["night", "knight"],
        ["mail", "male"],
        ["made", "maid"],
        ["wait", "weight"],
        ["red", "read"],
        ["read", "reed"],
        ["aloud", "allowed"],
        ["altar", "alter"],
        ["all", "awl"],
        ["air", "heir"],
        ["arc", "ark"],
        ["ascent", "assent"],
        ["bail", "bale"],
        ["ball", "bawl"],
        ["band", "banned"],
        ["base", "bass"],
        ["bean", "been"],
        ["bear", "bare"],
        ["beat", "beet"],
        ["berry", "bury"],
        ["berth", "birth"],
        ["bight", "bite", "byte"],
        ["bloc", "block"],
        ["bold", "bowled"],
        ["boar", "bore"],
        ["board", "bored"],
        ["boarder", "border"],
        ["born", "borne"],
        ["brews", "bruise"],
        ["bridal", "bridle"],
        ["broach", "brooch"],
        ["cache", "cash"],
        ["capital", "capitol"],
        ["carat", "caret", "carrot"],
        ["cell", "sell"],
        ["cent", "scent", "sent"],
        ["cereal", "serial"],
        ["chews", "choose"],
        ["chile", "chilly"],
        ["choir", "quire"],
        ["choral", "coral"],
        ["coarse", "course"],
        ["colonel", "kernel"],
        ["council", "counsel"],
        ["creak", "creek"],
        ["crews", "cruise"],
        ["cue", "queue", "q"],
        ["days", "daze"],
        ["dear", "deer"],
        ["descent", "dissent"],
        ["die", "dye"],
        ["discreet", "discrete"],
        ["doe", "dough"],
        ["done", "dun"],
        ["draft", "draught"],
        ["dual", "duel"],
        ["due", "dew", "do"],
        ["earn", "urn"],
        ["ewes", "use", "yews"],
        ["eye", "i", "aye"],
        ["fair", "fare"],
        ["faze", "phase"],
        ["feat", "feet"],
        ["faint", "feint"],
        ["find", "fined"],
        ["fir", "fur"],
        ["flair", "flare"],
        ["flea", "flee"],
        ["flew", "flue"],
        ["forth", "fourth"],
        ["friar", "fryer"],
        ["gait", "gate"],
        ["genes", "jeans"],
        ["gorilla", "guerrilla"],
        ["grate", "great"],
        ["groan", "grown"],
        ["guessed", "guest"],
        ["guise", "guys"],
        ["hail", "hale"],
        ["hair", "hare"],
        ["hay", "hey"],
        ["heal", "heel", "he'll"],
        ["heard", "herd"],
        ["him", "hymn"],
        ["hoard", "horde"],
        ["hoarse", "horse"],
        ["hole", "whole"],
        ["holy", "wholly"],
        ["hour", "our"],
        ["idle", "idol"],
        ["in", "inn"],
        ["key", "quay"],
        ["knead", "need"],
        ["knave", "nave"],
        ["kneel", "neil"],
        ["knot", "not"],
        ["lain", "lane"],
        ["leak", "leek"],
        ["lessen", "lesson"],
        ["liar", "lyre"],
        ["lichen", "liken"],
        ["links", "lynx"],
        ["loan", "lone"],
        ["locks", "lox"],
        ["loot", "lute"],
        ["main", "mane"],
        ["maize", "maze"],
        ["meat", "meet", "mete"],
        ["medal", "meddle"],
        ["metal", "mettle"],
        ["miner", "minor"],
        ["missed", "mist"],
        ["moose", "mousse"],
        ["morning", "mourning"],
        ["muscle", "mussel"],
        ["naval", "navel"],
        ["none", "nun"],
        ["oar", "or", "ore"],
        ["ode", "owed"],
        ["oh", "owe"],
        ["pail", "pale"],
        ["pain", "pane"],
        ["palate", "pallet"],
        ["passed", "past"],
        ["patience", "patients"],
        ["pause", "paws"],
        ["peak", "peek", "pique"],
        ["pedal", "peddle"],
        ["peer", "pier"],
        ["pi", "pie"],
        ["place", "plaice"],
        ["plum", "plumb"],
        ["pole", "poll"],
        ["pray", "prey"],
        ["principal", "principle"],
        ["profit", "prophet"],
        ["rain", "reign", "rein"],
        ["raise", "rays", "raze"],
        ["rap", "wrap"],
        ["real", "reel"],
        ["reek", "wreak"],
        ["ring", "wring"],
        ["role", "roll"],
        ["root", "route"],
        ["rose", "rows"],
        ["sail", "sale"],
        ["saw", "soar", "sore"],
        ["scene", "seen"],
        ["seam", "seem"],
        ["seas", "sees", "seize"],
        ["serf", "surf"],
        ["shear", "sheer"],
        ["shoe", "shoo"],
        ["side", "sighed"],
        ["sight", "site", "cite"],
        ["slay", "sleigh"],
        ["sole", "soul"],
        ["some", "sum"],
        ["stair", "stare"],
        ["stake", "steak"],
        ["stationary", "stationery"],
        ["steal", "steel"],
        ["straight", "strait"],
        ["suite", "sweet"],
        ["tailor", "taylor"],
        ["tale", "tail"],
        ["tare", "tear"],
        ["taught", "taut"],
        ["tea", "tee"],
        ["team", "teem"],
        ["thyme", "time"],
        ["throne", "thrown"],
        ["through", "threw"],
        ["tide", "tied"],
        ["toad", "towed"],
        ["toe", "tow"],
        ["troop", "troupe"],
        ["vain", "vane", "vein"],
        ["veil", "vale"],
        ["vice", "vise"],
        ["wade", "weighed"],
        ["wail", "whale"],
        ["waist", "waste"],
        ["way", "weigh"],
        ["waive", "wave"],
        ["warn", "worn"],
        ["wood", "would"],
        ["yoke", "yolk"],
        ["you", "ewe", "yew"],
        ["who's", "whose"],
        ["aural", "oral"],
        ["cannon", "canon"],
        ["censor", "sensor"],
        ["clause", "claws"],
        ["complement", "compliment"],
        ["cord", "chord"],
        ["core", "corps"],
        ["dam", "damn"],
        ["foul", "fowl"],
        ["frees", "freeze"],
        ["gild", "guild"],
        ["leads", "leds"],
        ["marshal", "martial"],
        ["pore", "pour", "poor"],
        ["rung", "wrung"],
        ["sew", "so", "sow"],
        ["spade", "spayed"],
        ["tax", "tacks"]
    ]

    static let groupIDsByWord: [String: [Int]] = {
        var result: [String: [Int]] = [:]

        for (groupID, group) in groups.enumerated() {
            for word in group {
                result[word, default: []].append(groupID)
            }
        }

        return result
    }()

    static func matches(_ left: String, _ right: String) -> Bool {
        guard left != right,
              let leftGroupIDs = groupIDsByWord[left],
              let rightGroupIDs = groupIDsByWord[right] else {
            return false
        }

        return leftGroupIDs.contains { rightGroupIDs.contains($0) }
    }

    static func tokens(from normalizedPhrase: String) -> [String] {
        let tokens = normalizedPhrase.split(whereSeparator: \.isWhitespace).map(String.init)
        var resolvedTokens: [String] = []
        var index = 0

        while index < tokens.count {
            if index + 1 < tokens.count,
               let contraction = contractionToken(first: tokens[index], second: tokens[index + 1]) {
                resolvedTokens.append(contraction)
                index += 2
            } else {
                resolvedTokens.append(tokens[index])
                index += 1
            }
        }

        return resolvedTokens
    }

    // MARK: - BM:🅱️ Contractions are reconstructed only for Tier 3 because existing canonical normalization intentionally keeps exact-match behavior unchanged.
    private static func contractionToken(first: String, second: String) -> String? {
        switch (first, second) {
        case ("they", "re"):
            return "they're"
        case ("you", "re"):
            return "you're"
        case ("he", "ll"):
            return "he'll"
        case ("who", "s"):
            return "who's"
        default:
            return nil
        }
    }
}
