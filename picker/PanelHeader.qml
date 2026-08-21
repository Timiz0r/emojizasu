import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property var dragTarget: null
    property real dragMaxX: 0
    property real dragMaxY: 0

    property string internalFocus: "search"
    property bool wantsKeyboard: false
    property bool forceFocusable: false
    property string language: "en"

    property alias searchText: searchInput.text
    property alias searchCursorPosition: searchInput.cursorPosition
    property alias searchSelectionStart: searchInput.selectionStart
    property alias searchSelectionEnd: searchInput.selectionEnd
    property alias searchSelectedText: searchInput.selectedText
    readonly property bool inputActiveFocus: searchInput.activeFocus

    signal closeRequested()
    signal searchAreaClicked()
    signal inputFocusLost()
    signal returnKeyPressed()
    signal escapeKeyPressed()
    signal tabKeyPressed()
    signal backtabKeyPressed()
    signal downKeyPressed()

    function focusInput() { searchInput.forceActiveFocus() }
    function blurInput() { searchInput.focus = false }
    function selectAll() { searchInput.selectAll() }
    function deselect() { searchInput.deselect() }

    readonly property var t: Localization.t
    function _() { return Localization._.apply(null, arguments) }

    SystemPalette { id: palette; colorGroup: SystemPalette.Active }

    Connections {
        target: searchInput
        function onActiveFocusChanged() {
            if (!searchInput.activeFocus) root.inputFocusLost()
        }
    }

    RowLayout {
        anchors.fill: parent
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
                drag.target: root.dragTarget
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
                        persistentSelection: true
                        cursorVisible: root.forceFocusable ? activeFocus
                                                           : root.internalFocus === "search"

                        Keys.onReturnPressed: root.returnKeyPressed()
                        Keys.onEnterPressed: root.returnKeyPressed()
                        Keys.onEscapePressed: root.escapeKeyPressed()
                        Keys.onTabPressed: root.tabKeyPressed()
                        Keys.onBacktabPressed: root.backtabKeyPressed()
                        Keys.onDownPressed: root.downKeyPressed()
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
                        onClicked: root.searchAreaClicked()
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
                            if (root.forceFocusable) root.focusInput()
                        }
                    }
                }
            }
        }

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
}
