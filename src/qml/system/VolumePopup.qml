/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/* The volume popup (haptics-sounds-15), as stock's VolumeActivity (sound_volume_activity.xml): when
 * the volume changes from outside (the phone, an app, the assistant) a screen shows the stream's
 * name as its header ("Media volume", "In-call volume") with an inline slider, and closes 3 s after
 * the last change. The watch has no volume keys; lipstick's VolumeControl (the `volumeControl`
 * context object) tells of every change. A change made on the quick settings' own slider shows
 * no popup (`suppressed`: the panel is the UI then), and the first value after start is not a change.
 * The slider can be dragged: that sets the volume and keeps the popup up. Nothing runs while it is
 * hidden but the signal connection. */
Item {
    id: popup
    objectName: "volumePopup"
    anchors.fill: parent

    /* the quick settings panel (its slider) is on screen */
    property bool suppressed: false
    /* asked at each change (the panel is not a property that can be bound before it exists) */
    property var suppressedCheck: function () { return false }
    /* the volume control object (a test replaces it) */
    property QtObject control: typeof volumeControl !== "undefined" ? volumeControl : null

    readonly property bool shown: dialog.shown
    readonly property alias dialog: dialog
    readonly property alias closeTimer: closeTimer
    readonly property alias track: track
    // 0..100
    property int percent: 0
    // the 3 s of stock after the last change (VolumeActivity.java:32-33)
    readonly property int closeMs: 3000
    property int shows: 0
    property bool _seen: false

    readonly property int _maximum: control && control.maximumVolume ? control.maximumVolume : 0
    readonly property int _current: control ? control.volume : 0
    readonly property bool inCall: control ? control.callActive === true : false

    on_CurrentChanged: popup.changed()
    on_MaximumChanged: popup.changed()

    function percentOf(v, max) { return max > 0 ? Math.max(0, Math.min(100, Math.round(v / max * 100))) : 0 }

    function changed() {
        var p = percentOf(_current, _maximum)
        if (!_seen) {
            // the first value after start is the volume, not a change
            if (_maximum > 0) {
                _seen = true
                percent = p
            }
            return
        }
        if (p === percent)
            return
        percent = p
        if (suppressed || suppressedCheck())
            return
        show()
    }

    function show() {
        shows++
        closeTimer.restart()
        dialog.open()
    }
    function close() { dialog.close() }

    // the slider's drag: the volume follows, the popup stays up 3 s more
    function setPercent(p) {
        var v = Math.max(0, Math.min(100, Math.round(p)))
        percent = v
        if (control && _maximum > 0)
            control.volume = Math.round(v / 100 * _maximum)
        closeTimer.restart()
    }

    Timer {
        id: closeTimer
        interval: popup.closeMs
        onTriggered: dialog.close()
    }

    Dialog {
        id: dialog
        objectName: "volumeDialog"
        onClosed: closeTimer.stop()

        // the stream's name as the header
        Label {
            id: header
            objectName: "volumeHeader"
            x: popup.width * 0.1
            width: popup.width * 0.8
            y: Math.ceil(popup.height * 0.22)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            role: "titleMedium"
            color: Theme.color.onBackground
            text: popup.inCall
                  //% "In-call volume"
                  ? qsTrId("id-volume-call") + localeManager.changesObserver
                  //% "Media volume"
                  : qsTrId("id-volume-media") + localeManager.changesObserver
        }

        // the inline slider: a pill, filled up to the volume
        Item {
            id: slider
            objectName: "volumeSlider"
            x: popup.width * 0.1
            width: popup.width * 0.8
            height: Theme.dp(40)
            y: Math.round(popup.height * 0.5 - height / 2)

            Rectangle {
                id: track
                anchors.fill: parent
                radius: height / 2
                color: Theme.color.surfaceContainer
                clip: true
                Rectangle {
                    id: fill
                    objectName: "volumeFill"
                    height: parent.height
                    width: Math.max(parent.height, parent.width * popup.percent / 100)
                    radius: height / 2
                    color: Theme.color.primary
                }
            }
            // the value in the pill
            Label {
                objectName: "volumeValue"
                anchors.centerIn: parent
                role: "labelMedium"
                color: popup.percent > 50 ? Theme.color.onPrimary : Theme.color.onSurface
                text: popup.percent + "%"
            }
            MouseArea {
                anchors.fill: parent
                onPressed: (mouse) => popup.setPercent(mouse.x / width * 100)
                onPositionChanged: (mouse) => popup.setPercent(mouse.x / width * 100)
            }
        }
    }
}
