/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import Nemo.DBus
import org.asteroid.controls
import org.asteroid.utils
import "lock.js" as Lock

/*
 * The keyguard (W3-launcher-a11y-security, accessibility-lock-security-03 to
 * -07, -10, -23): the screen lock of the launcher, as stock CP3A's
 * KeyguardViewController. Instantiated once in compositor.qml as `keyguard`
 * (z 2.5, declared before the overlay arbiter: under calls, alarms, the power
 * menu and SOS, over the face, the applications, the assistant's start). It
 * draws nothing while the watch is unlocked and costs no timer.
 *
 * Locked (lockService.locked; a credential is set and the watch was locked
 * by a restart, "Lock screen now" or the off-wrist rule):
 *  - the face stays visible under a transparent layer that fades in over
 *    500 ms and takes every touch; the face's status icon says "Device is
 *    locked" (StatusSources.screenLock). The crown and the side button only
 *    show the bouncer (keymap.js keyguardLocked).
 *  - untouched, the bouncer appears 1500 ms after the display came on, unless
 *    Touch lock is on or it is the boot lock screen; any tap, key or crown
 *    press shows it at once, a second request within 500 ms is ignored.
 *  - the bouncer is the PIN pad or the pattern pad (the kind of credential):
 *    in: scale 1.25 -> 1 in 300 ms, alpha 0.1 -> 1 in 225 ms after 75 ms,
 *    a black backdrop 0 -> 1 in 150 ms, the face zooms out to 0.9 in 300 ms
 *    (`faceZoom`, compositor.qml applies it to the home screen and the
 *    application layer); out: scale 1 -> 1.25 in 225 ms, alpha to 0 in 150
 *    ms, the backdrop and the face's zoom back over 450 ms after 150 ms.
 *  - a right credential unlocks (the pips reset, the confirm haptic, the
 *    unlock sound while Settings > Sound > Screen unlocking sound is on); a
 *    wrong one plays the pips' error reset (or the pattern's red 2000 ms) and
 *    the reject haptic. From the fifth failure the store makes a wait
 *    (eoslock.h): the bouncer is dimmed to 50 % and a dialog "Too many
 *    attempts" with the live countdown shows, redrawn each second while it is
 *    up and the display is on.
 *  - an application that opens while locked (appRequested) shows the bouncer
 *    and the toast "Unlock the watch to use %1" for 3000 ms.
 *  - after a restart (bootLocked) the boot lock screen covers the face
 *    until the first unlock (BootupLock.qml); a tap opens the bouncer.
 *
 * Off the wrist (the hub's off-body sensor, on change only; offBody
 * context object): while a credential is set and the watch is unlocked,
 * "off" locks it, and more than 5000 ms after the last unlock the display
 * goes off at once as well (displayOffRequested; the compositor asks mce).
 * No toggle, as stock (wear_wrist_detection_auto_locking_enabled).
 * On the wrist it stays unlocked through screen off and the always-on display.
 */
Item {
    id: kg
    objectName: "keyguard"
    anchors.fill: parent

    // the credential store (the launcher's LockService, a test double in tests)
    property QtObject service: typeof lockService !== "undefined" ? lockService : null
    // the hub's off-body sensor (OffBody)
    property QtObject offBodySource: typeof offBody !== "undefined" ? offBody : null
    // the display is on; the bouncer's timer and the countdown go with it
    property bool displayOn: true
    // Touch lock is on: no automatic bouncer
    property bool touchLocked: false
    // a clock in ms (tests replace it)
    property var clock: function () { return Date.now() }
    // 3 s toast to show; the name is given by whoever opens an application
    property string appToastName: ""

    readonly property bool secured: service !== null && service.secured === true
    readonly property bool locked: service !== null && service.locked === true
    readonly property bool bootLocked: service !== null && service.bootLocked === true
    readonly property string kind: service !== null ? service.kind : "none"

    // the bouncer is up (or on its way out)
    property bool bouncerShown: false
    readonly property bool bouncerPresent: bouncerShown || hideAnim.running
    // what the animations drive (compositor.qml reads faceZoom)
    property real faceZoom: 1.0
    property real backdropAlpha: 0
    property real bouncerScale: Lock.IN.scaleFrom
    property real bouncerAlpha: 0
    property real layerAlpha: 0
    // when the watch was last unlocked (ms, the clock), for the off-wrist rule
    property real unlockedAt: -1e12
    // when the bouncer was last asked for (the 500 ms debounce)
    property real requestedAt: -1e12

    // the wait after too many tries
    property bool lockoutShown: false
    property real waitMs: 0
    readonly property bool waiting: waitMs > 0
    readonly property var waitParts: Lock.waitParts(waitMs)
    // the toast of an application opened while locked
    readonly property bool launchToastShown: launchToastItem.visible
    readonly property bool bootupShown: bootup.visible

    readonly property alias pinPad: pin
    readonly property alias patternPad: pattern
    readonly property alias bootup: bootup
    readonly property alias launchToastItem: launchToast
    readonly property alias toastTimer: toastTimer
    readonly property alias lockout: lockoutView
    readonly property alias autoTimer: autoTimer
    readonly property alias waitTimer: waitTimer
    readonly property alias touchCatcher: catcher
    readonly property alias backdrop: backdropRect

    // the lock went on: the owner takes the watch to the face
    signal engaged()
    // the credential was right
    signal unlocked()
    // the sensor says off the wrist more than 5 s after the unlock: the screen goes off
    signal displayOffRequested()

    ConfigurationValue {
        id: soundSetting
        key: "/org/asteroidos/settings/screen-unlock-sound"
        defaultValue: true
    }
    readonly property bool unlockSound: soundSetting.value === true || soundSetting.value === "true"

    visible: locked || bootup.visible || hideAnim.running || layerAlpha > 0

    /* ---- showing and hiding the bouncer ------------------------------------ */

    /* Any tap, key or crown press (and the 1500 ms timer, `force`): show the bouncer. A request within
     * 500 ms of the last one is ignored. */
    function requestBouncer(force) {
        if (!locked)
            return false
        var now = clock()
        if (!force && now - requestedAt < Lock.INPUT_DEBOUNCE_MS)
            return false
        requestedAt = now
        showBouncer()
        return true
    }

    function showBouncer() {
        if (!locked || bouncerShown)
            return
        autoTimer.stop()
        hideAnim.stop()
        pin.reset()
        pattern.reset()
        updateWait()
        lockoutShown = waiting
        bouncerShown = true
        // from where they are (a bouncer on its way out comes back)
        showAnim.restart()
    }

    function hideBouncer() {
        if (!bouncerShown)
            return
        bouncerShown = false
        lockoutShown = false
        showAnim.stop()
        hideAnim.restart()
    }

    /* everything at rest, no animation (the display went off) */
    function settle() {
        showAnim.stop()
        hideAnim.stop()
        bouncerShown = false
        lockoutShown = false
        faceZoom = 1
        backdropAlpha = 0
        bouncerAlpha = 0
        bouncerScale = Lock.IN.scaleFrom
    }

    /* The face is shown again by the owner after the lock went on: arm the bouncer for 1500 ms. */
    function armAuto() {
        if (locked && displayOn && !touchLocked && !bootLocked && !bouncerShown)
            autoTimer.restart()
    }

    ParallelAnimation {
        id: showAnim
        NumberAnimation { target: kg; property: "bouncerScale"; to: 1.0; duration: Lock.IN.scaleMs
                          easing.type: Easing.BezierSpline; easing.bezierCurve: Lock.EASE_FAST_OUT_SLOW_IN }
        SequentialAnimation {
            PauseAnimation { duration: Lock.IN.alphaDelayMs }
            NumberAnimation { target: kg; property: "bouncerAlpha"; to: 1.0; duration: Lock.IN.alphaMs
                              easing.type: Easing.BezierSpline; easing.bezierCurve: Lock.EASE_FAST_OUT_SLOW_IN }
        }
        NumberAnimation { target: kg; property: "backdropAlpha"; to: 1.0; duration: Lock.IN.backdropMs
                          easing.type: Easing.BezierSpline; easing.bezierCurve: Lock.EASE_FAST_OUT_EXTRA_SLOW_IN }
        NumberAnimation { target: kg; property: "faceZoom"; to: Lock.IN.faceZoom; duration: Lock.IN.faceMs
                          easing.type: Easing.BezierSpline; easing.bezierCurve: Lock.EASE_FAST_OUT_EXTRA_SLOW_IN }
        onStarted: {
            // alpha starts at 0.1, the scale at 1.25
            kg.bouncerScale = Lock.IN.scaleFrom
            kg.bouncerAlpha = Lock.IN.alphaFrom
        }
    }
    ParallelAnimation {
        id: hideAnim
        NumberAnimation { target: kg; property: "bouncerScale"; to: Lock.OUT.scaleTo; duration: Lock.OUT.scaleMs
                          easing.type: Easing.BezierSpline; easing.bezierCurve: Lock.EASE_FAST_OUT_SLOW_IN }
        NumberAnimation { target: kg; property: "bouncerAlpha"; to: 0; duration: Lock.OUT.alphaMs
                          easing.type: Easing.BezierSpline; easing.bezierCurve: Lock.EASE_FAST_OUT_SLOW_IN }
        SequentialAnimation {
            PauseAnimation { duration: Lock.OUT.delayMs }
            ParallelAnimation {
                NumberAnimation { target: kg; property: "backdropAlpha"; to: 0; duration: Lock.OUT.backdropMs
                                  easing.type: Easing.BezierSpline; easing.bezierCurve: Lock.EASE_FAST_OUT_EXTRA_SLOW_IN }
                NumberAnimation { target: kg; property: "faceZoom"; to: 1.0; duration: Lock.OUT.faceMs
                                  easing.type: Easing.BezierSpline; easing.bezierCurve: Lock.EASE_FAST_OUT_EXTRA_SLOW_IN }
            }
        }
    }

    NumberAnimation {
        id: layerFade
        target: kg
        property: "layerAlpha"
        duration: Lock.LAYER_FADE_MS
    }

    /* ---- the lock going on and off ------------------------------------------ */

    onLockedChanged: {
        if (locked) {
            layerFade.stop()
            layerFade.to = 1
            layerFade.start()
            bouncerShown = false
            hideAnim.stop()
            showAnim.stop()
            faceZoom = 1
            backdropAlpha = 0
            bouncerAlpha = 0
            engaged()
            armAuto()
        } else {
            autoTimer.stop()
            lockoutShown = false
            waitMs = 0
            // out with the bouncer; the layer goes when the animation has ended
            if (bouncerShown)
                hideBouncer()
            layerFade.stop()
            layerAlpha = 0
        }
    }

    onDisplayOnChanged: {
        if (!displayOn) {
            autoTimer.stop()
            settle()
        } else {
            armAuto()
        }
    }

    Timer {
        id: autoTimer
        interval: Lock.AUTO_BOUNCER_MS
        onTriggered: kg.requestBouncer(true)
    }

    Connections {
        target: kg.service
        ignoreUnknownSignals: true
        function onUnlocked() {
            kg.unlockedAt = kg.clock()
            kg.unlocked()
            // stock UnlockFeedbackPlayer: the unlock sound (with its haptic) while it is on, else the
            // confirm haptic alone
            if (kg.unlockSound)
                Haptics.play("eos_screen_unlock")
            else
                Haptics.confirm()
        }
    }

    /* ---- a try at the credential ---------------------------------------------- */

    function updateWait() {
        waitMs = service !== null ? service.remainingMs() : 0
    }

    /* The PIN (4 digits) or the pattern (dots in order) from the pad. */
    function tryCredential(secret) {
        if (service === null || !locked)
            return
        var r = service.tryUnlock(secret)
        if (r === 0)
            return
        // wrong (or inside a wait): the pad's error, the reject haptic
        Haptics.reject()
        if (kind === "pattern")
            pattern.showError()
        else
            pin.resetWithError()
        updateWait()
        if (waiting)
            lockoutShown = true
    }

    onWaitingChanged: if (!waiting && lockoutShown) lockoutShown = false

    Timer {
        id: waitTimer
        interval: 1000
        repeat: true
        running: kg.lockoutShown && kg.displayOn
        onTriggered: kg.updateWait()
    }

    /* ---- an application opened while locked (gap -23) --------------------------- */

    function appRequested(name) {
        if (!locked)
            return false
        appToastName = name
        //% "Unlock the watch to use %1"
        launchToast.text = qsTrId("id-lock-unlock-to-use").arg(name)
        launchToast.show()
        requestedAt = clock()
        showBouncer()
        return true
    }

    // mce: the display off at once (the off-wrist rule, more than 5 s after the unlock)
    property DBusInterface mce: DBusInterface {
        service: "com.nokia.mce"
        path: "/com/nokia/mce/request"
        iface: "com.nokia.mce.request"
        bus: DBus.SystemBus
    }
    function requestDisplayOff() {
        mce.call("req_display_state_off", undefined)
        displayOffRequested()
    }

    /* ---- off the wrist (gap -06) ------------------------------------------------ */

    Connections {
        target: kg.offBodySource
        enabled: kg.secured && !kg.locked
        ignoreUnknownSignals: true
        function onChanged() {
            var a = Lock.offBodyAction(kg.offBodySource.state, kg.secured, kg.locked, kg.unlockedAt, kg.clock())
            if (a === "none")
                return
            kg.service.lock()
            if (a === "lockAndOff")
                kg.requestDisplayOff()
        }
    }

    /* ---- the surfaces ------------------------------------------------------------- */

    // every touch stops here while locked; a tap shows the bouncer. The crown's wheel is not a touch:
    // the WheelHandler keeps RotaryInput from scrolling what is under the lock.
    MultiPointTouchArea {
        id: catcher
        anchors.fill: parent
        enabled: kg.locked
        mouseEnabled: true
        opacity: 1
        onPressed: kg.requestBouncer(false)
        WheelHandler {
            enabled: kg.locked
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => { event.accepted = true; kg.requestBouncer(false) }
        }
    }

    // the boot lock screen
    BootupLock {
        id: bootup
        anchors.fill: parent
        shown: kg.bootLocked && kg.locked
        onTapped: kg.requestBouncer(false)
    }

    // the black backdrop of the bouncer (over the face, under the pad)
    Rectangle {
        id: backdropRect
        objectName: "keyguardBackdrop"
        anchors.fill: parent
        color: "#000000"
        opacity: kg.backdropAlpha
        visible: opacity > 0
    }

    // the bouncer
    Item {
        id: bouncer
        objectName: "keyguardBouncer"
        anchors.fill: parent
        visible: kg.bouncerPresent
        opacity: kg.bouncerAlpha
        scale: kg.bouncerScale

        PinPad {
            id: pin
            anchors.fill: parent
            visible: kg.kind !== "pattern"
            inputEnabled: !kg.waiting
            onSubmitted: (secret) => kg.tryCredential(secret)
        }
        PatternPad {
            id: pattern
            anchors.fill: parent
            visible: kg.kind === "pattern"
            inputEnabled: !kg.waiting
            onCompleted: (dots) => kg.tryCredential(dots)
        }

        // the wait's dialog: "Too many attempts", the countdown, one round button
        LockoutDialog {
            id: lockoutView
            anchors.fill: parent
            shown: kg.lockoutShown
            parts: kg.waitParts
            onDismissed: kg.hideBouncer()
        }
    }

    // "Unlock the watch to use %1": 3000 ms
    Rectangle {
        id: launchToast
        objectName: "keyguardLaunchToast"
        property string text: ""
        function show() { visible = true; toastTimer.restart() }
        visible: false
        z: 10
        color: "#E6FFFFFF"
        radius: Theme.dp(24)
        width: Math.min(kg.width - Theme.dp(32), toastText.implicitWidth + Theme.dp(32))
        height: toastText.implicitHeight + Theme.dp(24)
        x: (kg.width - width) / 2
        y: (kg.height - height) / 2
        Text {
            id: toastText
            anchors.centerIn: parent
            width: parent.width - Theme.dp(32)
            text: launchToast.text
            color: "#000000"
            font.pixelSize: Theme.sp(13)
            font.weight: Font.Medium
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }
        Timer {
            id: toastTimer
            interval: Lock.LAUNCH_TOAST_MS
            onTriggered: launchToast.visible = false
        }
    }

    Accessible.role: Accessible.Pane
    //% "Screen locked"
    Accessible.name: qsTrId("id-lock-screen-locked")
}
