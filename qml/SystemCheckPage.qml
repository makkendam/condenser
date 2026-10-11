import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import CondenserApp

// Shown only when Steam or FFmpeg can't be found
Page {
    id: root

    signal systemCheckPassed()

    Connections {
        target: systemChecker
        function onSystemCheckCompleted() {
            if (systemChecker.allChecksPass) {
                recordingManager.steamPath = systemChecker.steamPath
                recordingManager.startScan()
                root.systemCheckPassed()
            }
        }
    }

    component Requirement: RowLayout {
        property bool found
        property string name
        property string hint
        spacing: 12
        Layout.fillWidth: true

        Label {
            text: parent.found ? "✓" : "✗"
            color: parent.found ? "#8ab4f8" : "#f28b82"
            font.pixelSize: 20
            Layout.alignment: Qt.AlignTop
        }
        ColumnLayout {
            spacing: 2
            Layout.fillWidth: true
            Label { text: parent.parent.name; font.weight: Font.Medium }
            Label {
                visible: !parent.parent.found
                text: parent.parent.hint
                color: Material.hintTextColor
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 460)
        spacing: 16

        Label {
            text: qsTr("Condenser can't start yet")
            font.pixelSize: 22
            font.weight: Font.Medium
        }

        Requirement {
            found: systemChecker.steamFound
            name: qsTr("Steam")
            hint: qsTr("No Steam installation found. Install Steam, or the Steam Flatpak, and record some gameplay first.")
        }

        Requirement {
            found: systemChecker.ffmpegFound
            name: qsTr("FFmpeg")
            hint: qsTr("FFmpeg is needed for exports and previews. Install it and make sure it is on your PATH.")
        }

        RowLayout {
            Layout.topMargin: 8
            spacing: 8

            Button {
                text: qsTr("Check Again")
                highlighted: true
                onClicked: systemChecker.startSystemCheck()
            }
            Button {
                text: qsTr("Download FFmpeg")
                flat: true
                visible: !systemChecker.ffmpegFound
                onClicked: Qt.openUrlExternally("https://ffmpeg.org/download.html")
            }
            Button {
                text: qsTr("Quit")
                flat: true
                onClicked: Qt.quit()
            }
        }
    }
}
