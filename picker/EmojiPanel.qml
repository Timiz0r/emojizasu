import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import Quickshell
import Quickshell.Io

Rectangle {
    id: root

    color: palette.window
    radius: 8

    signal emojiSelected(string emoji)
    signal closeRequested()

    property string language: "ja"
    property string searchText: ""
    property string currentCategory: "recent"

    property var emojiData: null
    property var categoryMeta: []
    property var recentList: []

    // Items fed into the three content views
    property var browseItems: []       // current category emoji
    property var kaomojiItems: []      // kaomoji category full list
    property var searchEmojiItems: []  // search: emoji matches
    property var searchKaomojiItems: [] // search: kaomoji matches

    readonly property bool dataReady: emojiData !== null
    readonly property bool isSearching: searchText.length > 0

    // Content index: 0=category browse, 1=kaomoji category, 2=search results
    readonly property int contentIndex: {
        if (isSearching) return 2
        if (currentCategory === "kaomoji") return 1
        return 0
    }

    function focusSearch() { searchInput.forceActiveFocus() }
    // Whether the search field holds active focus — used by tests to assert a
    // commit didn't leak into the search box.
    readonly property bool searchFocused: searchInput.activeFocus

    FileView {
        id: emojiDataFile
        // Resolve relative to this component's location (not shellDir) so the
        // picker loads its data when instantiated from any config dir, e.g. the
        // test harness's test/picker config.
        path: Qt.resolvedUrl("data/emoji.json")
        onLoaded: {
            root.emojiData = JSON.parse(emojiDataFile.text())
            root.buildCategoryMeta()
            root.refreshBrowse()
        }
    }

    FileView {
        id: recentFile
        path: StandardPaths.writableLocation(StandardPaths.StateLocation)
              + "/emojizasu/recent.json"
        printErrors: false // expected to fail on first run TODO: fixable?
        onLoaded: {
            try { root.recentList = JSON.parse(recentFile.text()) }
            catch(e) { root.recentList = [] }
            if (root.currentCategory === "recent") root.refreshBrowse()
        }
        onFileChanged: recentFile.reload()
        onLoadFailed: root.recentList = []
    }

    Component.onCompleted: {
        Qt.callLater(function() { searchInput.forceActiveFocus() })
    }

    function buildCategoryMeta() {
        if (!emojiData) return
        var cats = [{ id: "recent", icon: "🕐", name_en: "Recently Used", name_ja: "最近使った" }]
        for (var i = 0; i < emojiData.categories.length; i++) {
            var c = emojiData.categories[i]
            cats.push({ id: c.id, icon: c.icon, name_en: c.name_en, name_ja: c.name_ja })
        }
        cats.push({ id: "kaomoji", icon: "( ＾▽＾)", name_en: "Kaomoji", name_ja: "顔文字" })
        categoryMeta = cats
    }

    function refreshBrowse() {
        if (!emojiData) return
        if (currentCategory === "recent") {
            browseItems = recentList.map(function(e) {
                return { emoji: e, name_en: e, name_ja: e }
            })
            return
        }
        for (var i = 0; i < emojiData.categories.length; i++) {
            if (emojiData.categories[i].id === currentCategory) {
                browseItems = emojiData.categories[i].emoji
                return
            }
        }
        browseItems = []
    }

    function refreshKaomoji() {
        if (!emojiData) return
        kaomojiItems = emojiData.kaomoji
    }

    function refreshSearch() {
        if (!emojiData || searchText.length === 0) return
        var q = searchText
        var qlo = q.toLowerCase()
        var em = [], km = []

        for (var ci = 0; ci < emojiData.categories.length && em.length < 200; ci++) {
            var emojis = emojiData.categories[ci].emoji
            for (var ei = 0; ei < emojis.length && em.length < 200; ei++) {
                if (matchEmoji(emojis[ei], q, qlo)) em.push(emojis[ei])
            }
        }
        for (var ki = 0; ki < emojiData.kaomoji.length; ki++) {
            if (matchKaomoji(emojiData.kaomoji[ki], q, qlo)) km.push(emojiData.kaomoji[ki])
        }
        searchEmojiItems = em
        searchKaomojiItems = km
    }

    function matchEmoji(e, q, qlo) {
        if (e.emoji === q) return true
        if (e.name_en.toLowerCase().indexOf(qlo) >= 0) return true
        if (e.name_ja.indexOf(q) >= 0) return true
        var ke = e.keywords_en, kj = e.keywords_ja
        for (var i = 0; i < ke.length; i++) if (ke[i].toLowerCase().indexOf(qlo) >= 0) return true
        for (var j = 0; j < kj.length; j++) if (kj[j].indexOf(q) >= 0) return true
        return false
    }

    function matchKaomoji(km, q, qlo) {
        if (km.text.indexOf(q) >= 0) return true
        if (km.name_en.toLowerCase().indexOf(qlo) >= 0) return true
        if (km.name_ja.indexOf(q) >= 0) return true
        var t = km.tags
        for (var i = 0; i < t.length; i++) if (t[i].toLowerCase().indexOf(qlo) >= 0) return true
        return false
    }

    Timer {
        id: searchTimer; interval: 120; repeat: false
        onTriggered: root.refreshSearch()
    }

    onCurrentCategoryChanged: {
        if (currentCategory === "kaomoji") refreshKaomoji()
        else refreshBrowse()
    }
    onSearchTextChanged: {
        if (searchText.length > 0) searchTimer.restart()
    }

    SystemPalette { id: palette; colorGroup: SystemPalette.Active }

    ColumnLayout {
        anchors { fill: parent; margins: 8 }
        spacing: 6

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Rectangle {
                Layout.fillWidth: true
                height: 34
                radius: 17
                color: palette.base
                border.color: searchInput.activeFocus ? palette.highlight : Qt.darker(palette.base, 1.2)
                border.width: 1

                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 8 }
                    spacing: 6

                    Text {
                        text: "🔍"; font.pixelSize: 16; renderType: Text.NativeRendering
                    }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true; Layout.fillHeight: true
                        font.pixelSize: 14; color: palette.text
                        verticalAlignment: TextInput.AlignVCenter; clip: true
                        onTextChanged: root.searchText = text

                        Text {
                            anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                            text: root.language === "ja" ? "絵文字を検索..." : "Search emoji..."
                            color: Qt.alpha(palette.text, 0.38); font: parent.font
                            visible: !parent.text
                        }
                    }

                    Text {
                        text: "✕"; font.pixelSize: 12
                        color: Qt.alpha(palette.text, 0.5)
                        visible: searchInput.text.length > 0
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: { searchInput.text = ""; searchInput.forceActiveFocus() }
                        }
                    }
                }
            }

            // Language toggle
            Rectangle {
                width: 46; height: 34; radius: 17
                color: langHover.containsMouse ? Qt.lighter(palette.button, 1.1) : palette.button
                border.color: Qt.darker(palette.button, 1.15); border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: root.language === "ja" ? "JA" : "EN"
                    font.pixelSize: 13; font.bold: true; color: palette.buttonText
                }
                MouseArea {
                    id: langHover; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.language = (root.language === "ja" ? "en" : "ja")
                }
            }

            // Close
            Rectangle {
                width: 34; height: 34; radius: 17
                color: xHover.containsMouse ? "#c0392b" : Qt.alpha(palette.button, 0.7)
                Text {
                    anchors.centerIn: parent; text: "✕"; font.pixelSize: 14
                    color: xHover.containsMouse ? "white" : palette.buttonText
                }
                MouseArea {
                    id: xHover; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor; onClicked: root.closeRequested()
                }
            }
        }

        // Categories
        ListView {
            id: catBar
            Layout.fillWidth: true; height: 44
            orientation: ListView.Horizontal; spacing: 1; clip: true
            model: root.categoryMeta
            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOff }

            delegate: Item {
                required property var modelData
                width: 44; height: 44

                Rectangle {
                    anchors { fill: parent; margins: 2 }
                    radius: 6
                    color: root.currentCategory === modelData.id
                           ? Qt.alpha(palette.highlight, 0.22)
                           : tabHover.containsMouse ? Qt.alpha(palette.highlight, 0.1) : "transparent"

                    Rectangle {
                        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 1 }
                        width: 20; height: 2; radius: 1; color: palette.highlight
                        visible: root.currentCategory === modelData.id
                    }

                    Text {
                        anchors.centerIn: parent
                        text: modelData.icon
                        font.pixelSize: modelData.id === "kaomoji" ? 8 : 22
                        renderType: Text.NativeRendering
                    }

                    MouseArea {
                        id: tabHover; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.currentCategory = modelData.id
                            searchInput.text = ""
                        }
                        ToolTip.visible: containsMouse; ToolTip.delay: 600
                        ToolTip.text: root.language === "ja" ? modelData.name_ja : modelData.name_en
                    }
                }
            }
        }

        // Separator
        Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(palette.windowText, 0.1) }

        // Status line
        Text {
            Layout.fillWidth: true
            font.pixelSize: 11; color: Qt.alpha(palette.windowText, 0.45)
            visible: root.dataReady
            text: {
                if (root.isSearching) {
                    var n = root.searchEmojiItems.length + root.searchKaomojiItems.length
                    return root.language === "ja" ? n + " 件の検索結果" : n + " results"
                }
                if (root.currentCategory === "recent")
                    return root.language === "ja" ? "最近使った絵文字" : "Recently used"
                if (root.currentCategory === "kaomoji")
                    return root.language === "ja" ? "顔文字  " + root.kaomojiItems.length + " 件" : root.kaomojiItems.length + " kaomoji"
                for (var i = 0; i < root.categoryMeta.length; i++) {
                    if (root.categoryMeta[i].id === root.currentCategory) {
                        var nm = root.language === "ja" ? root.categoryMeta[i].name_ja : root.categoryMeta[i].name_en
                        return nm + "  " + root.browseItems.length
                    }
                }
                return ""
            }
        }

        StackLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            currentIndex: root.contentIndex

            // Category
            Item {
                GridView {
                    id: browseGrid
                    anchors.fill: parent; clip: true
                    cellWidth: 42; cellHeight: 42
                    model: root.browseItems
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: EmojiCell {
                        required property var modelData
                        emojiChar: modelData.emoji
                        label: root.language === "ja" ? (modelData.name_ja || modelData.name_en) : modelData.name_en
                        onActivated: root.emojiSelected(emojiChar)
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: browseGrid.count === 0 && root.dataReady
                        text: root.currentCategory === "recent"
                              ? (root.language === "ja" ? "まだ使った絵文字がありません" : "No recently used emoji yet")
                              : (root.language === "ja" ? "絵文字がありません" : "No emoji here")
                        color: Qt.alpha(palette.windowText, 0.38); font.pixelSize: 13
                        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; width: 200
                    }
                }
            }

            // Kaomoji
            Item {
                ListView {
                    id: kaomojiList
                    anchors.fill: parent; clip: true; spacing: 1
                    model: root.kaomojiItems
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: KaomojiCell {
                        required property var modelData
                        required property int index
                        kaomojiText: modelData.text
                        label: root.language === "ja" ? modelData.name_ja : modelData.name_en
                        width: kaomojiList.width
                        highlight: index % 2 === 0
                        onActivated: root.emojiSelected(kaomojiText)
                    }
                }
            }

            // Search results
            Item {
                Flickable {
                    id: searchFlickable
                    anchors.fill: parent; clip: true
                    contentHeight: searchColumn.implicitHeight
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    Column {
                        id: searchColumn
                        width: searchFlickable.width
                        spacing: 0

                        // Emoji results
                        Flow {
                            id: searchEmojiFlow
                            width: parent.width
                            spacing: 2
                            visible: root.searchEmojiItems.length > 0
                            Repeater {
                                model: root.searchEmojiItems
                                delegate: EmojiCell {
                                    required property var modelData
                                    emojiChar: modelData.emoji
                                    label: root.language === "ja" ? (modelData.name_ja || modelData.name_en) : modelData.name_en
                                    onActivated: root.emojiSelected(emojiChar)
                                }
                            }
                        }

                        // Kaomoji results header
                        Item {
                            width: parent.width; height: 28
                            visible: root.searchKaomojiItems.length > 0 && root.searchEmojiItems.length > 0

                            Text {
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 4 }
                                text: root.language === "ja" ? "顔文字" : "Kaomoji"
                                font.pixelSize: 11; font.bold: true
                                color: Qt.alpha(palette.windowText, 0.4)
                            }
                        }

                        // Kaomoji results list
                        Column {
                            width: parent.width
                            spacing: 1
                            visible: root.searchKaomojiItems.length > 0
                            Repeater {
                                model: root.searchKaomojiItems
                                delegate: KaomojiCell {
                                    required property var modelData
                                    required property int index
                                    kaomojiText: modelData.text
                                    label: root.language === "ja" ? modelData.name_ja : modelData.name_en
                                    width: searchColumn.width
                                    highlight: index % 2 === 0
                                    onActivated: root.emojiSelected(kaomojiText)
                                }
                            }
                        }

                        // Empty state
                        Item {
                            width: parent.width; height: 120
                            visible: root.searchEmojiItems.length === 0 && root.searchKaomojiItems.length === 0 && root.isSearching && root.dataReady
                            Text {
                                anchors.centerIn: parent
                                text: root.language === "ja" ? "「" + root.searchText + "」は見つかりませんでした" : "No results for \"" + root.searchText + "\""
                                color: Qt.alpha(palette.windowText, 0.38); font.pixelSize: 13
                                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; width: 260
                            }
                        }
                    }
                }
            }
        }
    }

    // Loading overlay
    Rectangle {
        anchors.fill: parent; radius: 8; color: palette.window
        visible: !root.dataReady

        Column {
            anchors.centerIn: parent; spacing: 12
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "🌸"; font.pixelSize: 48; renderType: Text.NativeRendering
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.language === "ja" ? "読み込み中..." : "Loading..."
                color: Qt.alpha(palette.windowText, 0.5); font.pixelSize: 14
            }
        }
    }
}
