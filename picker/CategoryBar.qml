pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

Rectangle {
    id: root

    property var categoryMeta: []
    property string currentCategory: ""
    property bool focused: false

    signal categoryActivated(string id)

    function moveTo(direction) {
        const ci = categoryMeta.findIndex(c => c.id === currentCategory)
        const target = direction === "left" ? ci - 1 : ci + 1
        if (target < 0 || target >= categoryMeta.length) return
        catList.positionViewAtIndex(target, ListView.Contain)
        categoryActivated(categoryMeta[target].id)
    }

    color: "transparent"
    radius: 6
    border.color: root.focused ? Qt.alpha(palette.highlight, 0.6) : "transparent"
    border.width: 1

    SystemPalette { id: palette; colorGroup: SystemPalette.Active }

    ListView {
        id: catList
        anchors.fill: parent
        orientation: ListView.Horizontal
        spacing: 1
        clip: true
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
                    onClicked: root.categoryActivated(modelData.id)
                    ToolTip.visible: containsMouse; ToolTip.delay: 600
                    ToolTip.text: modelData.name
                }
            }
        }
    }
}
