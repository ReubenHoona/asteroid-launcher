/*
 * Copyright (C) 2026 Timo Könnecke <github.com/moWerk>
 *               2017 Florent Revest <revestflo@gmail.com>
 * All rights reserved.
 *
 * You may use this file under the terms of BSD license as follows:
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the author nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import QtQuick
import org.asteroid.controls
import org.asteroid.utils
import org.asteroid.settings
import Nemo.Configuration
import Nemo.DBus
import Nemo.Mce
import "../desktop.js" as Desktop
import "setup.js" as Setup

/* The setup (first run) of a new watch, as stock CP3A's setup wizard (W3-launcher-setup, DECISIONS.md Q58:
 * setup as stock, no Skip). Pairing comes first and cannot be skipped:
 *
 *   [low battery gate] -> first screen -> language list -> instructions (-> help)
 *     -> (the phone bonds) code screen -> connecting
 *     -> place and time zone (only while the zone is unknown) -> time and date (only when the phone did not
 *        set the clock) -> Setup complete -> the tutorial
 *
 * The pages are in a stack: a swipe right goes back (setup.js: backAllowed), back is ignored on the first
 * screen. The pages cross-fade (250 ms after 150 ms in, 150 ms out) on a black background.
 *
 * Display policy (setup-wizard-05): each time a setup screen opens, or is touched, the display is held on
 * for 360 s (one single shot timer; then mce's normal timeout runs and the always-on face shows); in
 * ambient the animations stop (the pages read displayOn) and on waking the first screen returns unless a
 * code is showing. Off the charger one exact wake-up alarm powers the watch off 3600 s after the last arming
 * (a page change, or a touch a minute after the last arming); the charger cancels it.
 *
 * Pairing during setup (setup-wizard-09, -14, connectivity-system-ux-04): the Bluetooth dialog stays away
 * (Desktop.setupPairing); this item answers the agent: a numeric comparison is shown and accepted at once,
 * a consent is accepted, a code the watch displays is shown, anything that needs typing and every request
 * after the first bond is refused. A failed bond closes the code screen and the page before it is back.
 *
 * Power (M1): no polling here (battery and charger by signal, GPS only on the place page), all timers are
 * single shots. */
Item {
    id: config
    objectName: "firstRunConfig"
    anchors.fill: parent

    // the display is on and not in the always-on screen (the compositor's state)
    property bool displayOn: true
    // the name the phone app lists (the BlueZ alias)
    property string watchName: typeof firstRun !== "undefined" && firstRun !== null ? firstRun.bluetoothName() : ""
    // the setup is over: the host removes it and may start the tutorial
    signal done()

    // ---- state ----
    property var stack: []
    readonly property string page: stack.length > 0 ? stack[stack.length - 1] : ""
    // the page on screen (it follows `page` through the cross-fade)
    property string shownPage: ""
    // after the bond: the pages still to come
    property var queue: []
    property bool codeUp: false
    property string codeKind: "secure"
    property string codeValue: ""
    // a phone has bonded: no other pairing is accepted
    property bool bonded: false
    // the watch has answered the pairing request (the phone's side decides now)
    property bool accepted: false
    property bool finished: false
    property string currentTz: ""
    property bool clockSet: false
    // the language rows
    property var languages: []

    readonly property alias gps: gpsObj
    readonly property alias stage: stageObj
    // what moves with the swipe back and fades between pages
    readonly property alias content: stageItem
    readonly property alias backArea: backAreaObj
    readonly property alias fadeOut: fadeOutObj
    readonly property alias fadeIn: fadeInObj
    readonly property alias bondTimer: bondTimerObj
    readonly property alias linkTimer: linkTimerObj
    readonly property alias screenTimer: screenTimerObj
    readonly property alias pageLoader: pageLoaderObj
    readonly property alias codeLoader: codeLoaderObj
    readonly property int level: batteryLevel.valid ? batteryLevel.percent : -1
    readonly property bool charging: chargerType.valid && chargerType.type !== MceChargerType.None
    readonly property bool backEnabled: Setup.backAllowed(stack, codeUp)

    // ---- facts ----
    MceBatteryLevel { id: batteryLevel }
    MceChargerType { id: chargerType }
    BluetoothStatus { id: bluetoothStatus }
    // the Bluetooth link (a test sets another object with `connected`)
    property var link: bluetoothStatus
    LanguageModel { id: langSettings }
    // the languages (a test sets another model with rowCount(), index(), data() and setSystemLocale())
    property var languageModel: langSettings
    DateTimeSettings { id: dtSettings }
    // the system's time zone now (a test replaces it)
    property var zoneNow: function () { return dtSettings.currentTimezone() }
    WallClock { id: wallClock }

    ConfigurationValue {
        id: clockFromPhoneObj
        key: "/org/asteroidos/time/phone-set"
        defaultValue: false
    }
    ConfigurationValue {
        id: orientation
        key: "/org/asteroidos/settings/wrist-orientation-mode"
        defaultValue: 0
    }
    readonly property alias clockFromPhone: clockFromPhoneObj

    DBusInterface {
        id: timedateDbus
        bus: DBus.SystemBus
        service: "org.freedesktop.timedate1"
        path: "/org/freedesktop/timedate1"
        iface: "org.freedesktop.timedate1"
    }
    property var timezoneList: []

    SetupGps {
        id: gpsObj
        // only the place page asks for positions, with the display on
        searching: config.shownPage === Setup.pages.place && config.displayOn
        onFixReady: config.applyGpsFix()
    }

    // ---- start ----
    Component.onCompleted: {
        Desktop.setupPairing = config
        firstRun.startFirstRun()
        currentTz = zoneNow()
        timedateDbus.call("ListTimezones", undefined, function(m) { config.timezoneList = m })
        buildLanguages()
        var gate = Setup.gateNeeded(level, batteryLevel.valid) ? Setup.pages.charge : Setup.pages.first
        stack = [gate]
        shownPage = gate
        activity()
        updatePowerOff(true)
    }
    Component.onDestruction: {
        if (Desktop.setupPairing === config)
            Desktop.setupPairing = null
        screenTimerObj.stop()
        firstRun.keepScreenOn(false)
        firstRun.armIdlePowerOff(0)
    }

    // the Bluetooth dialog is not shown while this is up
    readonly property bool active: !finished

    // ---- the page stack ----
    function go(newStack) {
        if (newStack.join() === stack.join())
            return
        stack = newStack
        activity()
        updatePowerOff(true)
        swap()
    }
    function open(p) { go(Setup.pushPage(stack, p)) }
    function goBack() {
        if (!backEnabled)
            return
        go(Setup.popPage(stack))
    }
    function replaceAll(p) { go([p]) }

    // the cross-fade: out 150 ms, then the new page in over 250 ms
    function swap() {
        if (shownPage === "") {
            shownPage = page
            return
        }
        if (Motion.reduceMotion) {
            shownPage = page
            stageItem.opacity = 1
            return
        }
        fadeInObj.stop()
        fadeOutObj.restart()
    }

    SequentialAnimation {
        id: fadeOutObj
        NumberAnimation {
            target: stageItem; property: "opacity"; to: Setup.fade.outTo
            duration: Setup.fade.outMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Setup.fade.outEasing.concat([1, 1])
        }
        ScriptAction {
            script: {
                config.shownPage = config.page
                fadeInObj.restart()
            }
        }
    }
    NumberAnimation {
        id: fadeInObj
        target: stageItem
        property: "opacity"
        from: Setup.fade.inFrom
        to: 1
        duration: Setup.fade.inMs
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Setup.fade.inEasing.concat([1, 1])
    }

    // ---- the pages ----
    Item {
        id: stageObj
        objectName: "setupStage"
        anchors.fill: parent

        // the swipe back follows the finger: the page moves right and shrinks as in a back transition
        BackSwipeArea {
            id: backAreaObj
            anchors.fill: parent
            swipeEnabled: config.backEnabled && !fadeOutObj.running
            onStarted: {
                backSpring.snapTo(backAreaObj.smoothedProgress)
                config._dragging = true
            }
            onFinished: {
                config._dragging = false
                backSpring.snapTo(backAreaObj.smoothedProgress)
                backSpring.animateTo(backAreaObj.committed ? 1 : 0, backAreaObj.smoothedVelocity)
            }

            Item {
                id: stageItem
                objectName: "setupStageItem"
                width: parent.width
                height: parent.height
                transform: Translate { x: config.backProgress * config.width }

                Loader {
                    id: pageLoaderObj
                    objectName: "setupPageLoader"
                    anchors.fill: parent
                    sourceComponent: config.componentFor(config.shownPage)
                }
            }
        }
    }

    property bool _dragging: false
    readonly property real backProgress: _dragging ? backAreaObj.smoothedProgress : backSpring.value
    WearSpring {
        id: backSpring
        stiffness: Motion.inAppBack.settle.stiffness
        dampingRatio: Motion.inAppBack.settle.dampingRatio
        visibilityThreshold: 0.002
        onFinished: {
            var popped = backSpring.value >= 0.99
            backSpring.snapTo(0)
            backAreaObj.reset()
            if (popped)
                config.goBack()
        }
    }

    function componentFor(p) {
        switch (p) {
        case Setup.pages.charge: return chargePage
        case Setup.pages.first: return firstPage
        case Setup.pages.language: return languagePage
        case Setup.pages.instructions: return instructionsPage
        case Setup.pages.help: return helpPage
        case Setup.pages.connecting: return connectingPage
        case Setup.pages.place: return placePage
        case Setup.pages.region: return regionPage
        case Setup.pages.city: return cityPage
        case Setup.pages.time: return timePage
        case Setup.pages.date: return datePage
        case Setup.pages.complete: return completePage
        }
        return null
    }

    Component {
        id: chargePage
        SetupCharge {
            level: config.level
            charging: config.charging
        }
    }
    Component {
        id: firstPage
        SetupFirst {
            displayOn: config.displayOn
            active: config.displayOn && !config.codeUp
            onChooseLanguage: config.open(Setup.pages.language)
        }
    }
    Component {
        id: languagePage
        SetupList {
            //% "Choose your language"
            accessibleName: qsTrId("id-setup-your-language") + localeManager.changesObserver
            entries: config.languages
            onChosen: key => config.chooseLanguage(key)
        }
    }
    Component {
        id: instructionsPage
        SetupInstructions {
            watchName: config.watchName
            onNeedHelp: config.open(Setup.pages.help)
        }
    }
    Component { id: helpPage; SetupHelp { } }
    Component {
        id: connectingPage
        SetupConnecting {
            id: connecting
            displayOn: config.displayOn
            // the link is up and the first turn is shown: go on
            readonly property bool ready: played && link.connected
            onReadyChanged: if (ready) config.afterConnecting()
        }
    }
    Component {
        id: placePage
        SetupList {
            //% "Choose your time zone"
            accessibleName: qsTrId("id-country-selection-hint") + localeManager.changesObserver
            entries: [
                //% "GPS"
                { text: qsTrId("id-gps") + localeManager.changesObserver, sub: gpsObj.statusText(), key: "gps" },
                //% "Country selection"
                { text: qsTrId("id-country-selection") + localeManager.changesObserver,
                  //% "Choose your time zone"
                  sub: qsTrId("id-country-selection-hint") + localeManager.changesObserver, key: "list" }
            ]
            onChosen: key => config.choosePlace(key)
        }
    }
    Component {
        id: regionPage
        SetupList {
            accessibleName: qsTrId("id-country-selection-hint") + localeManager.changesObserver
            entries: config.regionEntries()
            onChosen: key => config.chooseRegion(key)
        }
    }
    Component {
        id: cityPage
        SetupList {
            accessibleName: qsTrId("id-country-selection-hint") + localeManager.changesObserver
            entries: config.cityEntries(config.pendingRegion)
            onChosen: key => config.chooseCity(key)
        }
    }
    Component {
        id: timePage
        SetupTime {
            hour: config.startTime().hour
            minute: config.startTime().minute
            onPicked: (h, m) => config.chooseTime(h, m)
        }
    }
    Component {
        id: datePage
        SetupDate {
            date: config.startDate()
            onPicked: (y, m, d) => config.chooseDate(y, m, d)
        }
    }
    Component {
        id: completePage
        SetupComplete {
            onFinished: config.finish()
        }
    }

    // the code screen is over the page, outside the stack
    Loader {
        id: codeLoaderObj
        objectName: "setupCodeLoader"
        anchors.fill: parent
        active: config.codeUp
        z: 5
        sourceComponent: SetupCode {
            kind: config.codeKind
            code: config.codeValue
            displayOn: config.displayOn
            active: config.displayOn
        }
    }

    // ---- the language ----
    function buildLanguages() {
        var rows = []
        for (var i = 0; i < languageModel.rowCount(); i++) {
            var ix = languageModel.index(i, 0)
            rows.push({ name: languageModel.data(ix, LanguageModel.NameRole),
                        locale: languageModel.data(ix, LanguageModel.LocaleRole),
                        regionLabel: languageModel.data(ix, LanguageModel.RegionLabelRole) })
        }
        var ordered = Setup.languageList(rows, ["en_US", "en_GB"])
        var entries = []
        for (var j = 0; j < ordered.length; j++)
            entries.push({ text: ordered[j].name, key: ordered[j].locale })
        languages = entries
    }

    // a tap applies the language at once and goes to the instructions
    function chooseLanguage(locale) {
        languageModel.setSystemLocale(locale, LanguageModel.UpdateWithoutReboot)
        open(Setup.pages.instructions)
    }

    // ---- pairing ----
    function showCode(kind, value) {
        codeKind = kind
        codeValue = value
        codeUp = true
        activity()
    }

    function handleAgent() {
        var st = bluetoothAgent.state
        var action = Setup.agentAction(st, { bonded: bonded })
        if (finished) {
            return
        }
        switch (action) {
        case "show-accept":
            showCode(Setup.codeKind(st), Setup.codeText(st, bluetoothAgent.passkey, bluetoothAgent.pinCode))
            // the watch confirms its side itself (stock: the code screen has no buttons)
            accepted = true
            bondTimerObj.restart()
            bluetoothAgent.userAccepts()
            break
        case "accept":
            accepted = true
            bondTimerObj.restart()
            bluetoothAgent.userAccepts()
            break
        case "show":
            showCode(Setup.codeKind(st), Setup.codeText(st, bluetoothAgent.passkey, bluetoothAgent.pinCode))
            break
        case "cancel":
            bluetoothAgent.userCancels()
            break
        default:
            // the agent is idle again: with a code showing that nobody answered, the phone ended it (a display
            // only code is done on the phone's side: wait for the link as after an accept)
            if (st === Setup.agent.Idle && codeUp && !accepted && !bonded) {
                accepted = true
                bondTimerObj.restart()
            }
        }
    }

    Connections {
        target: bluetoothAgent
        function onStateChanged() { config.handleAgent() }
    }

    // a failed bond: the code goes and the page before it is there again (pairing still possible)
    function failBond() {
        bondTimerObj.stop()
        accepted = false
        codeUp = false
        activity()
    }
    // no link within bondWaitMs after the watch accepted: the bond failed
    Timer {
        id: bondTimerObj
        interval: Setup.bondWaitMs
        onTriggered: if (!config.bonded) config.failBond()
    }

    readonly property bool linkUp: link.connected === true
    onLinkUpChanged: {
        if (linkUp) {
            if (accepted)
                bondDone()
            else if (!bonded && !finished && (page === Setup.pages.first || page === Setup.pages.language
                                              || page === Setup.pages.instructions || page === Setup.pages.help))
                linkTimerObj.restart()
        } else {
            linkTimerObj.stop()
        }
    }
    onAcceptedChanged: if (accepted && linkUp) bondDone()
    // a link with no pairing request: a phone that was bonded before (no code to show)
    Timer {
        id: linkTimerObj
        interval: Setup.bondedLinkMs
        onTriggered: {
            if (config.linkUp && !config.bonded && !config.codeUp) {
                config.accepted = true
                config.bondDone()
            }
        }
    }

    function bondDone() {
        if (bonded || finished)
            return
        bonded = true
        bondTimerObj.stop()
        linkTimerObj.stop()
        codeUp = false
        replaceAll(Setup.pages.connecting)
    }

    // the connecting page has run: the pages the phone could not fill in
    function afterConnecting() {
        queue = Setup.pagesAfterBond(zoneNow(), clockFromPhoneObj.value === true)
        advance()
    }
    function advance() {
        if (queue.length === 0)
            return
        var p = queue[0]
        queue = queue.slice(1)
        replaceAll(p)
    }

    // ---- place, time zone, time, date (setup-wizard-04) ----
    property string pendingRegion: ""
    property bool gpsApplied: false

    function setZone(tz) {
        currentTz = tz
        timedateDbus.typedCall("SetTimezone", [
            { "type": "s", "value": tz },
            { "type": "b", "value": false }
        ],
        function(result) { console.log("FirstRunConfig: time zone set to", tz) },
        function(error, message) { console.log("FirstRunConfig: SetTimezone failed:", error, message) })
    }

    function choosePlace(key) {
        if (key === "gps") {
            if (!gpsObj.available || gpsObj.status === 0)
                return
            if (gpsObj.fix) {
                applyGpsFix()
            } else {
                gpsObj.waitingForFix = true
            }
        } else {
            gpsObj.waitingForFix = false
            open(Setup.pages.region)
        }
    }

    // the time zone, and the clock's offset, from the fix; the next pages start filled in with them
    function applyGpsFix() {
        if (gpsApplied || page !== Setup.pages.place)
            return
        var tz = firstRun.timezoneForPosition(gpsObj.latitude, gpsObj.longitude)
        if (tz === "") {
            gpsObj.waitingForFix = false
            open(Setup.pages.region)
            return
        }
        gpsApplied = true
        gpsObj.waitingForFix = false
        setZone(tz)
        advance()
    }

    function regionEntries() {
        var allowlist = ["Africa", "America", "Antarctica", "Arctic", "Asia", "Atlantic", "Australia", "Europe", "Indian", "Pacific"]
        var e = []
        for (var i = 0; i < allowlist.length; i++)
            e.push({ text: allowlist[i], key: allowlist[i] })
        e.push({ text: "Zulu", key: "Zulu" })
        return e
    }
    function cityEntries(region) {
        var e = []
        var prefix = region + "/"
        for (var i = 0; i < timezoneList.length; i++) {
            var tz = timezoneList[i]
            if (tz.indexOf(prefix) === 0)
                e.push({ text: tz.substring(prefix.length).replace(/_/g, " "), key: tz })
        }
        return e
    }
    function chooseRegion(key) {
        if (key === "Zulu") {
            setZone("Zulu")
            advance()
            return
        }
        pendingRegion = key
        open(Setup.pages.city)
    }
    function chooseCity(tz) {
        setZone(tz)
        advance()
    }

    // local time now in the zone picked so far (the GPS clock after a fix, else the system clock)
    function localNow() {
        if (currentTz === "")
            return null
        var offset = gpsApplied ? gpsObj.clockOffset : 0
        var local = firstRun.localDateTime(currentTz, Math.round(Date.now() / 1000 + offset))
        return local && local.hour !== undefined ? local : null
    }

    // where the pickers start: the zone's local time now, else the system clock
    function startTime() {
        var l = localNow()
        return l ? { hour: l.hour, minute: l.minute }
                 : { hour: wallClock.time.getHours(), minute: wallClock.time.getMinutes() }
    }
    function startDate() {
        var l = localNow()
        return l ? new Date(l.year, l.month - 1, l.day) : new Date()
    }

    function chooseTime(h, m) {
        dtSettings.setTime(h, m)
        advance()
    }
    function chooseDate(y, m, d) {
        dtSettings.setDate(new Date(y, m - 1, d))
        advance()
    }

    // ---- the end ----
    function finish() {
        if (finished)
            return
        finished = true
        console.log("FirstRunConfig: setup complete, wrist orientation mode", orientation.value)
        firstRun.finishSetup()
        // the completion cue: the sound (3.05 s) and the 200/50/50/50 ms vibration (ngfd event, W3-launcher-setup draft)
        Haptics.play("eos_setup_complete")
        done()
    }

    // ---- the display policy ----
    property real lastActivity: 0
    property real armedAt: 0

    // a setup screen opened or was touched: hold the display on for 360 s from now
    function activity() {
        lastActivity = Date.now()
        if (!displayOn || finished)
            return
        if (!held) {
            held = true
            firstRun.keepScreenOn(true)
        }
        screenTimerObj.restart()
    }
    // mce is holding the display on for us
    property bool held: false
    Timer {
        id: screenTimerObj
        objectName: "setupScreenTimer"
        interval: Setup.screenOnSeconds * 1000
        onTriggered: {
            config.held = false
            firstRun.keepScreenOn(false)
        }
    }

    // exact wake-up alarm for the idle power-off; 0 cancels
    function updatePowerOff(force) {
        var now = Date.now()
        if (!force && !Setup.rearm(now, armedAt))
            return
        var s = Setup.powerOffSeconds(charging, finished || bonded)
        armedAt = s > 0 ? now : 0
        firstRun.armIdlePowerOff(s)
    }
    onChargingChanged: updatePowerOff(true)

    // the display went dark: stop holding it; it came back: hold again, and the pairing pages start again
    // at the first screen unless a code is showing
    onDisplayOnChanged: {
        if (!displayOn) {
            screenTimerObj.stop()
            held = false
            firstRun.keepScreenOn(false)
        } else {
            activity()
            if (!codeUp && !bonded && !finished
                    && (page === Setup.pages.language || page === Setup.pages.instructions || page === Setup.pages.help))
                replaceAll(Setup.pages.first)
        }
    }

    // the low battery gate ends when the level is 20 % or more (by the battery signal)
    onLevelChanged: {
        if (page === Setup.pages.charge && !Setup.gateNeeded(level, batteryLevel.valid))
            replaceAll(Setup.pages.first)
    }

    // a touch is somebody being there (passive: it takes nothing from the pages)
    PointHandler {
        acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Mouse
        grabPermissions: PointerHandler.ApprovesTakeOverByAnything
        onActiveChanged: if (active) { config.activity(); config.updatePowerOff(false) }
    }
}
