pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

Item {
    id: root

    property var searchEmojiItems: []
    property var searchKaomojiItems: []
    property int gridSelectedIndex: 0
    property bool gridFocused: false
    property bool isSearching: false
    property bool dataReady: false
    property string searchText: ""

    readonly property int emojiColumnCount: searchFlickable.width > 0
        ? Math.max(1, Math.floor((searchFlickable.width + 2) / 44)) : 1

    signal emojiSelected(string emoji)

    readonly property var t: Localization.t
    function _() { return Localization._.apply(null, arguments) }

    SystemPalette { id: palette; colorGroup: SystemPalette.Active }

    Flickable {
        id: searchFlickable
        anchors.fill: parent; clip: true
        contentHeight: searchColumn.implicitHeight
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            id: searchColumn
            width: searchFlickable.width
            spacing: 0

            Flow {
                width: parent.width
                spacing: 2
                visible: root.searchEmojiItems.length > 0
                Repeater {
                    model: root.searchEmojiItems
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

            Column {
                width: parent.width
                spacing: 1
                visible: root.searchKaomojiItems.length > 0
                Repeater {
                    model: root.searchKaomojiItems
                    delegate: KaomojiCell {
                        required property var modelData
                        required property int index
                        kaomojiText: modelData
                        label: EmojiData.nameFor(modelData)
                        width: searchColumn.width
                        highlight: index % 2 === 0
                        selected: root.gridFocused && (root.searchEmojiItems.length + index) === root.gridSelectedIndex
                        onActivated: root.emojiSelected(kaomojiText)
                    }
                }
            }

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
