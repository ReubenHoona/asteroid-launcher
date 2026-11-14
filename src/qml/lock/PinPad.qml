/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "lock.js" as Lock

/*
 * The PIN pad (W3-launcher-a11y-security, accessibility-lock-security-03):
 * stock's Material 3 bouncer (PinPadEditView, NumPadKt, VALUES.tsv systemui
 * pin_pad_m3_*). Four pips on top, 18 dp, turned -15, -5, 5 and 15 degrees,
 * the outer two 3 dp lower, the row's top margin 3.65 % of the height; each
 * pip turns into one of six shuffled shapes when a digit lands (83 ms, then
 * 333 ms). Under them the 4 x 3 numpad "1 2 3 / 4 5 6 / 7 8 9 / back 0
 * enter": side padding 6.4 %, top 4 %, bottom 3.7 %, 10 dp between the
 * keys; the digit keys are filled circles (primaryDim, text onPrimary, 30 sp
 * on a 34 sp line, displayMedium weight 500), pressed they become a 12 dp
 * rounded square (tertiaryDim, onTertiary, weight 700); no ripple. Backspace
 * is an icon in tertiaryDim, errorDim and scaled 1.16 while pressed; the
 * enter key is hidden: the fourth digit submits.
 *
 * It only collects the digits: the owner asks the credential store and
 * answers with reset() (right) or resetWithError() (wrong: the pips play the
 * error reset, staggered (4 - i) * 50 ms, and the input is open again).
 * `enabled: false` (a wait after too many tries) dims the keys to 50 %
 * (numpad_min_alpha) and takes no digit.
 *
 * Stock draws it with Compose in the dynamic colour scheme; ours uses the
 * theme's palette (Theme.color), which the colour theme package makes dynamic.
 */
Item {
    id: pad
    objectName: "pinPad"

    // the digits typed so far
    property string entry: ""
    // false: no digit is taken and the keys are dimmed
    property bool inputEnabled: true
    // true while the pips play the wrong-PIN reset
    readonly property bool erroring: errorHold > 0
    property int errorHold: 0
    // the shape order of the pips (a shuffle of 0..5), new at every reset
    property var shapes: Lock.shapeOrder(Math.random)
    // the owner's picks of random numbers (tests replace it)
    property var random: Math.random
    // the geometry (padMetrics)
    readonly property var metrics: Lock.padMetrics(width, height, Theme.dp(1))
    readonly property real keyAlpha: inputEnabled ? 1.0 : 0.5
    readonly property alias keys: keyRepeater
    readonly property alias pips: pipRepeater

    // the 4th digit is in: the PIN to check
    signal submitted(string pin)
    // a key went down (the haptic is the pad's own; the owner may count)
    signal keyPressed(string key)

    function press(key) {
        if (!inputEnabled)
            return
        var r = Lock.pressKey(entry, key)
        entry = r.entry
        if (r.submit)
            submitted(entry)
    }

    /* right PIN (or a new start): the pips go back to empty at once */
    function reset() {
        entry = ""
        shapes = Lock.shapeOrder(random)
        for (var i = 0; i < pipRepeater.count; i++)
            pipRepeater.itemAt(i).clearNow()
    }

    /* wrong PIN: the pips fade out one after the other, the first one last
     * ((4 - i) * 50 ms), and the entry is open again at once */
    function resetWithError() {
        entry = ""
        shapes = Lock.shapeOrder(random)
        for (var i = 0; i < pipRepeater.count; i++)
            pipRepeater.itemAt(i).errorOut(Lock.pipResetDelay(i))
    }

    // the pips
    Item {
        id: pipRow
        objectName: "pinPips"
        readonly property real pipSize: pad.metrics.pip
        readonly property real spacing: Theme.dp(8)
        width: 4 * pipSize + 3 * spacing
        height: pipSize + Theme.dp(3)
        x: (pad.width - width) / 2
        y: pad.metrics.pipY

        Repeater {
            id: pipRepeater
            model: Lock.PIN_LENGTH
            Item {
                id: pip
                objectName: "pinPip" + index
                width: pipRow.pipSize
                height: pipRow.pipSize
                x: index * (pipRow.pipSize + pipRow.spacing)
                y: Theme.dp(Lock.PIP_DROP_DP[index])
                rotation: Lock.PIP_ROTATION[index]

                readonly property bool filled: index < pad.entry.length
                // 0 = a small dot, 1 = its shape at full size
                property real morph: 0
                property bool failed: false
                property real fade: 1
                readonly property var shape: Lock.PIP_SHAPES[pad.shapes[index] % Lock.PIP_SHAPES.length]

                function clearNow() {
                    errorAnim.stop()
                    failed = false
                    fade = 1
                    morph = filled ? morph : 0
                }
                function errorOut(delay) {
                    errorAnim.stop()
                    failed = true
                    pad.errorHold++
                    errorAnim.delay = delay
                    errorAnim.restart()
                }

                onFilledChanged: {
                    if (filled) {
                        errorAnim.stop()
                        failed = false
                        fade = 1
                        morphIn.restart()
                    } else if (!failed) {
                        morphIn.stop()
                        morph = 0
                    }
                }

                // 83 ms to a first size, 333 ms to the shape
                SequentialAnimation {
                    id: morphIn
                    NumberAnimation { target: pip; property: "morph"; to: 0.55; duration: Lock.PIP_MORPH_FIRST_MS; easing.type: Easing.OutQuad }
                    NumberAnimation { target: pip; property: "morph"; to: 1; duration: Lock.PIP_MORPH_SECOND_MS; easing.type: Easing.OutBack }
                }
                SequentialAnimation {
                    id: errorAnim
                    property int delay: 0
                    PauseAnimation { duration: errorAnim.delay }
                    ParallelAnimation {
                        NumberAnimation { target: pip; property: "fade"; to: 0; duration: 150 }
                        NumberAnimation { target: pip; property: "morph"; to: 0; duration: 150 }
                    }
                    ScriptAction {
                        script: {
                            pip.failed = false
                            pip.fade = 1
                            pip.morph = 0
                            pad.errorHold = Math.max(0, pad.errorHold - 1)
                        }
                    }
                }

                // the empty pip: a small dot
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.4
                    height: width
                    radius: width / 2
                    color: Theme.color.onSurface
                    opacity: (1 - pip.morph) * 0.5 * pip.fade
                }
                // the filled pip: one of the six shapes
                Rectangle {
                    objectName: "pinPipShape"
                    anchors.centerIn: parent
                    readonly property real full: pip.width
                    width: Math.max(1, full * pip.shape.w * (0.4 + 0.6 * pip.morph))
                    height: Math.max(1, full * pip.shape.h * (0.4 + 0.6 * pip.morph))
                    radius: Math.min(width, height) * pip.shape.r
                    rotation: pip.shape.rot * pip.morph
                    color: pip.failed ? Theme.color.errorDim : "#ffffff"
                    opacity: pip.morph * pip.fade
                }
            }
        }
    }

    // the numpad
    Repeater {
        id: keyRepeater
        model: Lock.KEYS
        Item {
            id: keyCell
            objectName: "pinKey_" + modelData
            readonly property var cell: pad.metrics.cells[index]
            readonly property bool isDigit: modelData.length === 1
            readonly property bool pressed: area.pressed
            x: cell.x
            y: cell.y
            width: cell.size
            height: cell.size
            // the hidden enter key
            visible: modelData !== "enter"
            opacity: pad.keyAlpha

            Rectangle {
                id: face
                objectName: "pinKeyFace"
                anchors.fill: parent
                visible: keyCell.isDigit
                color: keyCell.pressed ? Theme.color.tertiaryDim : Theme.color.primaryDim
                radius: keyCell.pressed ? Theme.dp(Lock.PRESSED_RADIUS_DP) : width / 2
                Behavior on radius { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
            }
            Text {
                objectName: "pinKeyText"
                anchors.centerIn: parent
                visible: keyCell.isDigit
                text: modelData
                color: keyCell.pressed ? Theme.color.onTertiary : Theme.color.onPrimary
                font.pixelSize: Theme.sp(Lock.DIGIT_SP)
                // 500, 700 pressed: the nearest weights of the face
                font.weight: keyCell.pressed ? Font.Bold : Font.Medium
                lineHeight: Theme.sp(Lock.DIGIT_LINE_SP)
                lineHeightMode: Text.FixedHeight
            }
            Icon {
                objectName: "pinKeyIcon"
                anchors.centerIn: parent
                visible: !keyCell.isDigit
                width: parent.width * 0.55
                height: width
                name: "ms-backspace"
                color: keyCell.pressed ? Theme.color.errorDim : Theme.color.tertiaryDim
                scale: keyCell.pressed ? Lock.ICON_PRESSED_SCALE : 1
                Behavior on scale { NumberAnimation { duration: 100 } }
            }

            MouseArea {
                id: area
                anchors.fill: parent
                enabled: pad.inputEnabled
                onPressed: {
                    Haptics.virtualKey()
                    pad.keyPressed(modelData)
                }
                onClicked: pad.press(modelData)
            }

            //% "Delete"
            readonly property string deleteName: qsTrId("id-lock-delete")
            //% "Enter"
            readonly property string enterName: qsTrId("id-lock-enter")
            Accessible.role: Accessible.Button
            Accessible.name: keyCell.isDigit ? modelData : (modelData === "back" ? deleteName : enterName)
            Accessible.onPressAction: pad.press(modelData)
        }
    }

    Accessible.role: Accessible.Pane
    //% "PIN area"
    Accessible.name: qsTrId("id-lock-pin-area")
}
