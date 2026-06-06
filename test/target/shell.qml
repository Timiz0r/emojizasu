import QtQuick
import Quickshell
import Quickshell.Io

FloatingWindow {
    id: window
    title: "EmojizasuTestTarget"
    implicitWidth: 380
    implicitHeight: 120
    visible: true

    IpcHandler {
        target: "testtarget"
        function getText(): string { return input.text }
        function setText(t: string): void { input.text = t; input.cursorPosition = input.text.length }
        function clear(): void { input.text = ""; input.cursorPosition = 0 }
        function isActive(): bool { return root.windowActive }
    }

    Item {
        id: root
        anchors.fill: parent
        anchors.margins: 8
        readonly property bool windowActive: Window.active

        Column {
            anchors.fill: parent
            spacing: 6
            Text { text: "Target — emoji should land below (active=" + root.windowActive + ")" }
            Rectangle {
                width: parent.width; height: 32
                border.color: input.activeFocus ? "#3daee9" : "#888"
                border.width: 1
                TextInput {
                    id: input
                    anchors.fill: parent
                    anchors.margins: 4
                    focus: true
                    verticalAlignment: TextInput.AlignVCenter
                }
            }
        }
    }

    Component.onCompleted: requestActivate()
    onClosed: Qt.quit()
}
