import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "KeyNav.js" as KeyNav

Rectangle {
    id: root

    color: palette.window
    radius: 8

    signal emojiSelected(string emoji)
    signal closeRequested()
    signal moveWindowRequested(real dx, real dy)
    signal resizeRequested(real w, real h)

    readonly property var t: Localization.t
    function _() { return Localization._.apply(null, arguments) }

    readonly property string language: Localization.localeCode
    property alias searchText: searchInput.text
    property string currentCategory: "recent"

    property real dragMaxX: 0
    property real dragMaxY: 0

    property string internalFocus: "grid"
    property bool wantsKeyboard: false
    property bool keyChannelDown: false
    property int gridSelectedIndex: 0

    readonly property bool dataReady: EmojiData.dataReady

    readonly property var categoryMeta: {
        if (!EmojiData.dataReady) return []
        const cats = [{ id: "recent", icon: "🕐", name_en: "Recently Used", name_ja: "最近使った" }]
        for (let i = 0; i < EmojiData.categories.length; i++) cats.push(EmojiData.categories[i])
        return cats
    }

    property var browseItems: currentCategory !== "recent"
        ? (EmojiData.categoryItems[currentCategory] || [])
        : []

    property var searchEmojiItems: []
    property var searchKaomojiItems: []

    property var recentEmojiItems: []
    property var recentKaomojiItems: []

    function refreshRecentSnapshot() {
        recentEmojiItems = EmojiData.recentItems.filter(function(i) { return i.category !== "kaomoji" })
        recentKaomojiItems = EmojiData.recentItems.filter(function(i) { return i.category === "kaomoji" })
    }

    // True only in the test negative-control (EMOJIZASU_FORCE_FOCUSABLE): the
    // search field takes real keyboard focus and reproduces the focus-steal leak.
    // Disabled in normal operation.
    property bool forceFocusable: false

    readonly property bool isSearching: searchText.length > 0
    readonly property int contentIndex: isSearching ? 1 : 0

    readonly property int browseGridColumns: browseGrid.width > 0
        ? Math.max(1, Math.floor(browseGrid.width / browseGrid.cellWidth)) : 1
    readonly property int searchEmojiCols: searchFlickable.width > 0
        ? Math.max(1, Math.floor((searchFlickable.width + 2) / 44)) : 1
    readonly property int recentEmojiCols: browseGrid.width > 0
        ? Math.max(1, Math.floor((browseGrid.width + 2) / 44)) : 1

    readonly property int gridCount: {
        if (isSearching) return searchEmojiItems.length + searchKaomojiItems.length
        if (currentCategory === "recent") return recentEmojiItems.length + recentKaomojiItems.length
        return browseItems.length
    }

    function dlog(where, scope) {
        DebugLog.event(scope || "panel", where
            + "  internalFocus=" + internalFocus
            + " wantsKeyboard=" + wantsKeyboard
            + " searchFocus=" + searchInput.activeFocus
            + " gridSel=" + gridSelectedIndex
            + " searching=" + isSearching)
    }

    function focusSearch() { engageSearch() }

    function engageSearch() {
        internalFocus = "search"
        wantsKeyboard = true
        dlog("engageSearch")
    }

    function releaseKeyboard() { wantsKeyboard = false; dlog("releaseKeyboard") }

    function focusGrid() {
        if (gridCount <= 0) return
        internalFocus = "grid"
        if (gridSelectedIndex < 0) gridSelectedIndex = 0
        wantsKeyboard = false
        dlog("focusGrid")
    }

    function advanceFromSearch() {
        if (isSearching) focusGrid()
        else { internalFocus = "categories"; wantsKeyboard = false }
    }

    function leaveGridBackward() {
        if (isSearching) engageSearch()
        else internalFocus = "categories"
        gridSelectedIndex = -1
    }

    function resetFocusState() {
        wantsKeyboard = false
        internalFocus = "grid"
        searchText = ""
        gridSelectedIndex = 0
        currentCategory = "recent"
    }

    onWantsKeyboardChanged: {
        if (wantsKeyboard) Qt.callLater(() => {
            searchInput.forceActiveFocus()
            dlog("forceActiveFocus(callLater)")
        })
        else searchInput.focus = false
    }

    Connections {
        target: searchInput
        function onActiveFocusChanged() {
            root.dlog("searchInput.activeFocusChanged=" + searchInput.activeFocus)
            if (!searchInput.activeFocus && root.internalFocus === "search" && !root.forceFocusable)
                root.releaseKeyboard()
        }
    }

    readonly property bool searchFocused: searchInput.activeFocus

    function handleKeyLine(line) {
        const intent = KeyNav.route(line, internalFocus)
        dlog("handleKeyLine '" + line + "' -> " + intent.kind)
        switch (intent.kind) {
        case "close":
            closeRequested(); return
        case "activate":
            if (internalFocus === "grid" && gridSelectedIndex >= 0) selectEmojiAt(gridSelectedIndex)
            else selectFirstEmoji()
            return
        case "moveWindow":
            root.moveWindowRequested(intent.dx, intent.dy); return
        case "insert":
            insertInSearch(intent.text); return
        case "clipboard":
            clipboardInSearch(intent.op); return
        case "deleteBack":
            deleteBackInSearch(); return
        case "cursorLeft":
            moveSearchCursor(-1); return
        case "cursorRight":
            moveSearchCursor(1); return
        case "advanceFromSearch":
            advanceFromSearch(); return
        case "setCategory":
            moveCategory(intent.direction); return
        case "engageSearch":
            engageSearch(); return
        case "focusGrid":
            focusGrid(); return
        case "leaveGridBackward":
            leaveGridBackward(); return
        case "navGrid":
            navigateGrid(intent.direction); return
        default:
            return
        }
    }

    function ensureSearchEngaged() {
        if (internalFocus !== "search") engageSearch()
        else wantsKeyboard = true
    }

    function insertInSearch(text) {
        ensureSearchEngaged()
        const p = searchInput.cursorPosition
        searchInput.text = searchInput.text.slice(0, p) + text + searchInput.text.slice(p)
        searchInput.cursorPosition = p + text.length
    }

    function clipboardInSearch(op) {
        ensureSearchEngaged()
        if (op === "selectAll") Qt.callLater(() => searchInput.selectAll())
        else if (op === "copy") Qt.callLater(() => searchInput.copy())
        else if (op === "cut") Qt.callLater(() => searchInput.cut())
        else if (op === "paste") Qt.callLater(() => searchInput.paste())
    }

    function deleteBackInSearch() {
        ensureSearchEngaged()
        const p = searchInput.cursorPosition
        if (p > 0) {
            searchInput.text = searchInput.text.slice(0, p - 1) + searchInput.text.slice(p)
            searchInput.cursorPosition = p - 1
        }
    }

    function moveSearchCursor(delta) {
        ensureSearchEngaged()
        const np = searchInput.cursorPosition + delta
        if (np >= 0 && np <= searchInput.text.length) searchInput.cursorPosition = np
    }

    function moveCategory(direction) {
        const ci = categoryMeta.findIndex(c => c.id === currentCategory)
        const target = direction === "left" ? ci - 1 : ci + 1
        if (target < 0 || target >= categoryMeta.length) return
        currentCategory = categoryMeta[target].id
        catBar.positionViewAtIndex(target, ListView.Contain)
    }

    function gridAtTop() {
        if (contentIndex === 0) {
            if (currentCategory === "recent") {
                if (recentEmojiItems.length > 0)
                    return gridSelectedIndex < Math.min(recentEmojiCols, recentEmojiItems.length)
                return gridSelectedIndex <= 0
            }
            if (currentCategory === "kaomoji") return gridSelectedIndex <= 0
            return gridSelectedIndex < browseGridColumns
        }
        // search
        if (searchEmojiItems.length > 0)
            return gridSelectedIndex < Math.min(searchEmojiCols, searchEmojiItems.length)
        return gridSelectedIndex <= 0
    }

    function navigateGrid(direction) {
        if (direction === "up" && gridAtTop()) { leaveGridBackward(); return }
        if (gridSelectedIndex < 0) { gridSelectedIndex = 0; return }
        if (contentIndex === 0) {
            if (currentCategory === "recent") {
                gridSelectedIndex = KeyNav.nextSearchIndex(direction, gridSelectedIndex,
                    recentEmojiItems.length, recentKaomojiItems.length, recentEmojiCols)
                ensureRecentVisible()
            } else if (currentCategory === "kaomoji") {
                gridSelectedIndex = KeyNav.nextKaomojiIndex(direction, gridSelectedIndex, browseItems.length)
                kaomojiListView.positionViewAtIndex(gridSelectedIndex, ListView.Contain)
            } else {
                gridSelectedIndex = KeyNav.nextBrowseIndex(direction, gridSelectedIndex, browseGridColumns, browseItems.length)
                browseGrid.positionViewAtIndex(gridSelectedIndex, GridView.Contain)
            }
        } else {
            gridSelectedIndex = KeyNav.nextSearchIndex(direction, gridSelectedIndex,
                searchEmojiItems.length, searchKaomojiItems.length, searchEmojiCols)
        }
    }

    function ensureRecentVisible() {
        if (gridSelectedIndex < 0) return
        const item = gridSelectedIndex < recentEmojiItems.length
            ? recentEmojiRepeater.itemAt(gridSelectedIndex)
            : recentKaomojiRepeater.itemAt(gridSelectedIndex - recentEmojiItems.length)
        if (!item) return
        const top = item.mapToItem(recentColumn, 0, 0).y
        const bottom = top + item.height
        if (top < recentFlickable.contentY)
            recentFlickable.contentY = top
        else if (bottom > recentFlickable.contentY + recentFlickable.height)
            recentFlickable.contentY = bottom - recentFlickable.height
    }

    function selectEmojiAt(idx) {
        if (contentIndex === 0) {
            if (currentCategory === "recent") {
                if (idx < recentEmojiItems.length) {
                    emojiSelected(recentEmojiItems[idx].text)
                } else {
                    const ki = idx - recentEmojiItems.length
                    if (ki < recentKaomojiItems.length) emojiSelected(recentKaomojiItems[ki].text)
                }
            } else if (idx >= 0 && idx < browseItems.length) {
                emojiSelected(browseItems[idx].text)
            }
        } else {
            const ei = searchEmojiItems.length
            if (idx < ei) {
                emojiSelected(searchEmojiItems[idx].text)
            } else {
                const ki = idx - ei
                if (ki < searchKaomojiItems.length) emojiSelected(searchKaomojiItems[ki].text)
            }
        }
    }

    function selectFirstEmoji() {
        if (isSearching) {
            if (searchEmojiItems.length > 0) { emojiSelected(searchEmojiItems[0].text); return }
            if (searchKaomojiItems.length > 0) { emojiSelected(searchKaomojiItems[0].text); return }
        } else if (browseItems.length > 0) {
            emojiSelected(browseItems[0].text)
        }
    }

    function refreshSearch() {
        if (!EmojiData.dataReady || searchText.length === 0) return
        const q = searchText, qlo = q.toLowerCase()
        const em = [], km = []
        const all = EmojiData.items
        for (let i = 0; i < all.length && em.length < 200; i++) {
            const item = all[i]
            if (matchItem(item, q, qlo)) {
                if (item.category === "kaomoji") km.push(item)
                else em.push(item)
            }
        }
        searchEmojiItems = em
        searchKaomojiItems = km
    }

    function matchItem(item, q, qlo) {
        if (item.text === q) return true
        if (item.name_en.toLowerCase().indexOf(qlo) >= 0) return true
        if (item.name_ja && item.name_ja.indexOf(q) >= 0) return true
        const ke = item.keywords_en || [], kj = item.keywords_ja || []
        for (let i = 0; i < ke.length; i++) if (ke[i].toLowerCase().indexOf(qlo) >= 0) return true
        for (let j = 0; j < kj.length; j++) if (kj[j].indexOf(q) >= 0) return true
        return false
    }

    Timer {
        id: searchTimer; interval: 120; repeat: false
        onTriggered: root.refreshSearch()
    }

    onDataReadyChanged: {
        if (dataReady) refreshRecentSnapshot()
    }

    onIsSearchingChanged: {
        gridSelectedIndex = isSearching ? 0 : (internalFocus === "grid" ? 0 : -1)
        if (!isSearching && currentCategory === "recent") refreshRecentSnapshot()
    }

    onCurrentCategoryChanged: {
        if (currentCategory === "recent") refreshRecentSnapshot()
        if (internalFocus === "grid") gridSelectedIndex = 0
    }

    onSearchTextChanged: {
        if (searchText.length > 0) searchTimer.restart()
    }

    Component.onCompleted: {
        Localization.sources = [Qt.resolvedUrl("data/locale/ja.po")]
        if (forceFocusable)
            Qt.callLater(() => searchInput.forceActiveFocus())
    }

    SystemPalette { id: palette; colorGroup: SystemPalette.Active }

    ColumnLayout {
        anchors { fill: parent; margins: 8 }
        spacing: 6

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Item {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 34

                Text {
                    anchors.centerIn: parent
                    text: "⠿"
                    font.pixelSize: 18
                    renderType: Text.NativeRendering
                    color: Qt.alpha(palette.windowText,
                                    dragArea.containsMouse || dragArea.drag.active ? 0.75 : 0.35)
                }

                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.SizeAllCursor
                    drag.target: root
                    drag.axis: Drag.XAndYAxis
                    drag.threshold: 0
                    drag.minimumX: 0
                    drag.maximumX: root.dragMaxX
                    drag.minimumY: 0
                    drag.maximumY: root.dragMaxY
                }
            }

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

                        TextInput {
                            id: searchInput
                            anchors.fill: parent
                            font.pixelSize: 14; color: palette.text
                            verticalAlignment: TextInput.AlignVCenter; clip: true
                            activeFocusOnPress: root.forceFocusable
                            cursorVisible: root.forceFocusable ? activeFocus
                                                               : root.internalFocus === "search"

                            Keys.onReturnPressed: { root.dlog("Qt Keys.Return"); root.selectFirstEmoji() }
                            Keys.onEnterPressed: { root.dlog("Qt Keys.Enter"); root.selectFirstEmoji() }
                            Keys.onEscapePressed: { root.dlog("Qt Keys.Escape"); root.closeRequested() }
                            Keys.onTabPressed: { root.dlog("Qt Keys.Tab"); root.advanceFromSearch() }
                            Keys.onBacktabPressed: { root.dlog("Qt Keys.Backtab"); root.internalFocus = "categories"; root.wantsKeyboard = false }
                            Keys.onDownPressed: { root.dlog("Qt Keys.Down"); root.advanceFromSearch() }
                        }

                        Text {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            text: _`Search emoji...`
                            color: Qt.alpha(palette.text, 0.38); font.pixelSize: 14
                            visible: searchInput.text.length === 0
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !root.wantsKeyboard && !root.forceFocusable
                            cursorShape: Qt.IBeamCursor
                            onClicked: root.engageSearch()
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
                                if (root.forceFocusable) searchInput.forceActiveFocus()
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
                    onClicked: Localization.localeCode = (Localization.localeCode === "ja" ? "en" : "ja")
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
                    const n = root.searchEmojiItems.length + root.searchKaomojiItems.length
                    return _(t`${n} result`, n, { other: t`${n} results`, zero: t`No results` })
                }
                if (root.currentCategory === "recent")
                    return _`Recently used`
                for (let i = 0; i < root.categoryMeta.length; i++) {
                    if (root.categoryMeta[i].id === root.currentCategory) {
                        const nm = root.language === "ja" ? root.categoryMeta[i].name_ja : root.categoryMeta[i].name_en
                        return nm + "  " + root.browseItems.length
                    }
                }
                return ""
            }
        }

        StackLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            currentIndex: root.contentIndex

            // Browse / Recent
            Item {
                GridView {
                    id: browseGrid
                    anchors.fill: parent; clip: true
                    cellWidth: 42; cellHeight: 42
                    model: root.browseItems
                    visible: root.currentCategory !== "recent" && root.currentCategory !== "kaomoji"
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: EmojiCell {
                        required property var modelData
                        required property int index
                        emojiChar: modelData.text
                        label: root.language === "ja" ? (modelData.name_ja || modelData.name_en) : modelData.name_en
                        selected: root.internalFocus === "grid" && index === root.gridSelectedIndex
                        onActivated: root.emojiSelected(emojiChar)
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: browseGrid.count === 0 && root.dataReady
                        text: _`No emoji here`
                        color: Qt.alpha(palette.windowText, 0.38); font.pixelSize: 13
                        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; width: 200
                    }
                }

                ListView {
                    id: kaomojiListView
                    anchors.fill: parent; clip: true; spacing: 1
                    model: root.browseItems
                    visible: root.currentCategory === "kaomoji"
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: KaomojiCell {
                        required property var modelData
                        required property int index
                        kaomojiText: modelData.text
                        label: root.language === "ja" ? modelData.name_ja : modelData.name_en
                        width: kaomojiListView.width
                        highlight: index % 2 === 0
                        selected: root.internalFocus === "grid" && index === root.gridSelectedIndex
                        onActivated: root.emojiSelected(kaomojiText)
                    }
                }

                Flickable {
                    id: recentFlickable
                    anchors.fill: parent; clip: true
                    visible: root.currentCategory === "recent"
                    contentHeight: recentColumn.implicitHeight
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    Column {
                        id: recentColumn
                        width: recentFlickable.width
                        spacing: 0

                        Flow {
                            width: parent.width
                            spacing: 2
                            visible: root.recentEmojiItems.length > 0
                            Repeater {
                                id: recentEmojiRepeater
                                model: root.recentEmojiItems
                                delegate: EmojiCell {
                                    required property var modelData
                                    required property int index
                                    emojiChar: modelData.text
                                    label: root.language === "ja" ? (modelData.name_ja || modelData.name_en) : modelData.name_en
                                    selected: root.internalFocus === "grid" && index === root.gridSelectedIndex
                                    onActivated: root.emojiSelected(emojiChar)
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: 1
                            visible: root.recentKaomojiItems.length > 0
                            Repeater {
                                id: recentKaomojiRepeater
                                model: root.recentKaomojiItems
                                delegate: KaomojiCell {
                                    required property var modelData
                                    required property int index
                                    kaomojiText: modelData.text
                                    label: root.language === "ja" ? modelData.name_ja : modelData.name_en
                                    width: recentColumn.width
                                    highlight: index % 2 === 0
                                    selected: root.internalFocus === "grid" && (root.recentEmojiItems.length + index) === root.gridSelectedIndex
                                    onActivated: root.emojiSelected(kaomojiText)
                                }
                            }
                        }

                        Item {
                            width: parent.width; height: 120
                            visible: root.recentEmojiItems.length === 0 && root.recentKaomojiItems.length === 0 && root.dataReady
                            Text {
                                anchors.centerIn: parent
                                text: _`No recently used emoji yet`
                                color: Qt.alpha(palette.windowText, 0.38); font.pixelSize: 13
                                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; width: 200
                            }
                        }
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
                                    emojiChar: modelData.text
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
                                text: _`Kaomoji`
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
                                text: _(t`No results for "${root.searchText}"`)
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
                text: _`Loading...`
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
                text: _`Can't reach the key-input service`
                color: palette.windowText; font.pixelSize: 15; font.bold: true
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            }
            Text {
                width: parent.width
                text: _`Check that fcitx5 and the emojizasu addon are running, then reopen.`
                color: Qt.alpha(palette.windowText, 0.55); font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            }
        }
    }

    Item {
        anchors { right: parent.right; bottom: parent.bottom }
        width: 16
        height: 16

        Text {
            anchors { right: parent.right; bottom: parent.bottom; rightMargin: 3; bottomMargin: 1 }
            text: "◢"
            font.pixelSize: 11
            renderType: Text.NativeRendering
            color: Qt.alpha(palette.windowText, resizeArea.containsMouse || resizeArea.pressed ? 0.7 : 0.3)
        }

        MouseArea {
            id: resizeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.SizeFDiagCursor
            property real pressSceneX
            property real pressSceneY
            property real pressW
            property real pressH
            onPressed: mouse => {
                const s = mapToItem(null, mouse.x, mouse.y)
                pressSceneX = s.x
                pressSceneY = s.y
                pressW = root.width
                pressH = root.height
            }
            onPositionChanged: mouse => {
                if (!pressed) return
                const s = mapToItem(null, mouse.x, mouse.y)
                root.resizeRequested(pressW + (s.x - pressSceneX), pressH + (s.y - pressSceneY))
            }
        }
    }
}
