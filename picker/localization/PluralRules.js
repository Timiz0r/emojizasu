.pragma library

/**
 * CLDR plural operands derived from a count.
 *
 * Accepts a number (integer fast path; for non-integers the operands are taken
 * from its default string form) or a string
 * (where trailing-zero significance — v/w/f/t — is preserved, since JS numbers cannot represent it).
 * See https://github.com/unicode-org/cldr/blob/main/docs/ldml/tr35-numbers.md
 *
 * Operands: n (abs value), i (integer digits), v/w (fraction digit counts with/
 * without trailing zeros), f/t (fraction digits as integer with/without trailing
 * zeros). The compact-exponent operands c/e are unsupported and treated as 0.
 */
function Operands(value) {
    let s = typeof value === "string" ? value : String(Math.abs(value))
    if (s.charAt(0) === "-") s = s.substring(1)

    const dot = s.indexOf(".")
    const intPart = dot < 0 ? s : s.substring(0, dot)
    const fracPart = dot < 0 ? "" : s.substring(dot + 1)
    const fracTrimmed = fracPart.replace(/0+$/, "")

    this.n = parseFloat(s)
    this.i = parseInt(intPart.length ? intPart : "0", 10)
    this.v = fracPart.length
    this.w = fracTrimmed.length
    this.f = fracPart.length ? parseInt(fracPart, 10) : 0
    this.t = fracTrimmed.length ? parseInt(fracTrimmed, 10) : 0
}

/**
 * Parse a CLDR plural rule string into a predicate `(Operands) -> bool`.
 * Returns null for an empty/absent rule, and an always-true predicate for a
 * rule whose condition is blank (the typical `other` rule, which carries only
 * `@integer/@decimal` samples).
 */
function parseRule(rule) {
    if (rule == null || rule.length === 0) return null

    const at = rule.indexOf("@")
    const condition = (at < 0 ? rule : rule.substring(0, at)).trim()
    if (condition.length === 0) return function () { return true }

    const len = condition.length
    let index = 0

    const result = readExpression()
    return result

    function readExpression() {
        let expr = readAndCondition()
        while (matchWord("or")) {
            index += 2
            skipSpaces()
            const lhs = expr
            const rhs = readAndCondition()
            expr = function (o) { return lhs(o) || rhs(o) }
        }
        return expr
    }

    function readAndCondition() {
        let expr = readRelation()
        while (matchWord("and")) {
            index += 3
            skipSpaces()
            const lhs = expr
            const rhs = readRelation()
            expr = function (o) { return lhs(o) && rhs(o) }
        }
        return expr
    }

    function readRelation() {
        const operand = readExpr()

        let isEquality
        if (condition.charAt(index) === "=") {
            isEquality = true
            index += 1
        } else if (condition.charAt(index) === "!" && condition.charAt(index + 1) === "=") {
            isEquality = false
            index += 2
        } else {
            throw new Error("Expected '=' or '!=' at: " + condition.substring(index))
        }
        skipSpaces()

        let inSet = readRangeList(operand)
        while (index < len && condition.charAt(index) === ",") {
            index += 1
            skipSpaces()
            const lhs = inSet
            const rhs = readRangeList(operand)
            inSet = function (o) { return lhs(o) || rhs(o) }
        }

        return isEquality ? inSet : function (o) { return !inSet(o) }
    }

    function readRangeList(operand) {
        const first = readValue()
        if (index < len && condition.charAt(index) === "." && condition.charAt(index + 1) === ".") {
            index += 2
            skipSpaces()
            const second = readValue()
            return function (o) { const x = operand(o); return x >= first && x <= second }
        }
        return function (o) { return operand(o) === first }
    }

    function readExpr() {
        const name = condition.charAt(index)
        index += 1
        skipSpaces()

        let operand
        if (name === "n") operand = function (o) { return o.n }
        else if (name === "i") operand = function (o) { return o.i }
        else if (name === "v") operand = function (o) { return o.v }
        else if (name === "w") operand = function (o) { return o.w }
        else if (name === "f") operand = function (o) { return o.f }
        else if (name === "t") operand = function (o) { return o.t }
        else if (name === "c" || name === "e") operand = function () { return 0 }
        else throw new Error("Unknown operand '" + name + "'")

        if (condition.charAt(index) === "%") {
            index += 1
            skipSpaces()
            const modulus = readValue()
            const base = operand
            operand = function (o) { return base(o) % modulus }
        }

        return operand
    }

    function readValue() {
        let count = 0
        while (index + count < len && condition.charAt(index + count) >= "0" && condition.charAt(index + count) <= "9") count += 1
        if (count === 0) throw new Error("Expected digit at: " + condition.substring(index))
        const value = parseInt(condition.substring(index, index + count), 10)
        index += count
        skipSpaces()
        return value
    }

    function matchWord(word) {
        return condition.substring(index, index + word.length) === word
    }

    function skipSpaces() {
        while (index < len && condition.charAt(index) === " ") index += 1
    }
}

/**
 * The set of plural rules for a locale. `rules` is an object of raw CLDR rule
 * strings keyed by category (`zero`/`one`/`two`/`few`/`many`/`other`); any may
 * be absent. `other` is always present and defaults to an always-true rule.
 *
 * `count` is the number of present categories — it must match a plural entry's
 * `msgstr[]` count for that entry to be used. `evaluate` returns the matched
 * category and its index among the present categories (the `msgstr[]` index).
 */
function PluralRules(rules) {
    rules = rules || {}
    const order = ["zero", "one", "two", "few", "many", "other"]

    this.raw = {}
    this._evals = []
    for (let oi = 0; oi < order.length; oi++) {
        const type = order[oi]
        const raw = rules[type]
        if (type === "other") {
            this.raw.other = raw != null ? raw : ""
            this._evals.push([type, (raw != null && raw.trim().length > 0) ? parseRule(raw) : function () { return true }])
        } else if (raw != null) {
            this.raw[type] = raw
            this._evals.push([type, parseRule(raw)])
        }
    }
    this.count = this._evals.length
}

PluralRules.prototype.evaluate = function (operands) {
    for (let i = 0; i < this._evals.length; i++) {
        if (this._evals[i][1](operands)) return { type: this._evals[i][0], index: i }
    }
    return { type: "other", index: this._evals.length - 1 }
}
