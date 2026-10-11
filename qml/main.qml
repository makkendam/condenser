import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import net.blumia.pineapple.streamrecordingexporter

ApplicationWindow {
    id: mainWindow

    visible: true
    // Most of the screen: a big player and still room for a good part of the session list
    width: Math.min(1700, Math.round(Screen.desktopAvailableWidth * 0.85))
    height: Math.min(1500, Math.round(Screen.desktopAvailableHeight * 0.92))
    minimumWidth: 800
    minimumHeight: 600

    title: qsTr("Pineapple Steam Recording Exporter")

    Material.theme: Material.Dark
    Material.primary: "#121212"
    // Dark blue for filled buttons (white text); controls drawn on the dark
    // background (tabs, sliders, dialogs) override it with a light blue
    Material.accent: "#1a3d6e"

    // Auto-fullscreen in SteamOS game mode
    Component.onCompleted: {
        if (systemChecker && systemChecker.isSteamGameMode) {
            mainWindow.showFullScreen()
        }
        systemChecker.startSystemCheck()
    }

    // The editor is the main screen; the system check runs in the background
    // and its page only shows up on top when something is missing
    StackView {
        id: pageStack
        anchors.fill: parent
        initialItem: EditorPage {}
    }

    Component {
        id: systemCheckComponent

        SystemCheckPage {
            onSystemCheckPassed: pageStack.pop()
        }
    }

    Connections {
        target: systemChecker

        function onSystemCheckCompleted() {
            if (pageStack.depth > 1) {
                return // The visible check page handles rechecks itself
            }
            if (systemChecker.allChecksPass) {
                recordingManager.steamPath = systemChecker.steamPath
                recordingManager.startScan()
            } else {
                pageStack.push(systemCheckComponent)
            }
        }
    }

    Shortcut {
        sequences: [StandardKey.Quit]
        onActivated: Qt.quit()
    }

    Shortcut {
        sequences: ["Ctrl+R"]
        enabled: pageStack.depth === 1
        onActivated: recordingManager.refreshClips()
    }

    // Handle window close
    onClosing: function(close) {
        if (videoExporter && videoExporter.isExporting) {
            // Show confirmation dialog if export is in progress
            close.accepted = false
            confirmExitDialog.open()
        }
    }

    // Exit confirmation dialog
    Dialog {
        Material.accent: "#8ab4f8"
        id: confirmExitDialog

        anchors.centerIn: parent
        modal: true
        title: qsTr("Export in Progress")

        Label {
            text: qsTr("An export operation is currently in progress. Are you sure you want to exit?")
            wrapMode: Text.WordWrap
        }

        standardButtons: Dialog.Yes | Dialog.No

        onAccepted: {
            if (videoExporter) {
                videoExporter.cancelExport()
            }
            Qt.quit()
        }
    }

    Dialog {
        Material.accent: "#8ab4f8"
        id: aboutDialog

        anchors.centerIn: parent
        modal: true
        title: qsTr("About")

        Label {
            text: `
- Source Code: [GitHub](https://github.com/BLumia/pineapple-steam-recording-exporter)
- Copyright: 2026 [Gary "BLumia" Wang](https://github.com/BLumia/)
- License: [GPL-3.0-only](https://spdx.org/licenses/GPL-3.0-only.html)
- Donate: [Ko-fi](https://ko-fi.com/blumia)
`
            textFormat: TextEdit.MarkdownText
            onLinkActivated: {
                Qt.openUrlExternally(link)
            }
        }

        standardButtons: Dialog.Ok
        footer: DialogButtonBox {
            Button {
                flat: true
                text: qsTr("Donate")
                DialogButtonBox.buttonRole: DialogButtonBox.Open
                onClicked: {
                    Qt.openUrlExternally("https://link.blumia.net/pineapple-apps-donate")
                }
            }
        }
    }
}
