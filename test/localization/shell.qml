import QtQuick
import Quickshell
import "Gettext.js" as Gettext

QtObject {
    property int passed: 0
    property int failed: 0

    function check(name, actual, expected) {
        if (actual === expected) {
            passed += 1
            console.log("PASS " + name)
        } else {
            failed += 1
            console.log("FAIL " + name + " — expected [" + expected + "] got [" + actual + "]")
        }
    }

    function catalogFrom(nativeLocale, poText) {
        const c = new Gettext.Catalog(nativeLocale)
        if (poText) c.addPo(poText)
        return c
    }

    readonly property string jaHeader:
        'msgid ""\n' +
        'msgstr ""\n' +
        '"Language: ja\\n"\n' +
        '"X-PluralRules-Zero: n = 0\\n"\n\n'

    Component.onCompleted: {
        const t = Gettext.t
        const en = Gettext.englishLocale
        const enz = Gettext.englishLocaleWithZero

        const simple = jaHeader +
            'msgid "foo"\nmsgstr "bar"\n\n' +
            'msgid "foo {0}"\nmsgstr "bar {0}"\n'

        let c = catalogFrom(en(), simple)

        c.selectLocale("en")
        check("T_ReturnsId_WhenNativeLocaleSelected", c.T(t`foo`), "foo")
        check("T_ReturnsIdFromFormattedString_WhenNativeLocaleSelected", c.T(t`foo ${1}`), "foo 1")

        c.selectLocale("ja")
        check("T_ReturnsTranslatedValue_WhenOtherLocaleSelected", c.T(t`foo`), "bar")
        check("T_ReturnsTranslatedValueFromFormattedString_WhenOtherLocaleSelected", c.T(t`foo ${1}`), "bar 1")

        c.selectLocaleOrNative(["ja"])
        check("SelectLocaleOrNative_SelectsSupportedLocale", c.T(t`foo`), "bar")
        c.selectLocaleOrNative(["ko"])
        check("SelectLocaleOrNative_SelectsNativeLocale_WhenPassedUnsupportedLocale", c.T(t`foo`), "foo")

        const fullPlural = jaHeader +
            'msgid "{0} foo"\nmsgid_plural "{0} foos"\n' +
            'msgstr[0] "fooがありません"\nmsgstr[1] "{0} foo"\n'

        function pl(cat, count) {
            return cat.T(t`${count} foo`, count, { other: t`${count} foos`, zero: t`no foos` })
        }

        let pc = catalogFrom(enz(), fullPlural)

        pc.selectLocale("en")
        check("T_ReturnsNativePluralZero_WhenZeroPassed", pl(pc, 0), "no foos")
        check("T_ReturnsNativePluralOne_WhenOnePassed", pl(pc, 1), "1 foo")
        check("T_ReturnsNativePluralOther_WhenTwoPassed", pl(pc, 2), "2 foos")

        pc.selectLocale("ja")
        check("T_ReturnsOtherLocalePluralZero_WhenZeroPassed", pl(pc, 0), "fooがありません")
        check("T_ReturnsOtherLocalePluralOther_WhenOnePassed", pl(pc, 1), "1 foo")
        check("T_ReturnsOtherLocalePluralOther_WhenTwoPassed", pl(pc, 2), "2 foo")

        const shortPlural = jaHeader +
            'msgid "{0} foo"\nmsgid_plural "{0} foos"\nmsgstr[0] "{0} foo"\n'

        let sc = catalogFrom(enz(), shortPlural)
        sc.selectLocale("ja")
        check("T_ReturnsNativeLocaleValue_WhenNotEnoughPluralValues_two", pl(sc, 2), "2 foos")
        check("T_ReturnsNativeLocaleValue_WhenNotEnoughPluralValues_zero", pl(sc, 0), "no foos")

        let nc = catalogFrom(en(), shortPlural)
        nc.selectLocale("ja")
        check("T_ReturnsNativeOtherValue_WhenNotEnoughPluralValuesAndNativeLanguageDoesntSupportPluralForm",
            nc.T(t`${0} foo`, 0, t`${0} foos`), "0 foos")

        const mixed = jaHeader +
            'msgid "{0} foo"\nmsgid_plural "{0} foos"\nmsgstr[0] "{0} foo"\n\n' +
            'msgid "{0} foo"\nmsgstr "{0} foo"\n'

        let mc = catalogFrom(en(), mixed)
        mc.selectLocale("ja")
        check("T_ProvidesDifferentValues_WhenPluralAndNonPluralUseSameId_plural",
            mc.T(t`${0} foo`, 0, t`${0} foos`), "0 foos")
        check("T_ProvidesDifferentValues_WhenPluralAndNonPluralUseSameId_singular",
            mc.T(t`${0} foo`), "0 foo")

        check("TagShortcut_singular", mc.T`hello ${"world"}`, "hello world")
        check("ThirdArgFormattable_isOther", mc.T(t`one`, 5, t`many`), "many")

        const ctxPo = jaHeader +
            'msgctxt "verb"\nmsgid "Open"\nmsgstr "ひらく"\n\n' +
            'msgctxt "adj"\nmsgid "Open"\nmsgstr "あいている"\n'
        let cc = catalogFrom(en(), ctxPo)
        cc.selectLocale("ja")
        check("Context_disambiguates_verb", cc.T(t`Open`, { context: "verb" }), "ひらく")
        check("Context_disambiguates_adj", cc.T(t`Open`, { context: "adj" }), "あいている")

        const ruPo =
            'msgid ""\nmsgstr ""\n' +
            '"Language: ru\\n"\n' +
            '"X-PluralRules-One: v = 0 and i % 10 = 1 and i % 100 != 11\\n"\n' +
            '"X-PluralRules-Few: v = 0 and i % 10 = 2..4 and i % 100 != 12..14\\n"\n' +
            '"X-PluralRules-Many: v = 0 and i % 10 = 0 or v = 0 and i % 10 = 5..9 or v = 0 and i % 100 = 11..14\\n"\n\n' +
            'msgid "{0} file"\nmsgid_plural "{0} files"\n' +
            'msgstr[0] "{0} ONE"\nmsgstr[1] "{0} FEW"\nmsgstr[2] "{0} MANY"\nmsgstr[3] "{0} OTHER"\n'
        let rc = catalogFrom(en(), ruPo)
        rc.selectLocale("ru")
        function ru(n) { return rc.T(t`${n} file`, n, t`${n} files`) }
        check("Cldr_ru_1_one", ru(1), "1 ONE")
        check("Cldr_ru_21_one", ru(21), "21 ONE")
        check("Cldr_ru_11_many", ru(11), "11 MANY")
        check("Cldr_ru_2_few", ru(2), "2 FEW")
        check("Cldr_ru_23_few", ru(23), "23 FEW")
        check("Cldr_ru_5_many", ru(5), "5 MANY")
        check("Cldr_ru_25_many", ru(25), "25 MANY")
        check("Cldr_ru_100_many", ru(100), "100 MANY")

        pc.selectLocale("en")
        check("Operands_intOne_usesOneForm",
            pc.T(t`${1} foo`, 1, t`${1} foos`), "1 foo")
        check("Operands_stringFraction_breaksEnglishOne",
            pc.T(t`${"1.0"} foo`, "1.0", t`${"1.0"} foos`), "1.0 foos")

        const escPo = jaHeader +
            'msgid "tab"\nmsgstr "a\\tb"\n\n' +
            'msgid "multi"\nmsgstr ""\n"line one "\n"line two"\n'
        let ec = catalogFrom(en(), escPo)
        ec.selectLocale("ja")
        check("Parser_unescapesTab", ec.T(t`tab`), "a\tb")
        check("Parser_concatenatesMultilineStrings", ec.T(t`multi`), "line one line two")

        console.log("SUMMARY " + passed + " " + failed)
        Qt.quit()
    }
}
