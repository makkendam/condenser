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

    function seekTo(ms) {
        if (!mediaPlayer.seekable) {
            return
        }
        if (mediaPlayer.playbackState === MediaPlayer.StoppedState) {
            mediaPlayer.pause() // Stopped shows no frame; paused shows the one we seek to
        }
        mediaPlayer.setPosition(Math.max(0, Math.min(mediaPlayer.duration, ms)))
    }

    function seekBy(ms) {
        seekTo(mediaPlayer.position + ms)
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
    Shortcut { sequence: "Left"; enabled: !exportPopup.opened; onActivated: root.seekBy(-1000) }
    Shortcut { sequence: "Right"; enabled: !exportPopup.opened; onActivated: root.seekBy(1000) }
    Shortcut { sequence: "Shift+Left"; enabled: !exportPopup.opened; onActivated: root.seekBy(-10000) }
    Shortcut { sequence: "Shift+Right"; enabled: !exportPopup.opened; onActivated: root.seekBy(10000) }

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
                onMediaStatusChanged: {
                    // A stopped player shows nothing and ignores seeks; paused shows the
                    // current frame, so the first frame appears and timeline clicks work
                    if (mediaStatus === MediaPlayer.LoadedMedia && playbackState === MediaPlayer.StoppedState) {
                        pause()
                    }
                }
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
                height: timeline.zoomed ? 104 : 84
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
                property bool markerDragging: false

                // Zoom: the timeline shows viewStart .. viewEnd of the recording.
                // Scroll on it to zoom around the mouse, down to a minute wide.
                readonly property real minSpanMs: Math.min(duration, 60000)
                property real viewSpan: duration
                property real viewStart: 0
                readonly property real span: Math.max(minSpanMs, Math.min(duration, viewSpan))
                readonly property real viewEnd: viewStart + span
                readonly property bool zoomed: span < duration - 1

                function xFor(ms) {
                    return Math.max(0, Math.min(width, (ms - viewStart) / span * width))
                }

                function msAtX(x) {
                    return viewStart + Math.max(0, Math.min(1, x / width)) * span
                }

                function inView(ms) {
                    return ms >= viewStart && ms <= viewEnd
                }

                function setView(start, newSpan) {
                    newSpan = Math.max(minSpanMs, Math.min(duration, newSpan))
                    viewSpan = newSpan
                    viewStart = Math.max(0, Math.min(duration - newSpan, start))
                }

                function zoomAt(x, factor) {
                    var anchorMs = msAtX(x)
                    var newSpan = Math.max(minSpanMs, Math.min(duration, span * factor))
                    setView(anchorMs - x / width * newSpan, newSpan)
                }

                Connections {
                    target: mediaPlayer
                    function onDurationChanged() { timeline.setView(0, timeline.duration) }
                    // Page along when playback or a seek leaves the visible part
                    function onPositionChanged() {
                        if (!timeline.zoomed || timeline.dragPosition >= 0 || timeline.markerDragging) {
                            return
                        }
                        var position = mediaPlayer.position
                        if (position < timeline.viewStart || position > timeline.viewEnd) {
                            timeline.setView(position - timeline.span * 0.1, timeline.span)
                        }
                    }
                }

                // Labeled marks every N seconds, N picked so labels stay ~90px apart
                readonly property real tickIntervalMs: {
                    var steps = [5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200]
                    var maxTicks = Math.max(1, Math.floor(width / 90))
                    for (var i = 0; i < steps.length; ++i) {
                        if (span / (steps[i] * 1000) <= maxTicks) {
                            return steps[i] * 1000
                        }
                    }
                    return steps[steps.length - 1] * 1000
                }

                function isFrozenAt(ms) {
                    var ranges = thumbnails.frozenRanges
                    for (var i = 0; i < ranges.length; ++i) {
                        if (ms >= ranges[i].startMs && ms < ranges[i].endMs) {
                            return true
                        }
                    }
                    return false
                }

                // Mouse position over the timeline in ms, -1 when not hovering
                property real hoverPosition: -1

                // Only the marks in view; 0 and the very end get none
                readonly property int firstTick: Math.max(1, Math.ceil(viewStart / tickIntervalMs))
                readonly property int lastTick: Math.floor(Math.min(viewEnd, duration - 1) / tickIntervalMs)

                Repeater {
                    model: timeline.enabled ? Math.max(0, timeline.lastTick - timeline.firstTick + 1) : 0

                    Item {
                        readonly property real ms: (timeline.firstTick + index) * timeline.tickIntervalMs
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

                // Stretches where the game wasn't sending frames: audio only
                Repeater {
                    model: timeline.enabled ? thumbnails.frozenRanges : []
                    Rectangle {
                        visible: modelData.endMs > timeline.viewStart && modelData.startMs < timeline.viewEnd
                        anchors.verticalCenter: parent.verticalCenter
                        x: timeline.xFor(modelData.startMs)
                        width: Math.max(2, timeline.xFor(modelData.endMs) - x)
                        height: 6
                        radius: 2
                        color: "#5a5a64"
                    }
                }

                // Selected clip range
                Rectangle {
                    visible: root.hasRange && root.rangeEndMs > timeline.viewStart && root.rangeStartMs < timeline.viewEnd
                    anchors.verticalCenter: parent.verticalCenter
                    x: timeline.xFor(root.rangeStartMs)
                    width: timeline.xFor(root.rangeEndMs) - x
                    height: 8
                    radius: 2
                    color: "#e0ffffff"
                }

                // Clip start (index 0) and end (index 1); drag them to adjust the clip
                Repeater {
                    model: 2
                    Rectangle {
                        id: marker
                        readonly property real ms: index === 0 ? root.rangeStartMs : root.rangeEndMs
                        visible: ms >= 0 && timeline.inView(ms)
                        x: timeline.xFor(ms) - width / 2
                        z: 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: markerArea.containsMouse || markerArea.pressed ? 5 : 3
                        height: 22
                        radius: 1
                        color: "white"

                        MouseArea {
                            id: markerArea
                            anchors.centerIn: parent
                            width: 16
                            height: 32
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: Qt.SizeHorCursor

                            onPressed: timeline.markerDragging = true
                            onPositionChanged: function(mouse) {
                                if (!pressed) {
                                    return
                                }
                                var ms = timeline.msAtX(mapToItem(timeline, mouse.x, 0).x)
                                if (index === 0) {
                                    root.rangeStartMs = root.rangeEndMs >= 0 ? Math.min(ms, root.rangeEndMs - 500) : ms
                                } else {
                                    root.rangeEndMs = Math.max(ms, root.rangeStartMs + 500)
                                }
                                // Preview frame of where the marker is going
                                timeline.hoverPosition = marker.ms
                            }
                            onReleased: {
                                timeline.markerDragging = false
                                timeline.hoverPosition = -1
                                root.seekTo(marker.ms)
                            }
                        }
                    }
                }

                // Playhead
                Rectangle {
                    visible: timeline.inView(timeline.shownPosition)
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
                    y: -height - (timeline.zoomed ? 34 : 18)
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
                            visible: timeline.isFrozenAt(timeline.hoverPosition)
                            text: qsTr("Frozen picture (game in background)")
                            font.pixelSize: 11
                            color: "#c0ffffff"
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
                        return timeline.msAtX(mouseX)
                    }

                    onWheel: function(wheel) {
                        var steps = wheel.angleDelta.y / 120
                        if (steps !== 0) {
                            timeline.zoomAt(wheel.x, Math.pow(0.8, steps))
                            timeline.hoverPosition = msAt(wheel.x)
                        }
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
                        root.seekTo(msAt(mouse.x))
                        timeline.dragPosition = -1
                        if (!containsMouse) {
                            timeline.hoverPosition = -1
                        }
                    }
                }

                // Overview of the whole recording while zoomed in: the visible
                // part is highlighted; click or drag to move it
                Item {
                    id: overview
                    visible: timeline.zoomed
                    anchors.left: parent.left
                    anchors.right: parent.right
                    y: -28
                    height: 6

                    function xFor(ms) {
                        return Math.max(0, Math.min(width, ms / timeline.duration * width))
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 3
                        color: "#40ffffff"
                    }

                    Repeater {
                        model: overview.visible ? thumbnails.frozenRanges : []
                        Rectangle {
                            x: overview.xFor(modelData.startMs)
                            width: Math.max(1, overview.xFor(modelData.endMs) - x)
                            height: parent.height
                            color: "#5a5a64"
                        }
                    }

                    Rectangle {
                        visible: root.hasRange
                        x: overview.xFor(root.rangeStartMs)
                        width: Math.max(2, overview.xFor(root.rangeEndMs) - x)
                        height: parent.height
                        color: "#e0ffffff"
                    }

                    // Visible part
                    Rectangle {
                        x: overview.xFor(timeline.viewStart)
                        width: Math.max(4, overview.xFor(timeline.viewEnd) - x)
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height + 4
                        radius: 3
                        color: "transparent"
                        border.color: "#8ab4f8"
                        border.width: 2
                    }

                    Rectangle {
                        x: overview.xFor(mediaPlayer.position) - 1
                        width: 2
                        height: parent.height
                        color: "white"
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.topMargin: -6
                        anchors.bottomMargin: -6
                        cursorShape: Qt.PointingHandCursor
                        preventStealing: true

                        function centerOn(mouseX) {
                            var ms = Math.max(0, Math.min(1, mouseX / width)) * timeline.duration
                            timeline.setView(ms - timeline.span / 2, timeline.span)
                        }
                        onPressed: function(mouse) { centerOn(mouse.x) }
                        onPositionChanged: function(mouse) { if (pressed) centerOn(mouse.x) }
                        onWheel: function(wheel) {
                            var steps = wheel.angleDelta.y / 120
                            if (steps !== 0) {
                                timeline.zoomAt(timeline.xFor(timeline.viewStart + timeline.span / 2), Math.pow(0.8, steps))
                            }
                        }
                    }
                }
            }
        }

        // Editor bar: clip controls left, transport centered under the
        // timeline like Steam's player, volume and export right
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(transport.implicitHeight, clipRow.implicitHeight, outputRow.implicitHeight) + 8
            color: "#2a2a30"
            radius: 4

            RowLayout {
                id: clipRow
                anchors.left: parent.left
                anchors.leftMargin: 8
                // Line up with the transport buttons rather than the bar, as the time sits below them
                y: transport.y + transportButtons.y + (transportButtons.height - height) / 2
                width: transport.x - 16 - anchors.leftMargin
                spacing: 6

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

                Item { Layout.fillWidth: true }
            }

            // Clip info under the clip buttons, level with the time under the transport
            Label {
                x: clipRow.x + 8
                y: transport.y + transportTime.y
                width: clipRow.width - 8
                elide: Text.ElideRight
                font.pixelSize: 12
                font.features: { "tnum": 1 }
                color: Material.hintTextColor
                text: root.hasRange
                      ? qsTr("Clip %1 – %2 (%3)").arg(root.formatTime(root.rangeStartMs))
                                                  .arg(root.formatTime(root.rangeEndMs))
                                                  .arg(root.formatTime(root.rangeEndMs - root.rangeStartMs))
                      : root.rangeStartMs >= 0
                        ? qsTr("Clip starts at %1, now set the end").arg(root.formatTime(root.rangeStartMs))
                        : qsTr("No clip set, export takes the whole recording")
            }

            ColumnLayout {
                id: transport
                anchors.centerIn: parent
                spacing: -6

                RowLayout {
                    id: transportButtons
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 2

                    ToolButton {
                        icon.source: "qrc:/qml/icons/back-1.svg"
                        icon.width: 22; icon.height: 22
                        enabled: root.mediaReady
                        onClicked: root.seekBy(-1000)
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Back 1 second (Left)")
                    }
                    ToolButton {
                        icon.source: "qrc:/qml/icons/back-10.svg"
                        icon.width: 28; icon.height: 28
                        enabled: root.mediaReady
                        onClicked: root.seekBy(-10000)
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Back 10 seconds (Shift+Left)")
                    }
                    ToolButton {
                        icon.source: mediaPlayer.playbackState === MediaPlayer.PlayingState
                                     ? "qrc:/qml/icons/pause.svg" : "qrc:/qml/icons/play.svg"
                        icon.width: 38; icon.height: 38
                        enabled: root.loadedClip !== null
                        onClicked: root.togglePlayback()
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Play/Pause (Space)")
                    }
                    ToolButton {
                        icon.source: "qrc:/qml/icons/forward-10.svg"
                        icon.width: 28; icon.height: 28
                        enabled: root.mediaReady
                        onClicked: root.seekBy(10000)
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Forward 10 seconds (Shift+Right)")
                    }
                    ToolButton {
                        icon.source: "qrc:/qml/icons/forward-1.svg"
                        icon.width: 22; icon.height: 22
                        enabled: root.mediaReady
                        onClicked: root.seekBy(1000)
                        ToolTip.visible: hovered
                        ToolTip.text: qsTr("Forward 1 second (Right)")
                    }
                }

                Label {
                    id: transportTime
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 4
                    text: root.formatTime(timeline.shownPosition) + " / " + root.formatTime(mediaPlayer.duration)
                    font.pixelSize: 12
                    font.features: { "tnum": 1 }
                    color: Material.hintTextColor
                }
            }

            RowLayout {
                id: outputRow
                anchors.right: parent.right
                anchors.rightMargin: 8
                // Line up with the transport buttons rather than the bar, as the time sits below them
                y: transport.y + transportButtons.y + (transportButtons.height - height) / 2
                spacing: 6

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

        readonly property bool reencoding: codecCombo.currentValue !== VideoExporter.CopyStream
        readonly property real exportDurationMs: root.hasRange ? root.rangeEndMs - root.rangeStartMs
                                                               : mediaPlayer.duration
        // Video bitrate plus roughly 0.2 Mbps of audio
        readonly property real estimatedBytes: {
            var mbps = reencoding ? bitrateSlider.value : root.sourceBitrateMbps
            return (mbps + 0.2) * 1000000 / 8 * exportDurationMs / 1000
        }

        function formatSize(bytes) {
            if (bytes >= 1e9) {
                return qsTr("%1 GB").arg((bytes / 1e9).toFixed(1))
            }
            return qsTr("%1 MB").arg(Math.max(1, Math.round(bytes / 1e6)))
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
                    Material.accent: "#8ab4f8"
                    Layout.fillWidth: true
                    textRole: "text"
                    valueRole: "value"
                    model: {
                        var source = root.loadedClip ? root.loadedClip.videoCodecName(root.segmentIndex) : ""
                        var options = [
                            { value: VideoExporter.CopyStream,
                              text: source ? qsTr("Original %1 (no re-encoding, fastest)").arg(source)
                                           : qsTr("Original (no re-encoding, fastest)") }
                        ]
                        if (videoExporter && videoExporter.hardwareEncodingSupported) {
                            options.push({ value: VideoExporter.H264Hardware, text: qsTr("H.264, GPU encoding (plays everywhere)") })
                            options.push({ value: VideoExporter.HevcHardware, text: qsTr("HEVC, GPU encoding (smaller)") })
                            options.push({ value: VideoExporter.Av1Hardware, text: qsTr("AV1, GPU encoding (smallest)") })
                        }
                        options.push({ value: VideoExporter.H264Software, text: qsTr("H.264, CPU encoding (slow)") })
                        return options
                    }
                    Component.onCompleted: currentIndex = indexOfValue(videoExporter.videoCodec)
                    // A new recording rebuilds the list (codec name); keep the chosen format
                    onModelChanged: currentIndex = Math.max(0, indexOfValue(videoExporter.videoCodec))
                    onActivated: videoExporter.videoCodec = currentValue
                }

                Label { text: qsTr("Bitrate") }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    // Copying keeps the recording's own bitrate
                    Label {
                        visible: !exportPopup.reencoding
                        text: root.sourceBitrateMbps > 0
                              ? qsTr("%1 Mbps, same as the recording").arg(root.sourceBitrateMbps)
                              : qsTr("Same as the recording")
                    }

                    RowLayout {
                        visible: exportPopup.reencoding
                        Layout.fillWidth: true

                        Slider {
                            id: bitrateSlider
                            Material.accent: "#8ab4f8"
                            Layout.fillWidth: true
                            from: 2
                            to: root.maxBitrateMbps
                            stepSize: 1
                            snapMode: Slider.SnapAlways
                            value: videoExporter ? Math.min(videoExporter.videoBitrateMbps, root.maxBitrateMbps) : 12
                            onMoved: videoExporter.videoBitrateMbps = value
                        }
                        Label {
                            Layout.preferredWidth: 64
                            horizontalAlignment: Text.AlignRight
                            text: qsTr("%1 Mbps").arg(bitrateSlider.value)
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: 11
                        color: Material.hintTextColor
                        text: {
                            var size = qsTr("Up to about %1").arg(exportPopup.formatSize(exportPopup.estimatedBytes))
                            if (!exportPopup.reencoding) {
                                if (root.sourceBitrateMbps <= 0) {
                                    return ""
                                }
                                return size
                            }
                            var hint = codecCombo.currentValue === VideoExporter.H264Hardware
                                       || codecCombo.currentValue === VideoExporter.H264Software
                                       ? qsTr("H.264 needs about 20 Mbps to look like the original.")
                                       : qsTr("12 Mbps looks like the original, 6–8 Mbps is fine for sharing.")
                            return size + " · " + hint
                        }
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
