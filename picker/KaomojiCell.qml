import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Rectangle {
    id: cell
    height: 44

    property string kaomojiText: ""
    property string label: ""
    property bool highlight: false

    signal activated()

    SystemPalette { id: pal; colorGroup: SystemPalette.Active }

    color: ma.containsMouse ? Qt.alpha(pal.highlight, 0.15)
           : highlight ? Qt.alpha(pal.windowText, 0.03) : "transparent"
    radius: 5

    RowLayout {
        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
        spacing: 12

        Text {
            Layout.minimumWidth: 160
            text: cell.kaomojiText
            font.pixelSize: 14
            font.family: "monospace"
            color: pal.windowText
            elide: Text.ElideRight
        }

        Text {
            Layout.fillWidth: true
            text: cell.label
            font.pixelSize: 12
            color: Qt.alpha(pal.windowText, 0.5)
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: cell.activated()
    }
}
