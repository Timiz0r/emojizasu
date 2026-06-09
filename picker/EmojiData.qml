pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool dataReady: _items.length > 0
    readonly property var categories: _categories
    readonly property var items: _items
    readonly property var itemMap: _itemMap
    readonly property var categoryItems: _categoryItems
    readonly property var recentItems: _recentItems

    property var _categories: []
    property var _items: []
    property var _itemMap: ({})
    property var _categoryItems: ({})
    property var _recentList: []
    property var _recentItems: []

    function _buildRecentItems() {
        const result = []
        const seen = {}
        for (let i = 0; i < _recentList.length; i++) {
            const t = _recentList[i]
            if (!seen[t] && _itemMap[t]) {
                result.push(_itemMap[t])
                seen[t] = true
            }
        }
        _recentItems = result
    }

    FileView {
        path: Qt.resolvedUrl("data/emoji.json")
        onLoaded: {
            const d = JSON.parse(text())
            root._categories = d.categories
            root._items = d.items
            const m = {}, ci = {}
            for (let i = 0; i < d.items.length; i++) {
                const item = d.items[i]
                m[item.text] = item
                if (!ci[item.category]) ci[item.category] = []
                ci[item.category].push(item)
            }
            root._itemMap = m
            root._categoryItems = ci
            root._buildRecentItems()
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
        }
        onFileChanged: reload()
        onLoadFailed: { root._recentList = []; root._recentItems = [] }
    }
}
