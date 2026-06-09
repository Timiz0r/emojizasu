pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "localization/Gettext.js" as Gettext


// Global translation catalog. Loads the `.po` files named in `sources`, selects
// `localeCode` (falling back to the English native), and resolves translations.
Singleton {
    id: root

    readonly property var t: Gettext.t

    property var sources: []
    property string localeCode: "en"

    property int revision: 0
    readonly property var catalog: new Gettext.Catalog(Gettext.englishLocaleWithZero())

    function _() {
        void root.revision
        return root.catalog.T.apply(root.catalog, arguments)
    }

    function supportedLocales() {
        const codes = [root.catalog.nativeLocale.code]
        for (const code in root.catalog.documents) codes.push(code)
        return codes
    }

    onLocaleCodeChanged: {
        root.catalog.selectLocale(root.localeCode)
        root.revision += 1
    }

    Instantiator {
        model: root.sources
        delegate: FileView {
            required property var modelData
            path: modelData
            onLoaded: {
                root.catalog.addPo(text())
                root.catalog.selectLocale(root.localeCode)
                root.revision += 1
            }
            onLoadFailed: function (error) {
                console.warn("Localization: failed to load " + path + ": " + error)
            }
        }
    }
}
