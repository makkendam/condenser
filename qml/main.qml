import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import CondenserApp

ApplicationWindow {
    id: mainWindow

    visible: true
    // Most of the screen height: a big player and still room for a good part
    // of the session list. The width then follows from the player, so a 16:9
    // recording fills it without black bars (see playerArea in EditorPage.qml:
    // 58% of the height, 12 px margins).
    height: Math.min(1500, Math.round(Screen.desktopAvailableHeight * 0.92))
    width: 1280
    minimumWidth: 800
    minimumHeight: 600

    title: qsTr("Condenser")

    Material.theme: Material.Dark
    Material.primary: "#121212"
    // Dark blue for filled buttons (white text); controls drawn on the dark
    // background (tabs, sliders, dialogs) override it with a light blue
    Material.accent: "#1a3d6e"

    // Auto-fullscreen in SteamOS game mode
    Component.onCompleted: {
        // Set once rather than bound, so resizing the window later stays free
        width = Math.min(Screen.desktopAvailableWidth, Math.round(height * 0.58 * 16 / 9) + 24)
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
        title: qsTr("About Condenser")

        Label {
            text: `
Condenser turns Steam game recordings into clips.

- Based on [Pineapple Steam Recording Exporter](https://github.com/BLumia/pineapple-steam-recording-exporter), copyright 2026 [Gary "BLumia" Wang](https://github.com/BLumia/)
- Changes copyright 2026 makkendam
- License: [GPL-3.0-only](https://spdx.org/licenses/GPL-3.0-only.html)
`
            textFormat: TextEdit.MarkdownText
            onLinkActivated: function(link) {
                Qt.openUrlExternally(link)
            }
        }

        standardButtons: Dialog.Ok
    }
}
