import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import net.blumia.pineapple.streamrecordingexporter
import "components"

Page {
    id: root

    signal clipSelected(var clip)
    signal backRequested
    signal exportedVideosRequested

    title: qsTr("Recording List")

    header: ToolBar {
        RowLayout {
            anchors.fill: parent

            ToolButton {
                icon.name: "go-previous"
                text: qsTr("Back")
                onClicked: root.backRequested()
            }

            Label {
                text: qsTr("Steam Game Recordings")
                font.pixelSize: 18
                font.weight: Font.Medium
                Layout.fillWidth: true
            }

            ToolButton {
                icon.name: "folder-videos-symbolic"
                text: qsTr("Exported Videos")
                onClicked: root.exportedVideosRequested()

                ToolTip.visible: hovered
                ToolTip.text: qsTr("View and manage exported videos")
            }

            ToolButton {
                icon.name: "system-switch-user"
                text: qsTr("Switch User")
                enabled: recordingManager ? (!recordingManager.isScanning && recordingManager.hasMultipleUsers) : false
                visible: recordingManager ? recordingManager.hasMultipleUsers : false
                onClicked: userSelectionDialog.open()

                ToolTip.visible: hovered
                ToolTip.text: qsTr("Select different Steam account")
            }

            ToolButton {
                icon.name: "view-refresh"
                text: qsTr("Refresh")
                enabled: recordingManager ? !recordingManager.isScanning : false
                onClicked: {
                    if (recordingManager) {
                        recordingManager.refreshClips();
                    }
                }

                BusyIndicator {
                    Material.accent: "#8ab4f8"
                    anchors.centerIn: parent
                    running: recordingManager ? recordingManager.isScanning : false
                    visible: running
                    implicitWidth: 16
                    implicitHeight: 16
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16

        // Status and stats
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: statsColumn.implicitHeight + 32
            color: Material.backgroundColor
            border.color: Material.dividerColor
            border.width: 1
            radius: 8

            ColumnLayout {
                id: statsColumn
                anchors.fill: parent
                anchors.margins: 16

                RowLayout {
                    Layout.fillWidth: true

                    Label {
                        text: qsTr("Found Recordings")
                        font.pixelSize: 16
                        font.weight: Font.Medium
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Label {
                        text: recordingManager ? recordingManager.clipCount.toString() : "0"
                        font.pixelSize: 20
                        font.weight: Font.Bold
                        color: Material.foreground
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Label {
                        text: recordingManager && recordingManager.selectedUserId ? qsTr("Current User: %1").arg(recordingManager.getUserDisplayName(recordingManager.selectedUserId)) : qsTr("No user selected")
                        font.pixelSize: 12
                        color: Material.hintTextColor
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }

                    Label {
                        text: recordingManager && recordingManager.gameRecordingsPath ? qsTr("Scanning: %1").arg(recordingManager.gameRecordingsPath) : qsTr("No recordings path configured")
                        font.pixelSize: 12
                        color: Material.hintTextColor
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                }
            }
        }

        // Main content area
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true

            currentIndex: {
                if (!recordingManager)
                    return 2;
                if (recordingManager.isScanning)
                    return 0;
                if (recordingManager.hasClips)
                    return 1;
                return 2;
            }

            // Loading state
            Item {
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 16

                    BusyIndicator {
                        Material.accent: "#8ab4f8"
                        running: true
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 64
                        implicitHeight: 64
                    }

                    Label {
                        text: qsTr("Scanning for recording clips...")
                        font.pixelSize: 16
                        Layout.alignment: Qt.AlignHCenter
                    }

                    ScrollView {
                        Layout.preferredWidth: 600
                        Layout.preferredHeight: 200
                        clip: true

                        TextArea {
                            text: recordingManager ? recordingManager.scanResults.join('\n') : ""
                            readOnly: true
                            wrapMode: Text.WordWrap
                            font.family: "Consolas, Monaco, monospace"
                            font.pixelSize: 11
                            color: Material.hintTextColor

                            background: Rectangle {
                                color: "#2a2a30"
                                radius: 4
                                border.color: Material.dividerColor
                                border.width: 1
                            }
                        }
                    }
                }
            }

            // Full recordings and saved clips, each in their own tab
            ColumnLayout {
                spacing: 8

                TabBar {
                    Material.accent: "#8ab4f8"
                    id: recordingTabBar
                    Layout.fillWidth: true

                    TabButton {
                        text: qsTr("Full Recordings (%1)").arg(backgroundRecordingsModel.count)
                    }
                    TabButton {
                        text: qsTr("Clips (%1)").arg(savedClipsModel.count)
                    }
                }

                RecordingFilterModel {
                    id: backgroundRecordingsModel
                    sourceModel: recordingManager
                    backgroundRecordings: true
                }

                RecordingFilterModel {
                    id: savedClipsModel
                    sourceModel: recordingManager
                    backgroundRecordings: false
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    ListView {
                        id: clipsListView

                        model: recordingTabBar.currentIndex === 0 ? backgroundRecordingsModel : savedClipsModel
                        spacing: 12

                        delegate: RecordingCard {
                            width: clipsListView.width
                            recordingClip: model.clip

                            onCardClicked: {
                                root.clipSelected(model.clip);
                            }
                        }

                        Label {
                            anchors.centerIn: parent
                            visible: clipsListView.count === 0
                            text: recordingTabBar.currentIndex === 0
                                  ? qsTr("No full recordings found.\nTurn on background recording in Steam's Game Recording settings.")
                                  : qsTr("No clips yet.\nOpen a full recording and set a start and end to make one.")
                            horizontalAlignment: Text.AlignHCenter
                            color: Material.hintTextColor
                        }

                        // Pull to refresh
                        property bool refreshing: false

                        onContentYChanged: {
                            if (contentY < -80 && !refreshing && recordingManager && !recordingManager.isScanning) {
                                refreshing = true;
                                recordingManager.refreshClips();
                                refreshTimer.start();
                            }
                        }

                        Timer {
                            id: refreshTimer
                            interval: 1000
                            onTriggered: clipsListView.refreshing = false
                        }

                        // Add some padding at the bottom
                        footer: Item {
                            height: 20
                        }
                    }
                }
            }

            // Empty state
            Item {
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 16

                    Label {
                        text: "🎮"
                        font.pixelSize: 64
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Label {
                        text: qsTr("No recording clips found")
                        font.pixelSize: 18
                        font.weight: Font.Medium
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Label {
                        text: qsTr("Make sure you have game recordings in Steam.\nRecordings are saved automatically during gameplay\nwhen Steam's Game Recording feature is enabled.")
                        font.pixelSize: 14
                        color: Material.hintTextColor
                        horizontalAlignment: Text.AlignHCenter
                        Layout.alignment: Qt.AlignHCenter
                        Layout.maximumWidth: 400
                        wrapMode: Text.WordWrap
                    }

                    Button {
                        text: qsTr("Refresh")
                        onClicked: {
                            if (recordingManager) {
                                recordingManager.refreshClips();
                            }
                        }
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 16
                    }
                }
            }
        }
    }

    // Steam user selection dialog
    SteamUserSelectionDialog {
        id: userSelectionDialog

        onUserSelected: function (userId) {
            if (recordingManager) {
                recordingManager.selectedUserId = userId;
                recordingManager.refreshClips();
            }
        }
    }

    // Auto-start scanning when page loads
    Component.onCompleted: {
        console.log("RecordingListPage: Component completed");
        if (recordingManager) {
            console.log("RecordingListPage: recordingManager exists");
            console.log("RecordingListPage: hasMultipleUsers:", recordingManager.hasMultipleUsers);
            console.log("RecordingListPage: selectedUserId:", recordingManager.selectedUserId);
            console.log("RecordingListPage: availableUsers count:", recordingManager.availableUsers.length);

            // Force refresh users first to ensure data is up to date
            recordingManager.refreshAvailableUsers();

            // Use a timer to delay the decision until after property updates
            startupTimer.start();
        }
    }

    // Timer to handle startup logic after properties are updated
    Timer {
        id: startupTimer
        interval: 100
        repeat: false
        onTriggered: {
            if (recordingManager) {
                console.log("RecordingListPage: Startup timer triggered");
                console.log("RecordingListPage: hasMultipleUsers:", recordingManager.hasMultipleUsers);
                console.log("RecordingListPage: selectedUserId:", recordingManager.selectedUserId);
                console.log("RecordingListPage: availableUsers count:", recordingManager.availableUsers.length);

                // Check if we need to show user selection dialog
                if (recordingManager.hasMultipleUsers && (!recordingManager.selectedUserId || recordingManager.gameRecordingsPath === "")) {
                    console.log("RecordingListPage: Opening user selection dialog - no user selected or no recordings path");
                    userSelectionDialog.open();
                } else if (!recordingManager.hasClips) {
                    console.log("RecordingListPage: Starting scan");
                    recordingManager.startScan();
                }
            }
        }
    }

    // Handle recording manager changes
    Connections {
        target: recordingManager

        function onHasMultipleUsersChanged() {
            console.log("RecordingListPage: onHasMultipleUsersChanged, hasMultipleUsers:", recordingManager ? recordingManager.hasMultipleUsers : false);
            if (recordingManager && recordingManager.hasMultipleUsers && (!recordingManager.selectedUserId || recordingManager.gameRecordingsPath === "")) {
                console.log("RecordingListPage: Opening user selection dialog from signal");
                userSelectionDialog.open();
            }
        }

        function onAvailableUsersChanged() {
            console.log("RecordingListPage: onAvailableUsersChanged, count:", recordingManager ? recordingManager.availableUsers.length : 0);
        }

        function onSelectedUserIdChanged() {
            console.log("RecordingListPage: onSelectedUserIdChanged, selectedUserId:", recordingManager ? recordingManager.selectedUserId : "");
            // If user changed but still has no recordings path, show dialog again
            if (recordingManager && recordingManager.hasMultipleUsers && recordingManager.selectedUserId && recordingManager.gameRecordingsPath === "") {
                console.log("RecordingListPage: Selected user has no recordings, reopening dialog");
                userSelectionDialog.open();
            }
        }
    }
}
