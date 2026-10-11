import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import CondenserApp
import "components"

// Main screen: a big player with a clip editor, and the recordings to pick
// from underneath. Opens on the most recent background recording.
Page {
    id: root

    // What is loaded in the player
    property RecordingClip loadedClip: null
    property int segmentIndex: 0

    // Part to export, -1 = not set
    property real rangeStartMs: -1
    property real rangeEndMs: -1
    readonly property bool hasRange: rangeStartMs >= 0 && rangeEndMs > rangeStartMs

    readonly property int sourceBitrateMbps: loadedClip ? loadedClip.videoBitrateMbps(segmentIndex) : 0
    readonly property int maxBitrateMbps: sourceBitrateMbps > 0 ? sourceBitrateMbps : 200

    readonly property bool mediaReady: mediaPlayer.mediaStatus === MediaPlayer.LoadedMedia ||
                                       mediaPlayer.mediaStatus === MediaPlayer.BufferedMedia ||
                                       mediaPlayer.playbackState !== MediaPlayer.StoppedState

    function load(newClip) {
        if (!newClip || newClip === loadedClip) {
            return
        }
        mediaPlayer.stop()
        loadedClip = newClip
        segmentIndex = 0
        clearRange()
    }

    function clearRange() {
        rangeStartMs = -1
        rangeEndMs = -1
    }

    function setStart() {
        rangeStartMs = mediaPlayer.position
        if (rangeEndMs >= 0 && rangeEndMs <= rangeStartMs) {
            rangeEndMs = -1
        }
    }

    function setEnd() {
        rangeEndMs = mediaPlayer.position
        if (rangeStartMs < 0 || rangeStartMs >= rangeEndMs) {
            rangeStartMs = 0
        }
    }

    function togglePlayback() {
        if (mediaPlayer.playbackState === MediaPlayer.PlayingState) {
            mediaPlayer.pause()
        } else {
            mediaPlayer.play()
        }
    }

    function seekBy(ms) {
        if (mediaPlayer.seekable) {
            mediaPlayer.setPosition(Math.max(0, Math.min(mediaPlayer.duration, mediaPlayer.position + ms)))
        }
    }

    function openLatest() {
        if (!recordingManager) {
            return
        }
        var latest = recordingManager.latestBackgroundRecording()
        if (latest) {
            sourceTabs.currentIndex = 0
            load(latest)
        } else if (savedClipsModel.count > 0) {
            sourceTabs.currentIndex = 1
            load(recordingManager.getClip(0))
        }
    }

    function formatTime(milliseconds) {
        if (isNaN(milliseconds) || milliseconds < 0) {
            return "0:00"
        }
        var seconds = Math.floor(milliseconds / 1000)
        var hours = Math.floor(seconds / 3600)
        var minutes = Math.floor((seconds % 3600) / 60)
        seconds = seconds % 60
        var mm = hours > 0 && minutes < 10 ? "0" + minutes : "" + minutes
        var ss = seconds < 10 ? "0" + seconds : "" + seconds
        return (hours > 0 ? hours + ":" : "") + mm + ":" + ss
    }

    Connections {
        target: recordingManager

        function onScanCompleted() {
            // Open the newest recording on start, and when the loaded one disappeared
            if (!root.loadedClip || recordingManager.getClipIndex(root.loadedClip) < 0) {
                root.loadedClip = null
                root.openLatest()
            }
        }
    }

    Component.onCompleted: {
        if (recordingManager && !recordingManager.isScanning && recordingManager.hasClips) {
            openLatest()
        }
        askForUserIfNeeded()
    }

    // Several Steam accounts and none picked yet: let the user choose
    function askForUserIfNeeded() {
        // Only when no account could be picked automatically (none has recordings);
        // gameRecordingsPath is filled in later, so it can't be used to decide this
        if (recordingManager && recordingManager.hasMultipleUsers && !recordingManager.selectedUserId) {
            userSelectionDialog.open()
        }
    }

    Connections {
        target: recordingManager
        function onHasMultipleUsersChanged() { root.askForUserIfNeeded() }
    }

    // Keyboard: space play/pause, I/O set clip start/end, arrows seek
    Shortcut { sequence: "Space"; enabled: !exportPopup.opened; onActivated: root.togglePlayback() }
    Shortcut { sequence: "I"; enabled: !exportPopup.opened && root.mediaReady; onActivated: root.setStart() }
    Shortcut { sequence: "O"; enabled: !exportPopup.opened && root.mediaReady; onActivated: root.setEnd() }
    Shortcut { sequence: "Left"; enabled: !exportPopup.opened; onActivated: root.seekBy(-5000) }
    Shortcut { sequence: "Right"; enabled: !exportPopup.opened; onActivated: root.seekBy(5000) }

    header: ToolBar {
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12

            Column {
                Layout.fillWidth: true
                spacing: 2

                Label {
                    text: root.loadedClip ? (root.loadedClip.gameName || qsTr("Game ID: %1").arg(root.loadedClip.appId))
                                    : qsTr("Steam Game Recordings")
                    font.pixelSize: 16
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    width: parent.width
                }

                Label {
                    visible: root.loadedClip
                    text: root.loadedClip ? (root.loadedClip.isBackgroundRecording ? qsTr("Session") : qsTr("Clip"))
                                      + " • " + root.loadedClip.formattedDate : ""
                    font.pixelSize: 12
                    color: Material.hintTextColor
                }
            }

            ToolButton {
                icon.name: "folder-videos-symbolic"
                text: qsTr("Exported Videos")
                onClicked: Qt.openUrlExternally("file://" + videoExporter.defaultExportPath)
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Open the export folder")
            }

            ToolButton {
                icon.name: "system-switch-user"
                text: qsTr("Switch User")
                visible: recordingManager ? recordingManager.hasMultipleUsers : false
                enabled: recordingManager ? !recordingManager.isScanning : false
                onClicked: userSelectionDialog.open()
            }

            ToolButton {
                icon.name: "view-refresh"
                text: qsTr("Refresh")
                enabled: recordingManager ? !recordingManager.isScanning : false
                onClicked: recordingManager.refreshClips()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // Player with the timeline laid over its bottom edge
        Rectangle {
            id: playerArea
            Layout.fillWidth: true
            // As big as possible while leaving room for a few recordings below
            Layout.preferredHeight: Math.min(width * 9 / 16, root.height * 0.58)
            color: "black"
            radius: 4
            clip: true

            ThumbnailProvider {
                id: thumbnails
                segmentPath: root.loadedClip && root.segmentIndex < root.loadedClip.segments.length
                             ? root.loadedClip.segments[root.segmentIndex] : ""
            }

            MediaPlayer {
                id: mediaPlayer
                source: root.loadedClip ? root.loadedClip.getSegmentMpdUrl(root.segmentIndex) : ""
                videoOutput: videoOutput
                audioOutput: AudioOutput {
                    id: audioOutput
                }

                onErrorOccurred: function(error, errorString) {
                    playerError.text = qsTr("Preview Error: %1").arg(errorString)
                }
                onSourceChanged: playerError.text = ""
            }

            VideoOutput {
                id: videoOutput
                anchors.fill: parent
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.togglePlayback()
            }

            BusyIndicator {
                Material.accent: "#8ab4f8"
                anchors.centerIn: parent
                running: mediaPlayer.mediaStatus === MediaPlayer.LoadingMedia
                visible: running
            }

            Label {
                id: playerError
                anchors.centerIn: parent
                visible: text !== ""
                color: Material.color(Material.Red)
                wrapMode: Text.WordWrap
            }

            Label {
                anchors.centerIn: parent
                visible: !root.loadedClip && !(recordingManager && recordingManager.isScanning)
                text: qsTr("Pick a session or clip below")
                color: Material.hintTextColor
                font.pixelSize: 16
            }

            // Big play button while paused
            Rectangle {
                anchors.centerIn: parent
                width: 72
                height: 72
                radius: 36
                color: "#80000000"
                visible: root.loadedClip && mediaPlayer.playbackState !== MediaPlayer.PlayingState
                         && mediaPlayer.mediaStatus !== MediaPlayer.LoadingMedia && !playerError.visible

                Label {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: 3
                    text: "▶"
                    font.pixelSize: 30
                    color: "white"
                }
            }

            // Shade so the timeline stays readable on bright footage
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 84
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#00000000" }
                    GradientStop { position: 1.0; color: "#b0000000" }
                }
            }

            // Timeline: playhead, clip start/end ticks and the selected range
            Item {
                id: timeline
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.bottomMargin: 10
                height: 28
                enabled: root.mediaReady && mediaPlayer.duration > 0

                readonly property real duration: Math.max(1, mediaPlayer.duration)
                property real dragPosition: -1
                readonly property real shownPosition: dragPosition >= 0 ? dragPosition : mediaPlayer.position

                function xFor(ms) {
                    return Math.max(0, Math.min(width, ms / duration * width))
                }

                // Labeled marks every N seconds, N picked so labels stay ~90px apart
                readonly property real tickIntervalMs: {
                    var steps = [5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200]
                    var maxTicks = Math.max(1, Math.floor(width / 90))
                    for (var i = 0; i < steps.length; ++i) {
                        if (duration / (steps[i] * 1000) <= maxTicks) {
                            return steps[i] * 1000
                        }
                    }
                    return steps[steps.length - 1] * 1000
                }

                // Mouse position over the timeline in ms, -1 when not hovering
                property real hoverPosition: -1

                Repeater {
                    model: timeline.enabled ? Math.floor((timeline.duration - 1) / timeline.tickIntervalMs) : 0

                    Item {
                        readonly property real ms: (index + 1) * timeline.tickIntervalMs
                        x: timeline.xFor(ms)
                        y: 0
                        height: timeline.height

                        Rectangle {
                            anchors.horizontalCenter: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 1
                            height: 10
                            color: "#90ffffff"
                        }

                        Label {
                            anchors.horizontalCenter: parent.left
                            anchors.bottom: parent.top
                            anchors.bottomMargin: -2
                            text: root.formatTime(parent.ms)
                            font.pixelSize: 10
                            font.features: { "tnum": 1 }
                            color: "#c0ffffff"
                        }
                    }
                }

                Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    color: "#60ffffff"
                }

                // Played part
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: timeline.xFor(timeline.shownPosition)
                    height: 4
                    radius: 2
                    color: "#b0ffffff"
                }

                // Selected clip range
                Rectangle {
                    visible: root.hasRange
                    anchors.verticalCenter: parent.verticalCenter
                    x: timeline.xFor(root.rangeStartMs)
                    width: timeline.xFor(root.rangeEndMs) - x
                    height: 8
                    radius: 2
                    color: "#e0ffffff"
                }

                Repeater {
                    model: [root.rangeStartMs, root.rangeEndMs]
                    Rectangle {
                        visible: modelData >= 0
                        x: timeline.xFor(modelData) - width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: 22
                        radius: 1
                        color: "white"
                    }
                }

                // Playhead
                Rectangle {
                    x: timeline.xFor(timeline.shownPosition) - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    radius: 8
                    color: "white"
                    border.color: "#40000000"
                }

                // Preview frame and time under the mouse, so long recordings can be searched by hovering
                Rectangle {
                    visible: timeline.hoverPosition >= 0
                    x: Math.max(-16, Math.min(timeline.width + 16 - width,
                                              timeline.xFor(timeline.hoverPosition) - width / 2))
                    y: -height - 18
                    width: 240 + 6
                    height: hoverColumn.implicitHeight + 6
                    radius: 4
                    color: "#e0000000"
                    border.color: "#60ffffff"

                    Column {
                        id: hoverColumn
                        anchors.centerIn: parent
                        spacing: 3

                        Rectangle {
                            width: 240
                            height: 135
                            color: "#2a2a30"

                            Image {
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                // revision: re-query when new thumbnails come in
                                source: thumbnails.revision >= 0 && timeline.hoverPosition >= 0
                                        ? thumbnails.thumbnailAt(timeline.hoverPosition) : ""
                            }
                        }

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.formatTime(timeline.hoverPosition)
                            font.pixelSize: 12
                            font.features: { "tnum": 1 }
                            color: "white"
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.topMargin: -6
                    anchors.bottomMargin: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    function msAt(mouseX) {
                        return Math.max(0, Math.min(1, mouseX / width)) * timeline.duration
                    }

                    onExited: timeline.hoverPosition = -1
                    onPressed: function(mouse) {
                        timeline.dragPosition = msAt(mouse.x)
                        timeline.hoverPosition = timeline.dragPosition
                    }
                    onPositionChanged: function(mouse) {
                        timeline.hoverPosition = msAt(mouse.x)
                        if (pressed) {
                            timeline.dragPosition = msAt(mouse.x)
                        }
                    }
                    onReleased: function(mouse) {
                        if (mediaPlayer.seekable) {
                            mediaPlayer.setPosition(msAt(mouse.x))
                        }
                        timeline.dragPosition = -1
                        if (!containsMouse) {
                            timeline.hoverPosition = -1
                        }
                    }
                }
            }
        }

        // Editor bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: editorRow.implicitHeight + 12
            color: "#2a2a30"
            radius: 4

            RowLayout {
                id: editorRow
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 6

                ToolButton {
                    icon.name: mediaPlayer.playbackState === MediaPlayer.PlayingState ? "media-playback-pause" : "media-playback-start"
                    enabled: root.loadedClip !== null
                    onClicked: root.togglePlayback()
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Play/Pause (Space)")
                }

                Label {
                    text: root.formatTime(timeline.shownPosition) + " / " + root.formatTime(mediaPlayer.duration)
                    font.pixelSize: 12
                    font.features: { "tnum": 1 }
                    Layout.minimumWidth: 110
                }

                ToolSeparator {}

                Button {
                    text: qsTr("Start Clip")
                    flat: true
                    enabled: root.mediaReady
                    onClicked: root.setStart()
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Start the clip at the current position (I)")
                }

                Button {
                    text: qsTr("End Clip")
                    flat: true
                    enabled: root.mediaReady
                    onClicked: root.setEnd()
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("End the clip at the current position (O)")
                }

                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: 12
                    color: root.hasRange ? Material.foreground : Material.hintTextColor
                    text: root.hasRange
                          ? qsTr("Clip %1 – %2 (%3)").arg(root.formatTime(root.rangeStartMs))
                                                      .arg(root.formatTime(root.rangeEndMs))
                                                      .arg(root.formatTime(root.rangeEndMs - root.rangeStartMs))
                          : root.rangeStartMs >= 0
                            ? qsTr("Clip starts at %1, now set the end").arg(root.formatTime(root.rangeStartMs))
                            : qsTr("No clip set, export takes the whole recording")
                }

                ToolButton {
                    icon.name: "media-playlist-repeat"
                    visible: root.hasRange
                    onClicked: {
                        mediaPlayer.setPosition(root.rangeStartMs)
                        mediaPlayer.play()
                    }
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Play the clip from its start")
                }

                ToolButton {
                    icon.name: "edit-clear"
                    visible: root.rangeStartMs >= 0 || root.rangeEndMs >= 0
                    onClicked: root.clearRange()
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Clear clip")
                }

                ComboBox {
                    // Saved clips can consist of several recording segments
                    visible: root.loadedClip && root.loadedClip.segmentCount > 1
                    model: root.loadedClip ? root.loadedClip.segmentCount : 0
                    displayText: qsTr("Segment %1").arg(currentIndex + 1)
                    currentIndex: root.segmentIndex
                    onActivated: function(index) {
                        root.segmentIndex = index
                        root.clearRange()
                    }
                }

                ToolSeparator {}

                ToolButton {
                    icon.name: audioOutput.muted ? "audio-volume-muted" : "audio-volume-high"
                    onClicked: audioOutput.muted = !audioOutput.muted
                }

                Slider {
                    Material.accent: "#8ab4f8"
                    Layout.preferredWidth: 90
                    from: 0
                    to: 1
                    value: audioOutput.volume
                    onMoved: audioOutput.volume = value
                }

                Button {
                    text: root.hasRange ? qsTr("Export Clip…") : qsTr("Export…")
                    highlighted: true
                    enabled: root.loadedClip !== null
                    onClicked: exportPopup.open()
                }
            }
        }

        // Source recordings
        TabBar {
            Material.accent: "#8ab4f8"
            id: sourceTabs
            Layout.fillWidth: true
            Layout.topMargin: 4

            TabButton { text: qsTr("Sessions (%1)").arg(backgroundRecordingsModel.count) }
            TabButton { text: qsTr("Clips (%1)").arg(savedClipsModel.count) }
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

        ListView {
            id: sourceList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            model: sourceTabs.currentIndex === 0 ? backgroundRecordingsModel : savedClipsModel
            ScrollBar.vertical: ScrollBar {}

            delegate: ItemDelegate {
                id: row
                width: sourceList.width
                height: 56
                highlighted: model.clip === root.loadedClip
                onClicked: root.load(model.clip)

                background: Rectangle {
                    radius: 4
                    color: row.highlighted ? "#1a3d6e" : (row.hovered ? "#2a2a2a" : "transparent")
                    border.color: Material.dividerColor
                    border.width: 1
                }

                contentItem: RowLayout {
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 72
                        Layout.preferredHeight: 40
                        color: "#2a2a30"
                        radius: 2
                        clip: true

                        Image {
                            id: rowThumbnail
                            anchors.fill: parent
                            source: model.clip && model.clip.thumbnailPath ? "file:///" + model.clip.thumbnailPath : ""
                            fillMode: Image.PreserveAspectCrop
                            visible: status === Image.Ready
                        }

                        Label {
                            anchors.centerIn: parent
                            visible: !rowThumbnail.visible
                            text: "🎬"
                            color: Material.hintTextColor
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        spacing: 2

                        Label {
                            width: parent.width
                            elide: Text.ElideRight
                            font.weight: Font.Medium
                            text: model.clip ? (model.clip.gameName || qsTr("Game ID: %1").arg(model.clip.appId)) : ""
                        }

                        Label {
                            text: model.clip ? model.clip.formattedDate : ""
                            font.pixelSize: 12
                            color: Material.hintTextColor
                        }
                    }

                    Label {
                        text: model.clip ? model.clip.formattedDuration : ""
                        font.pixelSize: 12
                        font.features: { "tnum": 1 }
                    }

                    Label {
                        Layout.preferredWidth: 80
                        horizontalAlignment: Text.AlignRight
                        text: model.clip ? model.clip.formattedSize : ""
                        font.pixelSize: 12
                        color: Material.hintTextColor
                    }
                }
            }

            Label {
                anchors.centerIn: parent
                visible: sourceList.count === 0
                horizontalAlignment: Text.AlignHCenter
                color: Material.hintTextColor
                text: recordingManager && (recordingManager.isScanning || recordingManager.gameRecordingsPath === "")
                      ? qsTr("Looking for recordings…")
                      : sourceTabs.currentIndex === 0
                        ? qsTr("No sessions found.\nTurn on background recording in Steam's Game Recording settings.")
                        : qsTr("No clips saved in Steam yet.")
            }
        }
    }

    // Export options, shown in the window over a dimmed background
    Popup {
        id: exportPopup
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(600, root.width - 48)
        modal: true
        dim: true
        padding: 20
        closePolicy: videoExporter && videoExporter.isExporting ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside

        property string completedPath: ""
        property string failure: ""

        onAboutToShow: {
            mediaPlayer.pause()
            completedPath = ""
            failure = ""
            fileNameField.text = suggestedFileName()
            if (videoExporter) {
                videoExporter.clearLog()
            }
        }

        function suggestedFileName() {
            if (!videoExporter || !root.loadedClip) {
                return "recording.mp4"
            }
            var name = videoExporter.generateOutputFilename(root.loadedClip, root.segmentIndex)
            if (root.hasRange) {
                // Keep exports of different parts of one recording apart
                name = name.replace(/\.mp4$/, "") + "_at_" + root.formatTime(root.rangeStartMs).replace(/:/g, "-") + ".mp4"
            }
            return name
        }

        Connections {
            target: videoExporter
            function onExportCompleted(outputPath) { exportPopup.completedPath = outputPath }
            function onExportFailed(error) { exportPopup.failure = error }
        }

        contentItem: ColumnLayout {
            spacing: 14

            Label {
                text: root.hasRange
                      ? qsTr("Export clip (%1)").arg(root.formatTime(root.rangeEndMs - root.rangeStartMs))
                      : qsTr("Export whole recording (%1)").arg(root.formatTime(mediaPlayer.duration))
                font.pixelSize: 18
                font.weight: Font.Medium
            }

            // Options
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 12
                rowSpacing: 8
                enabled: !(videoExporter && videoExporter.isExporting)

                Label { text: qsTr("File name") }
                TextField {
                    id: fileNameField
                    Layout.fillWidth: true
                    selectByMouse: true
                }

                Item { Layout.preferredWidth: 1 }
                Label {
                    Layout.fillWidth: true
                    text: videoExporter ? qsTr("Saved to %1").arg(videoExporter.defaultExportPath) : ""
                    font.pixelSize: 11
                    color: Material.hintTextColor
                    elide: Text.ElideMiddle
                }

                Label { text: qsTr("Format") }
                ComboBox {
                    id: codecCombo
                    Layout.fillWidth: true
                    textRole: "text"
                    valueRole: "value"
                    model: {
                        var options = [
                            { value: VideoExporter.CopyStream, text: qsTr("Original (no re-encoding, fastest)") }
                        ]
                        if (videoExporter && videoExporter.hardwareEncodingSupported) {
                            options.push({ value: VideoExporter.H264Hardware, text: qsTr("H.264, GPU encoding (VAAPI)") })
                        }
                        options.push({ value: VideoExporter.H264Software, text: qsTr("H.264, CPU encoding (slow)") })
                        return options
                    }
                    Component.onCompleted: currentIndex = indexOfValue(videoExporter.videoCodec)
                    onActivated: videoExporter.videoCodec = currentValue
                }

                Label {
                    text: qsTr("Bitrate (Mbps)")
                    visible: bitrateBox.visible
                }
                RowLayout {
                    visible: bitrateBox.visible

                    SpinBox {
                        id: bitrateBox
                        visible: videoExporter && videoExporter.videoCodec !== VideoExporter.CopyStream
                        from: 1
                        to: root.maxBitrateMbps
                        editable: true
                        value: videoExporter ? Math.min(videoExporter.videoBitrateMbps, root.maxBitrateMbps) : 30
                        onValueModified: videoExporter.videoBitrateMbps = value
                    }

                    Label {
                        visible: root.sourceBitrateMbps > 0
                        text: qsTr("max %1, the recording's own bitrate").arg(root.sourceBitrateMbps)
                        font.pixelSize: 11
                        color: Material.hintTextColor
                    }
                }
            }

            // Progress
            ColumnLayout {
                Layout.fillWidth: true
                visible: videoExporter && videoExporter.isExporting
                spacing: 4

                ProgressBar {
                    Material.accent: "#8ab4f8"
                    Layout.fillWidth: true
                    value: videoExporter ? videoExporter.progress / 100.0 : 0
                }

                Label {
                    text: videoExporter ? qsTr("Exporting… %1%").arg(videoExporter.progress) : ""
                    font.pixelSize: 12
                    color: Material.hintTextColor
                }
            }

            Label {
                Layout.fillWidth: true
                visible: exportPopup.completedPath !== "" && !(videoExporter && videoExporter.isExporting)
                text: qsTr("Saved: %1").arg(exportPopup.completedPath.split("/").pop())
                wrapMode: Text.WrapAnywhere
            }

            Label {
                Layout.fillWidth: true
                visible: exportPopup.failure !== ""
                text: qsTr("Export failed: %1").arg(exportPopup.failure)
                color: Material.color(Material.Red)
                wrapMode: Text.WordWrap
            }

            // Buttons
            RowLayout {
                Layout.fillWidth: true

                Button {
                    text: qsTr("Open Folder")
                    flat: true
                    visible: exportPopup.completedPath !== "" && !(videoExporter && videoExporter.isExporting)
                    onClicked: videoExporter.openExportLocation(exportPopup.completedPath)
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: videoExporter && videoExporter.isExporting ? qsTr("Cancel Export")
                          : exportPopup.completedPath !== "" ? qsTr("Close") : qsTr("Cancel")
                    flat: true
                    onClicked: {
                        if (videoExporter && videoExporter.isExporting) {
                            videoExporter.cancelExport()
                        } else {
                            exportPopup.close()
                        }
                    }
                }

                Button {
                    text: qsTr("Export")
                    highlighted: true
                    visible: !(videoExporter && videoExporter.isExporting)
                    enabled: root.loadedClip !== null && fileNameField.text.trim() !== ""
                    onClicked: {
                        exportPopup.completedPath = ""
                        exportPopup.failure = ""
                        var outputPath = videoExporter.defaultExportPath + "/" + fileNameField.text.trim()
                        if (root.hasRange) {
                            videoExporter.exportClipRange(root.loadedClip, root.segmentIndex,
                                                          root.rangeStartMs, root.rangeEndMs, outputPath)
                        } else {
                            videoExporter.exportClipSegment(root.loadedClip, root.segmentIndex, outputPath)
                        }
                    }
                }
            }
        }
    }

    SteamUserSelectionDialog {
        id: userSelectionDialog

        onUserSelected: function(userId) {
            recordingManager.selectedUserId = userId
            recordingManager.refreshClips()
        }
    }
}
