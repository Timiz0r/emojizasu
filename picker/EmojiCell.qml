import QtQuick
import QtQuick.Controls

Item {
    id: cell
    width: 42; height: 42

    property string emojiChar: ""
    property string label: ""

    signal activated()

    SystemPalette { id: pal; colorGroup: SystemPalette.Active }

    Rectangle {
        anchors { fill: parent; margins: 2 }
        radius: 6
        color: ma.containsMouse ? Qt.alpha(pal.highlight, 0.2) : "transparent"

        Text {
            anchors.centerIn: parent
            text: cell.emojiChar
            font.pixelSize: 24
            renderType: Text.NativeRendering
        }

        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cell.activated()

            ToolTip.visible: containsMouse
            ToolTip.delay: 500
            ToolTip.text: cell.emojiChar + (cell.label ? "  " + cell.label : "")
        }
    }
}
