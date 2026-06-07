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

    // True only in the test negative-control (EMOJIZASU_FORCE_FOCUSABLE): the
    // search field becomes a real focused IME TextInput that reproduces the
    // focus-steal leak. Disabled in normal operation.
    property bool forceFocusable: false
    // Which UI element keys are routed to. Values: "search", "categories", "grid".
    property string internalFocus: "search"
    property bool caretOn: true
    property bool keyChannelDown: false
    property int cursorPos: 0
    property int gridSelectedIndex: -1

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

    readonly property int browseGridColumns: browseGrid.width > 0
        ? Math.max(1, Math.floor(browseGrid.width / browseGrid.cellWidth)) : 1
    readonly property int searchEmojiCols: searchFlickable.width > 0
        ? Math.max(1, Math.floor((searchFlickable.width + 2) / 44)) : 1

    function focusSearch() { searchInput.forceActiveFocus() }
    // Whether the search field holds active focus — used by tests to assert a
    // commit didn't leak into the search box. Normally always false (the picker
    // never takes keyboard focus); only the negative-control TextInput can focus.
    readonly property bool searchFocused: searchInput.activeFocus

    // fcitx keysyms (X11 keysym values) for the keys we act on.
    readonly property int keyBackspace: 0xff08
    readonly property int keyReturn:    0xff0d
    readonly property int keyKpEnter:   0xff8d
    readonly property int keyEscape:    0xff1b
    readonly property int keyLeft:      0xff51
    readonly property int keyUp:        0xff52
    readonly property int keyRight:     0xff53
    readonly property int keyDown:      0xff54
    readonly property int keyTab:       0xff09
    readonly property int keyShiftTab:  0xfe20

    // Entry point for keystrokes forwarded by the addon. Wire format is
    // "<sym> <states> <text>" (text may be empty or contain spaces).
    function handleKeyLine(line) {
        var firstSpace = line.indexOf(' ')
        if (firstSpace < 0) return
        var secondSpace = line.indexOf(' ', firstSpace + 1)
        if (secondSpace < 0) return
        var sym = parseInt(line.substring(0, firstSpace))
        var states = parseInt(line.substring(firstSpace + 1, secondSpace))
        var text = line.substring(secondSpace + 1)
        handleKey(sym, states, text)
    }

    function handleKey(sym, states, text) {
        var shiftHeld = (states & 1) !== 0
        var ctrlHeld  = (states & 4) !== 0

        if (sym === keyEscape) { closeRequested(); return }

        if (sym === keyReturn || sym === keyKpEnter) {
            if (internalFocus === "grid" && gridSelectedIndex >= 0)
                activateIndex(gridSelectedIndex)
            else
                activateFirst()
            return
        }

        if (internalFocus === "search") {
            if (sym === keyBackspace) {
                if (cursorPos > 0) {
                    cursorPos--
                    searchText = searchText.slice(0, cursorPos) + searchText.slice(cursorPos + 1)
                }
                return
            }
            if (sym === keyLeft)  { if (cursorPos > 0) cursorPos--; return }
            if (sym === keyRight) { if (cursorPos < searchText.length) cursorPos++; return }
            if (sym === keyUp || sym === keyDown) return
            if (sym === keyShiftTab || (sym === keyTab && shiftHeld)) return
            if (sym === keyTab) {
                if (isSearching) {
                    internalFocus = "grid"
                    gridSelectedIndex = 0
                } else {
                    internalFocus = "categories"
                }
                return
            }
            if (!ctrlHeld && text && text.length > 0) {
                searchText = searchText.slice(0, cursorPos) + text + searchText.slice(cursorPos)
                cursorPos += text.length
            }
            return
        }

        if (internalFocus === "categories") {
            var ci = categoryIndexOf(currentCategory)
            if (sym === keyLeft) {
                if (ci > 0) {
                    currentCategory = categoryMeta[ci - 1].id
                    catBar.positionViewAtIndex(ci - 1, ListView.Contain)
                }
                return
            }
            if (sym === keyRight) {
                if (ci < categoryMeta.length - 1) {
                    currentCategory = categoryMeta[ci + 1].id
                    catBar.positionViewAtIndex(ci + 1, ListView.Contain)
                }
                return
            }
            if (sym === keyUp || sym === keyDown) return
            if (sym === keyShiftTab || (sym === keyTab && shiftHeld)) { internalFocus = "search"; return }
            if (sym === keyTab) { internalFocus = "grid"; gridSelectedIndex = 0; return }
            return
        }

        if (internalFocus === "grid") {
            if (sym === keyShiftTab || (sym === keyTab && shiftHeld)) {
                internalFocus = isSearching ? "search" : "categories"
                gridSelectedIndex = -1
                return
            }
            if (sym === keyTab) return
            if (sym === keyLeft || sym === keyUp || sym === keyRight || sym === keyDown)
                navigateGrid(sym)
            return
        }
    }

    function categoryIndexOf(id) {
        for (var i = 0; i < categoryMeta.length; i++) {
            if (categoryMeta[i].id === id) return i
        }
        return 0
    }

    function navigateGrid(sym) {
        if (gridSelectedIndex < 0) { gridSelectedIndex = 0; return }
        var total, cols, idx, ki, emojiCount, kaomojiCount

        if (contentIndex === 0) {
            total = browseItems.length
            cols = browseGridColumns
            idx = gridSelectedIndex
            if (sym === keyLeft) {
                if (idx % cols > 0) idx--
            } else if (sym === keyRight) {
                if (idx % cols < cols - 1 && idx + 1 < total) idx++
            } else if (sym === keyUp) {
                if (idx - cols >= 0) idx -= cols
            } else if (sym === keyDown) {
                if (idx + cols < total) idx += cols
            }
            gridSelectedIndex = idx
            browseGrid.positionViewAtIndex(gridSelectedIndex, GridView.Contain)

        } else if (contentIndex === 1) {
            total = kaomojiItems.length
            idx = gridSelectedIndex
            if (sym === keyUp)   { if (idx > 0) idx-- }
            else if (sym === keyDown) { if (idx < total - 1) idx++ }
            gridSelectedIndex = idx
            kaomojiList.positionViewAtIndex(gridSelectedIndex, ListView.Contain)

        } else if (contentIndex === 2) {
            emojiCount = searchEmojiItems.length
            kaomojiCount = searchKaomojiItems.length
            total = emojiCount + kaomojiCount
            cols = searchEmojiCols
            idx = gridSelectedIndex
            if (idx < emojiCount) {
                if (sym === keyLeft) {
                    if (idx % cols > 0) idx--
                } else if (sym === keyRight) {
                    if (idx % cols < cols - 1 && idx + 1 < emojiCount) idx++
                } else if (sym === keyUp) {
                    if (idx - cols >= 0) idx -= cols
                } else if (sym === keyDown) {
                    if (idx + cols < emojiCount) idx += cols
                    else if (kaomojiCount > 0) idx = emojiCount
                }
            } else {
                ki = idx - emojiCount
                if (sym === keyUp) {
                    if (ki > 0) idx--
                    else if (emojiCount > 0) idx = emojiCount - 1
                } else if (sym === keyDown) {
                    if (idx + 1 < total) idx++
                }
            }
            gridSelectedIndex = idx
        }
    }

    function activateIndex(idx) {
        if (contentIndex === 0) {
            if (idx >= 0 && idx < browseItems.length) emojiSelected(browseItems[idx].emoji)
        } else if (contentIndex === 1) {
            if (idx >= 0 && idx < kaomojiItems.length) emojiSelected(kaomojiItems[idx].text)
        } else if (contentIndex === 2) {
            var ei = searchEmojiItems.length
            if (idx < ei) {
                emojiSelected(searchEmojiItems[idx].emoji)
            } else {
                var ki = idx - ei
                if (ki < searchKaomojiItems.length) emojiSelected(searchKaomojiItems[ki].text)
            }
        }
    }

    // Commit the first item of whatever view is showing.
    function activateFirst() {
        if (isSearching) {
            if (searchEmojiItems.length > 0) { emojiSelected(searchEmojiItems[0].emoji); return }
            if (searchKaomojiItems.length > 0) { emojiSelected(searchKaomojiItems[0].text); return }
        } else if (currentCategory === "kaomoji") {
            if (kaomojiItems.length > 0) emojiSelected(kaomojiItems[0].text)
        } else if (browseItems.length > 0) {
            emojiSelected(browseItems[0].emoji)
        }
    }

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
        // Only the negative-control path takes real keyboard focus. Normally the
        // picker must NOT focus a TextInput (that would enable zwp_text_input_v3
        // and overwrite the addon's tracked target IC).
        if (forceFocusable)
            Qt.callLater(function() { searchInput.forceActiveFocus() })
    }

    Timer {
        interval: 530; repeat: true
        running: root.internalFocus === "search" && !root.forceFocusable
        onTriggered: root.caretOn = !root.caretOn
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

    onInternalFocusChanged: {
        if (internalFocus === "search") caretOn = true
    }

    onIsSearchingChanged: {
        if (isSearching && internalFocus === "categories") internalFocus = "search"
        if (!isSearching) gridSelectedIndex = -1
    }

    onCurrentCategoryChanged: {
        if (currentCategory === "kaomoji") refreshKaomoji()
        else refreshBrowse()
        if (internalFocus === "grid") gridSelectedIndex = 0
    }

    onSearchTextChanged: {
        if (cursorPos > searchText.length) cursorPos = searchText.length
        if (searchText.length > 0) searchTimer.restart()
        if (internalFocus === "grid") gridSelectedIndex = 0
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
                border.color: (root.forceFocusable ? searchInput.activeFocus
                                                    : root.internalFocus === "search")
                              ? palette.highlight : Qt.darker(palette.base, 1.2)
                border.width: 1

                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 8 }
                    spacing: 6

                    Text {
                        text: "🔍"; font.pixelSize: 16; renderType: Text.NativeRendering
                    }

                    Item {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true

                        // Negative-control / test path only: a real editable IME
                        // text field that takes keyboard focus and reproduces the
                        // focus-steal leak. Disabled in normal operation.
                        TextInput {
                            id: searchInput
                            anchors.fill: parent
                            visible: root.forceFocusable
                            enabled: root.forceFocusable
                            font.pixelSize: 14; color: palette.text
                            verticalAlignment: TextInput.AlignVCenter; clip: true
                            onTextChanged: if (root.forceFocusable) root.searchText = text
                        }

                        // Normal path: display-only. searchText is mutated by
                        // handleKey from socket-forwarded keys; no IME, no focus.
                        Row {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            spacing: 0
                            visible: !root.forceFocusable
                            Text {
                                text: root.searchText.substring(0, root.cursorPos)
                                font.pixelSize: 14; color: palette.text
                                renderType: Text.NativeRendering
                                verticalAlignment: Text.AlignVCenter
                            }
                            Rectangle {
                                width: 1; height: 18; color: palette.text
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.internalFocus === "search" && root.caretOn
                            }
                            Text {
                                text: root.searchText.substring(root.cursorPos)
                                font.pixelSize: 14; color: palette.text
                                renderType: Text.NativeRendering
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Text {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            text: root.language === "ja" ? "絵文字を検索..." : "Search emoji..."
                            color: Qt.alpha(palette.text, 0.38); font.pixelSize: 14
                            visible: root.searchText.length === 0
                        }
                    }

                    Text {
                        text: "✕"; font.pixelSize: 12
                        color: Qt.alpha(palette.text, 0.5)
                        visible: root.searchText.length > 0
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.searchText = ""
                                root.cursorPos = 0
                                if (root.forceFocusable) { searchInput.text = ""; searchInput.forceActiveFocus() }
                            }
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
        Rectangle {
            Layout.fillWidth: true
            height: 44
            color: "transparent"
            radius: 6
            border.color: root.internalFocus === "categories" ? Qt.alpha(palette.highlight, 0.6) : "transparent"
            border.width: 1
            visible: !root.isSearching

            ListView {
                id: catBar
                anchors.fill: parent; orientation: ListView.Horizontal; spacing: 1; clip: true
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
                                root.searchText = ""
                                root.cursorPos = 0
                                if (root.forceFocusable) searchInput.text = ""
                            }
                            ToolTip.visible: containsMouse; ToolTip.delay: 600
                            ToolTip.text: root.language === "ja" ? modelData.name_ja : modelData.name_en
                        }
                    }
                }
            }
        }

        // Separator
        Rectangle {
            Layout.fillWidth: true; height: 1; color: Qt.alpha(palette.windowText, 0.1)
            visible: !root.isSearching
        }

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
                        required property int index
                        emojiChar: modelData.emoji
                        label: root.language === "ja" ? (modelData.name_ja || modelData.name_en) : modelData.name_en
                        selected: root.internalFocus === "grid" && index === root.gridSelectedIndex
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
                        selected: root.internalFocus === "grid" && index === root.gridSelectedIndex
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
                                    required property int index
                                    emojiChar: modelData.emoji
                                    label: root.language === "ja" ? (modelData.name_ja || modelData.name_en) : modelData.name_en
                                    selected: root.internalFocus === "grid" && index === root.gridSelectedIndex
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
                                    selected: root.internalFocus === "grid" && (root.searchEmojiItems.length + index) === root.gridSelectedIndex
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

    Rectangle {
        anchors.fill: parent; radius: 8; color: palette.window
        visible: root.keyChannelDown

        Column {
            anchors.centerIn: parent; spacing: 12; width: 300
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "⚠️"; font.pixelSize: 48; renderType: Text.NativeRendering
            }
            Text {
                width: parent.width
                text: root.language === "ja" ? "キー入力サービスに接続できません"
                                             : "Can't reach the key-input service"
                color: palette.windowText; font.pixelSize: 15; font.bold: true
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            }
            Text {
                width: parent.width
                text: root.language === "ja"
                      ? "fcitx5 と emojizasu アドオンが動作しているか確認してください"
                      : "Check that fcitx5 and the emojizasu addon are running, then reopen."
                color: Qt.alpha(palette.windowText, 0.55); font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            }
        }
    }
}
