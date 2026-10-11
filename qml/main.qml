import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import net.blumia.pineapple.streamrecordingexporter

ApplicationWindow {
    id: mainWindow
    
    visible: true
    // Tall enough to show the whole preview & export page without scrolling
    width: 1280
    height: 1000
    minimumWidth: 800
    minimumHeight: 600
    
    title: qsTr("Pineapple Steam Recording Exporter")
    
    Material.theme: Material.Dark
    Material.primary: "#121212"
    // Dark blue for filled buttons (white text); controls drawn on the dark
    // background (tabs, sliders, dialogs) override it with a light blue
    Material.accent: "#1a3d6e"
    
    // Global properties
    property string currentPage: "editor"
    property var selectedClip: null
    property int selectedSegmentIndex: -1
    property var selectedExportedVideo: null
    
    // Auto-fullscreen in SteamOS game mode
    Component.onCompleted: {
        if (systemChecker && systemChecker.isSteamGameMode) {
            mainWindow.showFullScreen()
        }
        systemChecker.startSystemCheck()
    }
    
    // Page stack for navigation
    StackView {
        id: pageStack
        anchors.fill: parent
        
        // The editor is the main screen; the system check runs in the
        // background and only shows up when something is missing
        initialItem: editorComponent
    }

    Component {
        id: systemCheckComponent

        SystemCheckPage {
            onSystemCheckPassed: {
                pageStack.pop()
                currentPage = "editor"
            }
        }
    }

    Connections {
        target: systemChecker

        function onSystemCheckCompleted() {
            if (pageStack.depth > 1 && currentPage === "systemCheck") {
                return // The visible check page handles rechecks itself
            }
            if (systemChecker.allChecksPass) {
                recordingManager.steamPath = systemChecker.steamPath
                recordingManager.startScan()
            } else {
                pageStack.push(systemCheckComponent)
                currentPage = "systemCheck"
            }
        }
    }
    
    // Components for different pages
    Component {
        id: editorComponent

        EditorPage {
            onExportedVideosRequested: {
                pageStack.push(exportedVideosComponent)
                currentPage = "exportedVideos"
            }
        }
    }

    Component {
        id: recordingListComponent
        
        RecordingListPage {
            onClipSelected: function(clip) {
                console.log("main.qml - Received clipSelected signal with clip:", clip)
                console.log("main.qml - Clip appId:", clip ? clip.appId : "null")
                console.log("main.qml - Clip segmentCount:", clip ? clip.segmentCount : "null")
                selectedClip = clip
                if (clip.segmentCount > 1) {
                    // Show clip selection page for multi-segment recordings
                    console.log("main.qml - Navigating to clip selection (multi-segment)")
                    pageStack.push(clipSelectionComponent)
                    currentPage = "clipSelection"
                } else {
                    // Go directly to preview for single-segment recordings
                    console.log("main.qml - Navigating to preview (single segment)")
                    selectedSegmentIndex = 0
                    pageStack.push(previewAndExportComponent)
                    currentPage = "previewAndExport"
                }
            }
            
            onExportedVideosRequested: {
                pageStack.push(exportedVideosComponent)
                currentPage = "exportedVideos"
            }
            
            onBackRequested: {
                pageStack.pop()
                currentPage = "systemCheck"
            }
        }
    }
    
    Component {
        id: clipSelectionComponent
        
        ClipSelectionPage {
            clip: selectedClip
            
            onSegmentSelected: function(segmentIndex) {
                selectedSegmentIndex = segmentIndex
                pageStack.push(previewAndExportComponent)
                currentPage = "previewAndExport"
            }
            
            onBackRequested: {
                pageStack.pop()
                currentPage = "recordingList"
                selectedClip = null
            }
        }
    }
    
    Component {
        id: previewAndExportComponent
        
        PreviewAndExportPage {
            clip: selectedClip
            segmentIndex: selectedSegmentIndex
            
            onBackRequested: {
                if (selectedClip && selectedClip.segmentCount > 1) {
                    pageStack.pop()
                    currentPage = "clipSelection"
                } else {
                    pageStack.pop()
                    currentPage = "recordingList"
                    selectedClip = null
                }
                selectedSegmentIndex = -1
            }
            
            onExportCompleted: {
                // Could show a success message or navigate back
                console.log("Export completed successfully")
            }
        }
    }
    
    Component {
        id: exportedVideosComponent
        
        ExportedVideosPage {
            onVideoSelected: function(video) {
                selectedExportedVideo = video
                pageStack.push(videoPreviewComponent)
                currentPage = "videoPreview"
            }
            
            onBackRequested: {
                pageStack.pop()
                currentPage = "editor"
                selectedExportedVideo = null
            }
        }
    }
    
    Component {
        id: videoPreviewComponent
        
        VideoPreviewPage {
            video: selectedExportedVideo
            
            onBackRequested: {
                pageStack.pop()
                currentPage = "exportedVideos"
                selectedExportedVideo = null
            }
            
            onVideoDeleted: {
                // Go back to exported videos list
                pageStack.pop()
                currentPage = "exportedVideos"
                selectedExportedVideo = null
            }
        }
    }
    
    // Global shortcuts
    Shortcut {
        sequences: [StandardKey.Back]
        enabled: pageStack.depth > 1 && currentPage !== "systemCheck"
        onActivated: {
            if (pageStack.depth > 1) {
                pageStack.pop()
                updateCurrentPage()
            }
        }
    }
    
    Shortcut {
        sequences: ["Escape"]
        enabled: pageStack.depth > 1 && currentPage !== "systemCheck"
        onActivated: {
            if (pageStack.depth > 1) {
                pageStack.pop()
                updateCurrentPage()
            }
        }
    }
    
    Shortcut {
        sequences: [StandardKey.Quit]
        onActivated: Qt.quit()
    }
    
    Shortcut {
        sequences: ["Ctrl+R"]
        enabled: currentPage === "editor"
        onActivated: {
            if (recordingManager) {
                recordingManager.refreshClips()
            }
        }
    }
    
    // Functions
    function updateCurrentPage() {
        switch (pageStack.depth) {
        case 1:
            currentPage = "editor"
            break
        case 2:
            currentPage = "exportedVideos"
            break
        case 3:
            currentPage = "videoPreview"
            break
        }
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
        id: languageDialog

        contentWidth: 220
        anchors.centerIn: parent
        modal: true
        title: qsTr("Language")

        ColumnLayout {
            anchors.fill: parent

            ComboBox {
                Layout.fillWidth: true
                id: languageComboBox
                model: languageManager.availableLanguages
                currentIndex: languageManager.availableLanguages.indexOf(languageManager.currentLanguage)
                displayText: Qt.locale(currentText).nativeLanguageName
                delegate: ItemDelegate {
                    width: languageComboBox.width
                    text: Qt.locale(modelData).nativeLanguageName
                }
                onCurrentIndexChanged: {
                    languageManager.setLanguage(valueAt(currentIndex))
                }
            }
        }
        
        standardButtons: Dialog.Ok
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
    
    // Status bar
    footer: ToolBar {
        height: 30
        
        RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            
            Label {
                text: {
                    switch (currentPage) {
                    case "systemCheck":
                        return qsTr("System Check")
                    case "editor":
                        return recordingManager && recordingManager.isScanning ? qsTr("Scanning for recordings…") : ""
                    case "recordingList":
                        return qsTr("Recording List") + 
                               (recordingManager ? " (" + recordingManager.clipCount + " clips)" : "")
                    case "clipSelection":
                        return qsTr("Clip Selection")
                    case "previewAndExport":
                        return qsTr("Preview & Export")
                    case "exportedVideos":
                        return qsTr("Exported Videos") + 
                               (exportedVideoManager ? " (" + exportedVideoManager.videoCount + " videos)" : "")
                    case "videoPreview":
                        return selectedExportedVideo ? selectedExportedVideo.displayName : qsTr("Video Preview")
                    default:
                        return ""
                    }
                }
                font.pixelSize: 12
                color: Material.foreground
            }
            
            Item { Layout.fillWidth: true }
            
            Label {
                id: languageButton
                text: `🌐 ${qsTr("Language")}`
                font.pixelSize: 12
                TapHandler {
                    onTapped: {
                        languageDialog.open()
                    }
                }
                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                }
            }
            
            Label {
                visible: videoExporter && videoExporter.isExporting
                text: videoExporter ? videoExporter.currentOperation + " (" + videoExporter.progress + "%)" : ""
                font.pixelSize: 12
                color: Material.foreground
            }
            
            BusyIndicator {
                Material.accent: "#8ab4f8"
                visible: (systemChecker && systemChecker.isChecking) ||
                         (recordingManager && recordingManager.isScanning) ||
                         (videoExporter && videoExporter.isExporting) ||
                         (exportedVideoManager && exportedVideoManager.isScanning)
                running: visible
                implicitWidth: 20
                implicitHeight: 20
            }
        }
    }
}
