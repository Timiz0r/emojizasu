pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

Item {
    id: root

    property string currentCategory: ""
    property var browseItems: []
    property var recentEmojiItems: []
    property var recentKaomojiItems: []
    property int gridSelectedIndex: 0
    property bool gridFocused: false
    property bool dataReady: false

    readonly property int browseColumnCount: browseGrid.width > 0
        ? Math.max(1, Math.floor(browseGrid.width / 42)) : 1
    readonly property int recentColumnCount: browseGrid.width > 0
        ? Math.max(1, Math.floor(browseGrid.width / 42)) : 1

    signal emojiSelected(string emoji)

    function positionBrowseAt(idx) { browseGrid.positionViewAtIndex(idx, GridView.Contain) }
    function positionKaomojiAt(idx) { kaomojiListView.positionViewAtIndex(idx, ListView.Contain) }

    // the recent pane is special in its layout that it doesn't inherently scroll
    // when selecting something with arrow keys.
    function ensureRecentVisible(idx) {
        if (idx < 0) return
        const item = idx < root.recentEmojiItems.length
            ? recentEmojiRepeater.itemAt(idx)
            : recentKaomojiRepeater.itemAt(idx - root.recentEmojiItems.length)
        if (!item) return
        const top = item.mapToItem(recentColumn, 0, 0).y
        const bottom = top + item.height
        if (top < recentFlickable.contentY)
            recentFlickable.contentY = top
        else if (bottom > recentFlickable.contentY + recentFlickable.height)
            recentFlickable.contentY = bottom - recentFlickable.height
    }

    readonly property var t: Localization.t
    function _() { return Localization._.apply(null, arguments) }

    SystemPalette { id: palette; colorGroup: SystemPalette.Active }

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
            emojiChar: modelData
            label: EmojiData.nameFor(modelData)
            selected: root.gridFocused && index === root.gridSelectedIndex
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
            kaomojiText: modelData
            label: EmojiData.nameFor(modelData)
            width: kaomojiListView.width
            highlight: index % 2 === 0
            selected: root.gridFocused && index === root.gridSelectedIndex
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
                spacing: 0
                visible: root.recentEmojiItems.length > 0
                Repeater {
                    id: recentEmojiRepeater
                    model: root.recentEmojiItems
                    delegate: EmojiCell {
                        required property var modelData
                        required property int index
                        emojiChar: modelData
                        label: EmojiData.nameFor(modelData)
                        selected: root.gridFocused && index === root.gridSelectedIndex
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
                        kaomojiText: modelData
                        label: EmojiData.nameFor(modelData)
                        width: recentColumn.width
                        highlight: index % 2 === 0
                        selected: root.gridFocused && (root.recentEmojiItems.length + index) === root.gridSelectedIndex
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
