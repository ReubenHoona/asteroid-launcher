/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * The call screen: ringing and in call as one layout that moves from one
 * to the other, as the stock Phone app (CP3A, Phone 164.0, Compose) does.
 * Pure presentation: IncomingCall decides what is shown and what a button
 * does. Sizes in px at 2 px per dp (384 px screen); stock files are
 * decomp/com.google.android.dialer/sources/defpackage/.
 *
 * Shared by both states: the TimeText, the name (24 sp, one line, a
 * marquee when it is longer than the screen: lzs.java:1023-1082), the 56 dp
 * monogram, the 52 dp round buttons at the two ends of one row (centre
 * y = 96 dp, 2 dp from the edges: mai.java:310) and the 56 dp EdgeButton
 * at the bottom (lzs.java:99; evp.java:1796).
 *
 *   ringing:  Decline (#EC928E, call-end glyph #410E0B) left, More options
 *             right, the green Answer EdgeButton below; the monogram on
 *             the middle of the screen.
 *   in call:  Mute left (when the watch holds the call audio), More right,
 *             the red End call EdgeButton; the monogram and the status line
 *             (the timer) above the row.
 *
 * Answer turns into End call in place (mas.java:13-23, maq.java): the
 * EdgeButton fill goes #93E5C3 -> #EC928E, its glyph #003828 -> #410E0B and
 * turns 0 -> 135 degrees over 400 ms, linear (wc.java:9); the monogram
 * moves up to its in-call place and the status line fades in.
 */
Item {
    id: screen
    objectName: "inCallScreen"

    // ---- what is shown ----
    // The name, or what stands for it (the number, "Unknown")
    property string name: ""
    // The monogram's letter; empty shows a person glyph
    property string initial: ""
    // The layout: false ringing, true in call (the change animates)
    property bool inCall: false
    // The animation of the change (it stops with the display)
    property bool animate: true
    // The status line of the in-call layout: the timer or a word
    property string status: ""
    // The buttons react (not while hanging up or after the call ended)
    property bool buttonsEnabled: true
    property bool canDecline: true
    property bool canAnswer: true
    property bool canEnd: true
    property bool canMore: true
    // The mute toggle is only there when the watch holds the call audio;
    // its slot stays empty otherwise (a 52 dp spacer, lzs.java:280)
    property bool canMute: false
    property bool muted: false
    // The name does not scroll (the display is off)
    property bool marqueePaused: false

    signal declineClicked()
    signal answerClicked()
    signal endClicked()
    signal moreClicked()
    signal muteToggled()

    // ---- stock numbers ----
    readonly property real nameTop: Math.round(Theme.dp(16.64))           // mai.java:298
    readonly property real nameSide: Math.round(Theme.dp(9.2))            // lzs.java:1023
    readonly property real nameLineHeight: Theme.type.displaySmall.lineHeight
    readonly property real monogramSize: Theme.dp(56)
    readonly property real monogramTopRinging: height / 2 - Theme.dp(28)
    readonly property real monogramTopInCall: Theme.dp(46)
    // the status line's bottom (70 dp above the screen bottom, lxf.java:153)
    readonly property real statusBottom: height - Theme.dp(70)
    readonly property real buttonSize: Theme.size.iconButton
    readonly property real buttonEdge: Theme.dp(2)
    readonly property real rowCenterY: Theme.dp(96)
    readonly property real tweenMs: 400
    readonly property real marqueeDelayMs: 1200
    readonly property int marqueeRuns: 3
    // dp per second -> px per second
    readonly property real marqueeSpeed: Theme.dp(30)
    // the gap between the two copies of a scrolling name
    readonly property real marqueeGap: 0.1493 * (width - 2 * nameSide)

    /* 0 ringing .. 1 in call */
    property real mix: inCall ? 1 : 0
    Behavior on mix {
        enabled: screen.animate
        NumberAnimation { duration: screen.tweenMs; easing.type: Easing.Linear }
    }

    function _lerp(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
    }
    function _dim(c) {
        return Qt.rgba(c.r, c.g, c.b, Theme.alpha.disabledContent)
    }

    readonly property alias nameLabel: nameText
    readonly property alias monogram: monogramCircle
    readonly property alias statusLabel: statusText
    readonly property alias declineButton: decline
    readonly property alias moreButton: more
    readonly property alias muteButton: mute
    readonly property alias bottomButton: bottom
    readonly property alias bottomIcon: bottomGlyph

    TimeText { }

    // ---- the name ----
    Item {
        id: nameBox
        objectName: "callName"
        x: screen.nameSide
        y: screen.nameTop
        width: screen.width - 2 * screen.nameSide
        height: screen.nameLineHeight
        clip: true

        readonly property bool scrolls: nameText.implicitWidth > width + 0.5

        Label {
            id: nameText
            role: "displaySmall"
            font.weight: 550
            // one line, as long as it is: the box scrolls it
            elide: Text.ElideNone
            wrapMode: Text.NoWrap
            clip: false
            width: implicitWidth
            x: nameBox.scrolls ? 0 : (nameBox.width - implicitWidth) / 2
            text: screen.name
            onTextChanged: screen._restartMarquee()
        }
        // the second copy follows the first by the gap while it scrolls
        Label {
            role: "displaySmall"
            font.weight: 550
            elide: Text.ElideNone
            clip: false
            visible: nameBox.scrolls
            width: nameText.implicitWidth
            x: nameText.x + nameText.implicitWidth + screen.marqueeGap
            text: screen.name
        }
        onWidthChanged: screen._restartMarquee()
        onScrollsChanged: screen._restartMarquee()
    }

    /* basicMarquee(iterations 3, initialDelay 1200, repeatDelay 1200,
     * velocity 30 dp/s, spacing 14.93 % of the width: abx.java): the text
     * runs left by its own width plus the gap, waits, and goes on; after
     * the third run it rests. Nothing runs while the display is off. */
    function _restartMarquee() {
        marquee.stop()
        nameText.x = nameBox.scrolls ? 0 : (nameBox.width - nameText.implicitWidth) / 2
        if (nameBox.scrolls && !marqueePaused && screen.visible && screen.width > 0)
            marquee.start()
    }
    onMarqueePausedChanged: _restartMarquee()
    onVisibleChanged: _restartMarquee()
    readonly property bool marqueeRunning: marquee.running

    SequentialAnimation {
        id: marquee
        PauseAnimation { duration: screen.marqueeDelayMs }
        SequentialAnimation {
            loops: screen.marqueeRuns
            NumberAnimation {
                target: nameText
                property: "x"
                from: 0
                to: -(nameText.implicitWidth + screen.marqueeGap)
                duration: Math.max(1, Math.round(1000 * (nameText.implicitWidth + screen.marqueeGap) / screen.marqueeSpeed))
                easing.type: Easing.Linear
            }
            PauseAnimation { duration: screen.marqueeDelayMs }
        }
        ScriptAction { script: nameText.x = 0 }
    }

    // ---- the monogram ----
    Rectangle {
        id: monogramCircle
        objectName: "callMonogram"
        width: screen.monogramSize
        height: width
        radius: width / 2
        anchors.horizontalCenter: parent.horizontalCenter
        y: screen.monogramTopRinging + (screen.monogramTopInCall - screen.monogramTopRinging) * screen.mix
        color: Theme.color.tertiaryContainer

        Label {
            anchors.centerIn: parent
            visible: screen.initial !== ""
            text: screen.initial
            role: "displaySmall"
            font.weight: 550
            elide: Text.ElideNone
            color: Theme.color.onTertiaryContainer
        }
        Icon {
            anchors.centerIn: parent
            visible: screen.initial === ""
            name: "ios-person"
            width: Theme.dp(32)
            height: width
            color: Theme.color.onTertiaryContainer
        }
    }

    // ---- the status line (the timer) ----
    Label {
        id: statusText
        objectName: "callStatus"
        role: "labelSmall"
        font.weight: 500
        font.features: Theme.tabularNumerals
        width: screen.width - 2 * Theme.dp(56)
        x: Theme.dp(56)
        horizontalAlignment: Text.AlignHCenter
        color: Theme.color.tertiaryDim
        text: screen.status
        height: Theme.type.labelSmall.lineHeight
        y: screen.statusBottom - height
        opacity: screen.mix
        visible: opacity > 0
    }

    /* A round button with its own glyph. IconButton's Icon would take a
     * dimmed colour (alpha) for the disabled look, and org.asteroid.controls
     * Icon tints its pixmap with SourceIn again on every colour change: a
     * glyph dimmed once never gets its alpha back. So the built-in glyph is
     * left transparent and the dimming is the glyph item's opacity. */
    component RoundButton: IconButton {
        id: round
        property string glyph: "ios-call"
        property real glyphSize: Theme.size.icon
        property color glyphColor: Theme.color.primary
        property real glyphRotation: 0
        property alias glyphItem: _glyph
        size: screen.buttonSize
        iconName: "ios-circle-outline"
        iconColor: "transparent"
        Icon {
            id: _glyph
            objectName: round.objectName + "Glyph"
            anchors.centerIn: parent
            name: round.glyph
            width: round.glyphSize
            height: width
            rotation: round.glyphRotation
            color: round.glyphColor
            opacity: round.enabled ? 1 : Theme.alpha.disabledContent
        }
    }

    // ---- the row: the two round buttons ----
    // Decline (ringing) and Mute (in call) share the left slot
    RoundButton {
        id: decline
        objectName: "callDecline"
        variant: "filled"
        // the call-end glyph: the handset turned 135 degrees, 48 px
        glyph: "ios-call"
        glyphSize: Theme.dp(24)
        glyphRotation: 135
        glyphColor: Theme.color.callDeclineContent
        containerColor: enabled ? Theme.color.callDecline : screen._dim(Theme.color.callDecline)
        x: screen.buttonEdge
        y: screen.rowCenterY - height / 2
        opacity: 1 - screen.mix
        visible: screen.canDecline && opacity > 0
        enabled: screen.buttonsEnabled && screen.mix < 0.5
        //% "Reject incoming call"
        Accessible.name: qsTrId("id-call-reject-a11y") + localeManager.changesObserver
        onClicked: screen.declineClicked()
    }

    RoundButton {
        id: mute
        objectName: "callMute"
        variant: "tonal"
        glyph: "ios-mic-off"
        // off: surfaceContainer / onSurfaceVariant; on: primary / onPrimary
        glyphColor: screen.muted ? Theme.color.onPrimary : Theme.color.onSurfaceVariant
        containerColor: !enabled ? screen._dim(Theme.color.surfaceContainer)
                        : screen.muted ? Theme.color.primary : Theme.color.surfaceContainer
        x: screen.buttonEdge
        y: screen.rowCenterY - height / 2
        opacity: screen.mix
        visible: screen.canMute && opacity > 0
        enabled: screen.buttonsEnabled && screen.mix > 0.5
        //% "Mute"
        Accessible.name: qsTrId("id-call-mute-a11y") + localeManager.changesObserver
        Accessible.checkable: true
        Accessible.checked: screen.muted
        onClicked: screen.muteToggled()
    }

    RoundButton {
        id: more
        objectName: "callMore"
        variant: "tonal"
        glyph: "ios-more"
        glyphColor: Theme.color.primary
        containerColor: enabled ? Theme.color.surfaceContainer : screen._dim(Theme.color.surfaceContainer)
        x: screen.width - screen.buttonEdge - width
        y: screen.rowCenterY - height / 2
        visible: screen.canMore
        enabled: screen.buttonsEnabled
        //% "More options"
        Accessible.name: qsTrId("id-call-more-a11y") + localeManager.changesObserver
        onClicked: screen.moreClicked()
    }

    // ---- Answer -> End call: one EdgeButton ----
    EdgeButton {
        id: bottom
        objectName: "callBottom"
        visible: screen.inCall ? screen.canEnd : screen.canAnswer
        enabled: screen.buttonsEnabled
        // the glyph colour (not dimmed here: see RoundButton) and the fill
        readonly property color glyphColor: screen._lerp(Theme.color.callAnswerContent, Theme.color.callDeclineContent, screen.mix)
        containerColor: {
            var c = screen._lerp(Theme.color.callAnswer, Theme.color.callDecline, screen.mix)
            return enabled ? c : screen._dim(c)
        }
        contentColor: enabled ? glyphColor : screen._dim(glyphColor)
        //% "End call"
        readonly property string endName: qsTrId("id-call-end-a11y") + localeManager.changesObserver
        //% "Answer incoming call"
        readonly property string answerName: qsTrId("id-call-answer-a11y") + localeManager.changesObserver
        Accessible.name: screen.inCall ? endName : answerName
        onClicked: screen.inCall ? screen.endClicked() : screen.answerClicked()

        Icon {
            id: bottomGlyph
            objectName: "callBottomGlyph"
            anchors.centerIn: parent
            name: "ios-call"
            width: Theme.dp(32)
            height: width
            rotation: 135 * screen.mix
            color: bottom.glyphColor
            opacity: bottom.enabled ? 1 : Theme.alpha.disabledContent
        }
    }
}
