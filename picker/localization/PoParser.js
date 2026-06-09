.pragma library

/**
 * Parse a gettext PO document into `{ language, pluralRules, entries }`.
 *
 * `entries` excludes the header (the empty-msgid entry); each is
 * `{ context, id, pluralId, value, pluralValues }` where `value` is the
 * `msgstr` of a singular entry and `pluralValues` is the ordered `msgstr[]`
 * list of a plural entry. `pluralRules` is an object of raw CLDR rule strings
 * keyed by category, read from the header's `X-PluralRules-*` fields.
 *
 * Comment and obsolete (`#~`) lines are ignored; this is a read path for
 * translation, not a round-tripping editor.
 */
function parse(text) {
    const lines = text.split(/\r?\n/)

    const rawEntries = []
    let current = null
    let currentKeyword = null

    for (let li = 0; li < lines.length; li++) {
        const rawLine = lines[li]
        const trimmed = rawLine.trim()

        if (trimmed.length === 0) {
            flush()
            continue
        }
        if (trimmed.charAt(0) === "#") continue

        const parsed = parseLine(rawLine)
        if (parsed === null) continue

        if (current === null) current = { msgctxt: null, msgid: null, msgid_plural: null, msgstr: null, plurals: {} }

        if (parsed.keyword !== null) {
            if (parsed.index !== null) {
                currentKeyword = "msgstr[" + parsed.index + "]"
                current.plurals[parsed.index] = parsed.string === null ? "" : parsed.string
            } else {
                currentKeyword = parsed.keyword
                current[parsed.keyword] = parsed.string === null ? "" : parsed.string
            }
        } else if (parsed.string !== null && currentKeyword !== null) {
            if (currentKeyword.charAt(0) === "m" && currentKeyword.charAt(6) === "[") {
                const idx = parseInt(currentKeyword.substring(7, currentKeyword.length - 1), 10)
                current.plurals[idx] += parsed.string
            } else {
                current[currentKeyword] += parsed.string
            }
        }
    }
    flush()

    let language = null
    let pluralRules = {}
    const entries = []
    for (let ei = 0; ei < rawEntries.length; ei++) {
        const entry = rawEntries[ei]
        if (entry.id === "" && entry.context === null) {
            const header = parseHeader(entry.value || "")
            language = header.language
            pluralRules = header.pluralRules
        } else {
            entries.push(entry)
        }
    }

    return { language: language, pluralRules: pluralRules, entries: entries }

    function flush() {
        if (current !== null && current.msgid !== null) rawEntries.push(finalize(current))
        current = null
        currentKeyword = null
    }
}

function finalize(raw) {
    const pluralKeys = Object.keys(raw.plurals).map(function (k) { return parseInt(k, 10) }).sort(function (a, b) { return a - b })
    const pluralValues = []
    for (let i = 0; i < pluralKeys.length; i++) pluralValues.push(raw.plurals[pluralKeys[i]])

    return {
        context: raw.msgctxt,
        id: raw.msgid,
        pluralId: raw.msgid_plural,
        value: raw.msgstr,
        pluralValues: pluralValues
    }
}

const lineRegex = /^\s*(?:([^\s\[\]"#]+)\s*(?:\[(\d+)\])?\s*)?(?:"((?:[^"\\]|\\.)*)")?\s*(?:#.*)?$/

function parseLine(line) {
    const match = lineRegex.exec(line)
    if (match === null) return null
    return {
        keyword: match[1] !== undefined ? match[1] : null,
        index: match[2] !== undefined ? parseInt(match[2], 10) : null,
        string: match[3] !== undefined ? unescapeString(match[3]) : null
    }
}

const escapeRegex = /\\(x[0-9a-fA-F]{2}|[0-7]{1,3}|.)/g

function unescapeString(raw) {
    return raw.replace(escapeRegex, function (whole, body) {
        switch (body) {
            case "a": return "\x07"
            case "b": return "\b"
            case "e": return "\x1b"
            case "f": return "\f"
            case "n": return "\n"
            case "r": return "\r"
            case "t": return "\t"
            case "v": return "\v"
            case "\\": return "\\"
            case "'": return "'"
            case "\"": return "\""
            case "?": return "?"
        }
        if (body.charAt(0) === "x") return String.fromCharCode(parseInt(body.substring(1), 16))
        if (body.charAt(0) >= "0" && body.charAt(0) <= "7") return String.fromCharCode(parseInt(body, 8))
        return body
    })
}

const languageRegex = /Language:\s*([a-zA-Z]+)(?:[_-]([a-zA-Z]+))?/
const ruleCategories = ["zero", "one", "two", "few", "many", "other"]

function parseHeader(value) {
    const languageMatch = languageRegex.exec(value)
    const language = languageMatch !== null
        ? (languageMatch[2] ? languageMatch[1] + "-" + languageMatch[2] : languageMatch[1])
        : null

    const pluralRules = {}
    for (let ci = 0; ci < ruleCategories.length; ci++) {
        const category = ruleCategories[ci]
        const name = category.charAt(0).toUpperCase() + category.substring(1)
        const ruleMatch = new RegExp("X-PluralRules-" + name + ":\\s*([^\\n]*)", "i").exec(value)
        if (ruleMatch !== null) pluralRules[category] = ruleMatch[1].trim()
    }

    return { language: language, pluralRules: pluralRules }
}
