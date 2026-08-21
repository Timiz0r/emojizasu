pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "localization/Gettext.js" as Gettext

Singleton {
    id: root

    readonly property bool dataReady: _items.length > 0
    readonly property var categories: _manifest ? _manifest.categories : []
    readonly property var kaomojis: _manifest ? _manifest.kaomojis : ({})
    readonly property var items: _items
    readonly property var categoryItems: _categoryItems
    readonly property var recentItems: _recentItems
    readonly property bool recentDataReady: dataReady && _recentLoaded

    property int changeTracking: 0

    property var _manifest: null
    property var _emojiCatalog: new Gettext.Catalog(Gettext.blankLocale())
    property var _enCatalog: new Gettext.Catalog(Gettext.blankLocale())
    property var _registeredPoFiles: ({})

    property var _items: []
    property var _categoryItems: ({})
    
    property var _recentList: []
    property var _recentItems: []
    property bool _recentLoaded: false

    property var _kwCache: ({})
    property var _enKwCache: ({})

    function nameFor(text) {
        void changeTracking
        return _emojiCatalog.get(text + ".name")
    }

    function kwFor(text) {
        void changeTracking
        return _kwCache[text] ?? []
    }

    function enNameFor(text) {
        return _enCatalog.get(text + ".name")
    }

    function enKwFor(text) {
        return _enKwCache[text] ?? []
    }

    function catName(id) {
        void changeTracking
        return _emojiCatalog.get("category." + id)
    }

    function catEmoji(id) {
        void changeTracking
        return _emojiCatalog.get("category." + id + ".emoji")
    }

    function _splitKw(s) {
        if (!s) return []
        const parts = s.split(" | ")
        const result = []
        for (const part of parts) {
            const p = part.trim()
            if (p.length > 0) result.push(p)
        }
        return result
    }

    function _tryBuild() {
        if (Object.keys(_registeredPoFiles).length < _manifest.poFiles.length) return
        _build()
    }

    function _build() {
        const emojiCatalog = new Gettext.Catalog(Gettext.blankLocale())
        const enCatalog = new Gettext.Catalog(Gettext.blankLocale())
        
        for (const entry of Object.values(_registeredPoFiles)) {
            if (!entry) continue
            emojiCatalog.addPo(entry.text)
            if (entry.isEn) enCatalog.addPo(entry.text)
        }
        emojiCatalog.selectLocale(Localization.localeCode)
        enCatalog.selectLocale("en")
        _emojiCatalog = emojiCatalog
        _enCatalog = enCatalog

        _items = _manifest.items
        _categoryItems = _manifest.categoryItems
        _kwCache = _buildKwCache(_emojiCatalog)
        _enKwCache = _buildKwCache(_enCatalog)

        _buildRecentItems()

        changeTracking++
    }

    function _buildKwCache(catalog) {
        const items = _manifest.items
        const kw = {}
        for (const t of items) {
            kw[t] = _splitKw(catalog.get(t + ".keywords"))
        }
        return kw
    }

    function _buildRecentItems() {
        const result = []
        const seen = {}
        const map = _manifest ? _manifest.itemMap : {}
        for (const t of _recentList) {
            if (!seen[t] && map[t]) {
                result.push(t)
                seen[t] = true
            }
        }
        _recentItems = result
    }

    Connections {
        target: Localization
        function onLocaleCodeChanged() {
            root._emojiCatalog.selectLocale(Localization.localeCode)
            if (root.dataReady) {
                root._kwCache = root._buildKwCache(root._emojiCatalog)
                root._buildRecentItems()
            }
            root.changeTracking++
        }
    }

    FileView {
        path: Qt.resolvedUrl("data/manifest.json")
        onLoaded: { root._manifest = JSON.parse(text()) }
        onLoadFailed: error => console.error("EmojiData: manifest.json failed: " + error)
    }

    Instantiator {
        model: root._manifest ? root._manifest.poFiles : []
        delegate: FileView {
            required property string modelData
            path: Qt.resolvedUrl("data/locale/" + modelData + ".po")
            onLoaded: {
                root._registeredPoFiles[modelData] = { text: text(), isEn: modelData.startsWith("en/") }
                root.dataReady ? root._build() : root._tryBuild()
            }
            onFileChanged: reload()
            onLoadFailed: error => {
                console.warn("EmojiData: failed to load " + modelData + ".po: " + error)
                root._registeredPoFiles[modelData] = null
                root.dataReady ? root._build() : root._tryBuild()
            }
        }
    }

    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
              + "/emojizasu/recent.json"
        watchChanges: true
        printErrors: false
        onLoaded: {
            try { root._recentList = JSON.parse(text()) }
            catch(e) { root._recentList = [] }
            root._buildRecentItems()
            root._recentLoaded = true
        }
        onFileChanged: reload()
        onLoadFailed: {
            root._recentList = []
            root._recentItems = []
            root._recentLoaded = true
        }
    }
}
