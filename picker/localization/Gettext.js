.pragma library
.import "PluralRules.js" as PluralRules
.import "PoParser.js" as PoParser

class FormattableString {
    constructor(format, args) {
        this.format = format
        this.args = args
    }
}
function t(strings, ...values) {
    let format = strings[0]
    for (let i = 0; i < values.length; i++) format += "{" + i + "}" + strings[i + 1]
    return new FormattableString(format, values)
}

/** ubstitute positional `{n}` placeholders in `format` with `args`. */
function format(formatString, args) {
    return formatString.replace(/\{(\d+)\}/g, function (whole, digits) {
        const i = parseInt(digits, 10)
        return i < args.length ? String(args[i]) : whole
    })
}

/** Build a locale `{ code, pluralRules }` from a code and raw CLDR rule strings. */
function locale(code, rawRules) {
    return { code: code, pluralRules: new PluralRules.PluralRules(rawRules) }
}

/** English native locale: CLDR `one` (i = 1 and v = 0) + catch-all `other`. */
function englishLocale() {
    return locale("en", { one: "i = 1 and v = 0" })
}

/** English native locale with a special `zero` (n = 0) form enabled. */
function englishLocaleWithZero() {
    return locale("en", { zero: "n = 0", one: "i = 1 and v = 0" })
}

function entryKey(context, id, pluralId) {
    return (context === null || context === undefined ? "" : context) + "\0" + id + "\0" + (pluralId === null || pluralId === undefined ? "" : pluralId)
}

/**
 * Holds the native locale plus per-locale parsed PO documents, and resolves
 * translations through `T`. `T` is polymorphic:
 *
 *   T`Hello`                                  singular (tag form)
 *   T(t`Hello`)                               singular
 *   T(t`one bar`, count, t`${count} bars`)    plural; 3rd FormattableString ⇒ other
 *   T(t`one bar`, count, { other, zero, … })  plural; forms bag
 *   T(t`Open`, { context: "verb" })           singular with context
 *
 * Lookup uses `id.format` as the msgid (and the `one` form) and `other.format`
 * as the pluralId. A plural entry is used only when its `msgstr[]` count matches
 * the selected locale's plural-rule count; otherwise the call-site forms are
 * used, picked by the evaluated plural category.
 */
class Catalog {
    constructor(nativeLocale) {
        this.nativeLocale = nativeLocale
        this.documents = {}
        this.selected = null
    }

    addPo(text) {
        const parsed = PoParser.parse(text)
        const loc = locale(parsed.language, parsed.pluralRules)
        const index = {}
        for (let i = 0; i < parsed.entries.length; i++) {
            const e = parsed.entries[i]
            index[entryKey(e.context, e.id, e.pluralId)] = e
        }
        this.documents[parsed.language] = { locale: loc, entries: parsed.entries, index: index }
        return loc
    }

    supports(code) {
        return code === this.nativeLocale.code || this.documents.hasOwnProperty(code)
    }

    selectLocale(code) {
        if (!code || code === this.nativeLocale.code) {
            this.selected = null
            return true
        }
        if (this.documents.hasOwnProperty(code)) {
            this.selected = this.documents[code]
            return true
        }
        return false
    }

    selectLocaleOrNative(codes) {
        const list = codes || []
        for (let i = 0; i < list.length; i++) {
            if (this.supports(list[i])) {
                this.selectLocale(list[i])
                return list[i]
            }
        }
        this.selectLocale(this.nativeLocale.code)
        return this.nativeLocale.code
    }

    get selectedLocale() {
        return this.selected !== null ? this.selected.locale : this.nativeLocale
    }

    T(first) {
        if (Array.isArray(first) && first.raw) {
            const args = []
            for (let i = 1; i < arguments.length; i++) args.push(arguments[i])
            return this._singular(t(first, ...args), null)
        }

        const id = first
        if (arguments.length === 1) return this._singular(id, null)

        const second = arguments[1]
        if (typeof second === "number" || typeof second === "string") {
            const third = arguments[2]
            const forms = third instanceof FormattableString ? { other: third } : (third || {})
            return this._plural(id, second, forms)
        }

        const options = second || {}
        return this._singular(id, options.context || null)
    }

    _singular(id, context) {
        if (this.selected !== null) {
            const entry = this.selected.index[entryKey(context, id.format, null)]
            if (entry !== undefined && entry.value) return format(entry.value, id.args)
        }
        return format(id.format, id.args)
    }

    _plural(id, count, forms) {
        const context = forms.context || null
        const other = forms.other
        const loc = this.selectedLocale
        const operands = new PluralRules.Operands(count)
        const evaluated = loc.pluralRules.evaluate(operands)

        if (this.selected !== null && other) {
            const entry = this.selected.index[entryKey(context, id.format, other.format)]
            if (entry !== undefined && entry.pluralValues.length === loc.pluralRules.count) {
                return format(entry.pluralValues[evaluated.index], other.args)
            }
        }

        let chosen
        if (evaluated.type === "one") chosen = id
        else if (evaluated.type === "zero") chosen = forms.zero
        else if (evaluated.type === "two") chosen = forms.two
        else if (evaluated.type === "few") chosen = forms.few
        else if (evaluated.type === "many") chosen = forms.many
        else chosen = other

        if (!chosen) chosen = other
        return format(chosen.format, chosen.args)
    }
}
