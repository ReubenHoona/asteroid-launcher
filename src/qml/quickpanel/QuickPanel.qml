/*
 * Copyright (C) 2025 Timo Könnecke <github.com/eLtMosen>
 *               2015 Florent Revest <revestflo@gmail.com>
 *               2014 Aleksi Suomalainen <suomalainen.aleksi@gmail.com>
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
import org.asteroid.launcher
import Nemo.Configuration
import Nemo.Mce
import Nemo.DBus
import Nemo.Ngf
import Connman
import "qs.js" as QS
import "tray.js" as TrayRules

/*
 * The quick settings panel, as stock CP3A's (W2-launcher-quick-settings): a
 * vertical list of rows of three buttons (the top row holds count mod 3), the
 * battery button first, the status tray last; it opens showing the bottom of
 * the list; the crown scrolls it and, pushed past its end, closes the tray;
 * the rows shrink and fade at the screen edges. SysUI lah.java, kxx.java,
 * kxr.java; the numbers and where they come from are in qs.js.
 *
 * The buttons: QuickPanelToggle.qml. The questions before a mode comes on:
 * ModeDialog.qml. The status pill and its popups: StatusTray.qml.
 *
 * Which tiles: /desktop/asteroid/quickpanel/tiles (a list of ids; unset is
 * stock's list, QS.DEFAULT_TILES). The older fixed / slider / enabled keys of
 * the editor are no longer read: stock has no editor (DECISIONS Q30).
 * Nothing here polls: the pill and the battery button follow signals.
 */
Item {
    id: rootitem
    width: parent.width
    height: parent.height

    property bool forbidLeft: true
    property bool forbidRight: true

    // sizes, px (stock dp x Theme.dp)
    readonly property real tileSize: Theme.dp(52)
    readonly property real tileGap: Theme.dp(4)
    readonly property real rowSpacing: Theme.dp(4)
    readonly property real topPadding: Theme.dp(20)
    /*! A second tap on a tile within this many ms is ignored (tests set 0). */
    property int tapDebounce: QS.TAP_DEBOUNCE_MS

    // ---- the crown and the tray ------------------------------------------------

    /* The crown pushed past the end of the list closes the tray (stock closes a
     * crown-opened tray at the end of its list): the grid decides (crownScrolled),
     * this item is the receiver RotaryInput finds first. Past the top nothing
     * happens (the end bump plays). */
    signal rotaryExit(int direction)
    property int rotaryExitEdge: grid.rotaryExitEdge === 1 ? 1 : 2
    onRotaryExit: (direction) => { if (grid.crownScrolled) grid.crownScrolled(direction) }

    /*! The list a drag is handed over to the tray from (PanelsGrid nested scroll): at its end, the finger going up. */
    readonly property Item handOverView: list

    MceBatteryLevel { id: batteryChargePercentage }
    MceChargerType { id: mceChargerType }

    readonly property int volume: volumeControl ? (volumeControl.maximumVolume ? Math.round((volumeControl.volume / volumeControl.maximumVolume) * 100) : 0) : 0

    function setVolume(volume) {
        volumeControl.volume = Math.round((volume / 100) * volumeControl.maximumVolume);
    }

    readonly property bool isCharging: mceChargerType.type != MceChargerType.None
    readonly property bool modesReady: typeof modes !== "undefined" && modes !== null
    // the charger, as the modes engine sees it (it turns the saver off there)
    readonly property bool charging: modesReady ? modes.charging : isCharging
    readonly property bool saverOn: modesReady && modes.batterySaver && !charging
    readonly property bool touchLockAvailable: typeof touchLock !== "undefined" && touchLock !== null && typeof touchLock.lock === "function"
    // the Mobile tile is for a watch with a modem (machine.conf); the state is a key until the modem work reads it
    readonly property bool mobileAvailable: !!DeviceSpecs.hasCellular

    AppLauncher { id: appLauncher }

    ConfigurationValue {
        id: preMuteLevel
        key: "/desktop/asteroid/pre-mute-level"
        defaultValue: 80
    }

    ConfigurationValue {
        id: tilesValue
        key: "/desktop/asteroid/quickpanel/tiles"
        defaultValue: QS.DEFAULT_TILES
    }

    // Settings > Battery > Show percentage (asteroid-settings BatteryPage); on as stock's battery button
    ConfigurationValue {
        id: showBatteryPercent
        key: "/org/asteroidos/quickpanel/show-battery-percent"
        defaultValue: true
    }

    ConfigurationValue {
        id: mobileEnabled
        key: "/org/asteroidos/settings/mobile-enabled"
        defaultValue: true
    }

    // Settings asks for a page with the launcher writing "<page>@<ms>" here (asteroid-settings main.qml openRequested)
    ConfigurationValue {
        id: settingsRequest
        key: "/org/asteroidos/settings/ui/open"
        defaultValue: ""
    }
    function openSettings(page) {
        settingsRequest.value = page + "@" + Date.now()
        appLauncher.launchApp("asteroid-settings")
    }

    DBusInterface {
        id: login1DBus
        bus: DBus.SystemBus
        service: "org.freedesktop.login1"
        path: "/org/freedesktop/login1"
        iface: "org.freedesktop.login1.Manager"
    }
    DBusInterface {
        id: mce_dbus
        service: "com.nokia.mce"
        path: "/com/nokia/mce/request"
        iface: "com.nokia.mce.request"
        bus: DBus.SystemBus
    }

    // a short, crisp click (ui_click, about 20 ms) for the haptics tile
    NonGraphicalFeedback { id: feedback; event: "ui_click" }
    ConfigurationValue {
        id: vibrationEnabled
        key: "/desktop/asteroid/vibration"
        defaultValue: true
    }

    NonGraphicalFeedback {
        id: unmuteSound
        event: "notification"
    }

    NetworkTechnology {
        id: wifiStatus
        path: "/net/connman/technology/wifi"
    }
    NetworkManager { id: connman }
    BluetoothStatus { id: btStatus }

    // ---- the tiles -------------------------------------------------------------

    // which tiles exist on this watch; the ones not in the default list stay for a list that names them
    readonly property var availability: ({
        "battery": true,
        "settingsButton": true,
        "soundToggle": DeviceSpecs.hasSpeaker,
        "bedtimeToggle": true,
        "dndToggle": true,
        "cinemaToggle": true,
        "airplaneToggle": true,
        "flashlightButton": true,
        "brightnessButton": true,
        "touchLockToggle": touchLockAvailable,
        "mobileToggle": mobileAvailable,
        "findPhoneButton": true,
        "lockButton": true,
        "bluetoothToggle": true,
        "hapticsToggle": true,
        "wifiToggle": DeviceSpecs.hasWlan,
        "extraDimToggle": true,
        "aodToggle": true,
        "powerOffToggle": true,
        "rebootToggle": true,
        "musicButton": true
    })

    readonly property var tileIds: QS.visibleTiles(tilesValue.value, availability)
    readonly property var rowIds: QS.rows(tileIds)

    function componentOf(id) {
        switch (id) {
        case "battery": return batteryComponent
        case "settingsButton": return settingsButtonComponent
        case "soundToggle": return soundToggleComponent
        case "bedtimeToggle": return bedtimeToggleComponent
        case "dndToggle": return dndToggleComponent
        case "cinemaToggle": return cinemaToggleComponent
        case "airplaneToggle": return airplaneToggleComponent
        case "flashlightButton": return flashlightButtonComponent
        case "brightnessButton": return brightnessButtonComponent
        case "touchLockToggle": return touchLockComponent
        case "mobileToggle": return mobileToggleComponent
        case "findPhoneButton": return findPhoneButtonComponent
        case "lockButton": return lockButtonComponent
        case "bluetoothToggle": return bluetoothToggleComponent
        case "hapticsToggle": return hapticsToggleComponent
        case "wifiToggle": return wifiToggleComponent
        case "extraDimToggle": return extraDimToggleComponent
        case "aodToggle": return aodToggleComponent
        case "powerOffToggle": return powerOffToggleComponent
        case "rebootToggle": return rebootToggleComponent
        case "musicButton": return musicButtonComponent
        }
        return null
    }

    // ---- the list --------------------------------------------------------------

    function toEnd() {
        list.contentY = Math.max(0, list.contentHeight - list.height)
    }
    // stock scrolls the list to its last item each time the tray moves, so it opens at the bottom
    Connections {
        target: grid
        function onCurrentVerticalPosChanged() {
            if (grid.currentVerticalPos === -1)
                rootitem.toEnd()
        }
        function onTopTrayFractionChanged() {
            if (!list.dragging && !list.flicking && !grid.handingOver)
                rootitem.toEnd()
        }
    }
    Component.onCompleted: {
        toEnd()
        if (visible)
            _everShown = true
    }

    Flickable {
        id: list
        objectName: "qsList"
        anchors.fill: parent
        contentWidth: width
        contentHeight: Math.max(height, col.height)
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        onContentHeightChanged: if (!dragging && !flicking) rootitem.toEnd()

        Column {
            id: col
            objectName: "qsColumn"
            width: list.width
            spacing: rootitem.rowSpacing
            topPadding: rootitem.topPadding + QS.topSpacer(rootitem.rowIds.length > 0 ? rootitem.rowIds[0].length : 3, rootitem.height)

            Repeater {
                model: rootitem.rowIds
                delegate: Item {
                    id: rowItem
                    objectName: "qsRow" + index
                    readonly property var ids: modelData
                    width: col.width
                    height: rootitem.tileSize
                    // the row in the viewport, for the edge morph
                    readonly property var m: QS.morph(y - list.contentY, height, list.height)

                    Repeater {
                        model: rowItem.ids
                        delegate: Loader {
                            id: tileLoader
                            objectName: "qsSlot-" + modelData
                            readonly property string tileId: modelData
                            width: rootitem.tileSize
                            height: width
                            x: QS.sidePadding(rowItem.ids.length, rowItem.width, rootitem.tileSize, rootitem.tileGap)
                               + index * (rootitem.tileSize + rootitem.tileGap)
                               + QS.slide(index, rowItem.ids.length, rootitem.tileSize, rowItem.m.scale)
                            scale: rowItem.m.scale
                            sourceComponent: rootitem.componentOf(modelData)
                            Binding { target: tileLoader.item; property: "containerAlpha"; value: rowItem.m.container; when: tileLoader.item !== null }
                            Binding { target: tileLoader.item; property: "contentAlpha"; value: rowItem.m.content; when: tileLoader.item !== null }
                            Binding { target: tileLoader.item; property: "debounce"; value: rootitem.tapDebounce; when: tileLoader.item !== null }
                        }
                    }
                }
            }

            // the status tray: a box 21.8 % of the height, the pill bottom-centred with 5.2 % under it
            Item {
                id: statusBox
                width: col.width
                height: Math.max(QS.statusBoxHeight(rootitem.height), list.height - y)
                StatusTray {
                    id: statusTray
                    objectName: "statusTray"
                    dialogHost: rootitem
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: QS.statusBottomPadding(rootitem.height)
                    phoneKnown: findPhone.known
                    phoneConnected: findPhone.connected
                    btPowered: btStatus.powered
                    wifiConnected: wifiStatus.powered && wifiStatus.connected
                    wifiName: connman.connectedWifi ? connman.connectedWifi.name : ""
                    alarmMs: rootitem.nextAlarmMs
                    scale: QS.pillScale((statusBox.y - list.contentY + statusBox.height - QS.statusBottomPadding(rootitem.height) - height / 2) / Math.max(1, list.height))
                    onSettingsRequested: (page) => rootitem.openSettings(page)
                }
            }
        }
    }

    // the next alarm for the pill: read when the panel is shown and when the alarms change
    // (timed's signals; no timer). The source is made the first time the panel is shown.
    property bool _everShown: false
    readonly property real nextAlarmMs: clockLoader.item ? clockLoader.item.nextAlarmMs : 0
    Loader {
        id: clockLoader
        active: rootitem._everShown
        source: "complications/ClockSource.qml"
        onLoaded: item.active = Qt.binding(function () { return rootitem.visible })
    }
    onVisibleChanged: {
        if (visible) {
            _everShown = true
            if (clockLoader.item) {
                clockLoader.item.now = new Date()
                clockLoader.item.refresh()
            }
        }
    }

    // ---- the questions and the caption -------------------------------------------

    /*
     * The modes, as the stock quick settings (STOCK-MODES.md): the launcher's modes
     * engine (modes.h) does what each changes. Bedtime, Theater, Battery saver, the
     * first Do Not Disturb and Airplane mode ask first, with "Don't show again";
     * turning one off is at once. "cinemaToggle" keeps its id (saved panels) and
     * is Theater mode.
     */
    ConfigurationValue { id: askDnd; key: "/org/asteroidos/modes/ask/do-not-disturb"; defaultValue: true }
    ConfigurationValue { id: askBedtime; key: "/org/asteroidos/modes/ask/bedtime"; defaultValue: true }
    ConfigurationValue { id: askTheater; key: "/org/asteroidos/modes/ask/theater"; defaultValue: true }
    ConfigurationValue { id: askBatterySaver; key: "/org/asteroidos/modes/ask/battery-saver"; defaultValue: true }
    ConfigurationValue { id: askAirplane; key: "/org/asteroidos/modes/ask/airplane"; defaultValue: true }

    // ask (a ConfigurationValue: with "Don't show again", or null: no such row); apply runs on yes
    function askFirst(ask, title, message, apply, iconName) {
        if (ask && !ask.value) {
            apply()
            return
        }
        modeDialog.ask(title, message, function (dontShowAgain) {
            if (ask && dontShowAgain)
                ask.value = false
            apply()
        }, iconName, ask !== null)
    }

    ModeDialog { id: modeDialog; objectName: "modeDialog" }

    /* The state caption after Do Not Disturb, Theater, Notifications and ring, Airplane
     * mode and Mobile change (SysUI kzp.java, qss2_toggle_overlay.xml): bodySmall (12 sp)
     * centred between 24 % and 76 % of the width, 6 % of the width above the bottom,
     * over a black gradient (#FF000000, #FF000000, #1E000000) rising 41 sp (65 sp for
     * more than two lines) above the margin. In 375 ms (PathInterpolator 0.4, 0, 1, 1),
     * 3000 ms, out 375 ms; a new text crosses over, 150 ms out and 225 ms in after a
     * 150 ms delay. */
    Item {
        id: caption
        objectName: "qsCaption"
        property string text: ""
        property string _next: ""
        readonly property real margin: QS.CAPTION.bottomFraction * rootitem.width
        // the gradient rises 41 sp (65 sp for more than two lines) above the margin and the text
        readonly property real gradientHeight: margin + captionLabel.height
                                               + Theme.dp(captionLabel.lineCount > 2 ? QS.CAPTION.gradientLongDp : QS.CAPTION.gradientDp)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: gradientHeight
        z: 950
        visible: opacity > 0
        opacity: 0
        enabled: false

        function show(message) {
            if (message === "")
                return
            if (visible && opacity > 0.01 && text !== message) {
                // a new text while one shows: it crosses over
                _next = message
                hold.stop()
                fadeInOut.stop()
                swap.restart()
                return
            }
            text = message
            captionLabel.opacity = 1
            swap.stop()
            hold.stop()
            fadeOutAnim.stop()
            fadeInOut.restart()
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: caption.gradientHeight
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#1E000000" }
                GradientStop { position: 0.5; color: "#FF000000" }
                GradientStop { position: 1.0; color: "#FF000000" }
            }
        }
        Label {
            id: captionLabel
            objectName: "qsCaptionText"
            x: QS.CAPTION.widthFrom * rootitem.width
            width: (QS.CAPTION.widthTo - QS.CAPTION.widthFrom) * rootitem.width
            anchors.bottom: parent.bottom
            anchors.bottomMargin: caption.margin
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            role: "bodySmall"
            text: caption.text
            color: Theme.color.onBackground
        }

        SequentialAnimation {
            id: fadeInOut
            NumberAnimation {
                target: caption; property: "opacity"; to: 1
                duration: Motion.duration(QS.CAPTION.fadeIn)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [QS.CAPTION.easing[0], QS.CAPTION.easing[1], QS.CAPTION.easing[2], QS.CAPTION.easing[3], 1, 1]
            }
            PauseAnimation { duration: Motion.duration(QS.CAPTION.hold) }
            NumberAnimation {
                target: caption; property: "opacity"; to: 0
                duration: Motion.duration(QS.CAPTION.fadeOut)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [QS.CAPTION.easing[0], QS.CAPTION.easing[1], QS.CAPTION.easing[2], QS.CAPTION.easing[3], 1, 1]
            }
        }
        SequentialAnimation {
            id: swap
            NumberAnimation { target: captionLabel; property: "opacity"; to: 0; duration: Motion.duration(QS.CAPTION.swapOut) }
            ScriptAction { script: caption.text = caption._next }
            PauseAnimation { duration: Motion.duration(QS.CAPTION.swapDelay - QS.CAPTION.swapOut > 0 ? QS.CAPTION.swapDelay - QS.CAPTION.swapOut : 0) }
            NumberAnimation { target: captionLabel; property: "opacity"; to: 1; duration: Motion.duration(QS.CAPTION.swapIn) }
            // the hold starts again for the new text
            ScriptAction { script: hold.restart() }
        }
        Timer {
            id: hold
            interval: Motion.duration(QS.CAPTION.hold)
            onTriggered: fadeOutAnim.start()
        }
        NumberAnimation {
            id: fadeOutAnim
            target: caption; property: "opacity"; to: 0
            duration: Motion.duration(QS.CAPTION.fadeOut)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [QS.CAPTION.easing[0], QS.CAPTION.easing[1], QS.CAPTION.easing[2], QS.CAPTION.easing[3], 1, 1]
        }
    }
    function showCaption(message) { caption.show(message) }

    // after Theater mode or Touch lock the tray closes 700 ms later (Touch lock without animation)
    property bool _closeInstantly: false
    Timer {
        id: autoClose
        interval: QS.AUTO_CLOSE_MS
        onTriggered: {
            if (rootitem._closeInstantly)
                grid.moveTo(0, 0)
            else if (grid.trayMode)
                grid.closeTray(TrayRules.REASON.nonDrag)
            else
                grid.animateTo(0, 0)
        }
    }
    function closeSoon(instantly) {
        _closeInstantly = instantly
        autoClose.restart()
    }

    // ---- the tiles' components ---------------------------------------------------

    // the battery button (kxx.java:293-347, kxb.java:36-190): the first button
    Component {
        id: batteryComponent
        QuickPanelToggle {
            id: bt
            objectName: "batteryButton"
            readonly property int percent: batteryChargePercentage.percent
            readonly property int step: QS.batteryStep(percent)
            checkable: true
            checked: rootitem.saverOn
            // plugged in: the button is greyed out (stock disables it)
            enabled: !rootitem.charging
            iconSize: Theme.dp(32)
            checkedContainer: QS.SAVER_CONTAINER
            checkedContent: QS.SAVER_CONTENT
            tinted: QS.batteryLow(percent)
            label: QS.batteryDescription(percent, rootitem.saverOn, rootitem.charging, {
                //% "Battery %1%."
                battery: qsTrId("id-qs-a11y-battery"),
                //% "Charging."
                charging: qsTrId("id-qs-a11y-charging"),
                //% "Battery saver on."
                saverOn: qsTrId("id-qs-a11y-saver-on"),
                //% "Battery saver off."
                saverOff: qsTrId("id-qs-a11y-saver-off")
            })

            // the glyph, 32 x 14 dp, filled to the level; own design
            Item {
                id: glyph
                objectName: "batteryGlyph"
                width: Theme.dp(32)
                height: Theme.dp(14)
                x: (parent.width - width) / 2
                y: parent.height / 2 - Theme.dp(15)
                readonly property real bodyWidth: width - Theme.dp(3)
                Rectangle {
                    id: body
                    width: glyph.bodyWidth
                    height: glyph.height
                    radius: Theme.dp(3.5)
                    color: "transparent"
                    border.width: Theme.dp(1.5)
                    border.color: bt.contentColor
                }
                Rectangle {
                    x: glyph.bodyWidth
                    y: (glyph.height - height) / 2
                    width: Theme.dp(2.5)
                    height: Theme.dp(6)
                    radius: Theme.dp(1)
                    color: bt.contentColor
                }
                Rectangle {
                    objectName: "batteryFill"
                    x: Theme.dp(3.5)
                    y: Theme.dp(3.5)
                    width: Math.max(Theme.dp(2), (glyph.bodyWidth - Theme.dp(7)) * bt.step / 100)
                    height: glyph.height - Theme.dp(7)
                    radius: Theme.dp(1.5)
                    color: bt.contentColor
                    visible: !rootitem.charging
                }
                Icon {
                    objectName: "batteryBolt"
                    visible: rootitem.charging
                    anchors.centerIn: body
                    width: Theme.dp(12)
                    height: width
                    name: "ios-flash"
                    color: bt.contentColor
                }
            }
            // the percent under it: digits 15 dp, "%" 10 dp, shifted +2 dp x and -8 dp y
            Row {
                id: percentRow
                objectName: "batteryPercent"
                visible: showBatteryPercent.value !== false
                x: (parent.width - width) / 2 + Theme.dp(2)
                y: glyph.y + glyph.height + Theme.dp(1)
                spacing: 0
                Label {
                    objectName: "batteryDigits"
                    text: bt.percent
                    font.pixelSize: Theme.dp(15)
                    font.weight: Font.DemiBold
                    color: bt.contentColor
                }
                Label {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Theme.dp(1)
                    text: "%"
                    font.pixelSize: Theme.dp(10)
                    color: bt.contentColor
                }
            }

            onActivated: {
                if (!rootitem.modesReady)
                    return
                if (checked) {
                    // saver on -> off at once
                    modes.batterySaver = false
                    return
                }
                //% "Turn on Battery Saver mode?"
                rootitem.askFirst(askBatterySaver, qsTrId("id-saver-confirm-title"),
                         // stock battery_saver_mode_dialog_message and, with the automatic
                         // saver on, battery_saver_mode_with_absm_dialog_message
                         rootitem.modesReady && modes.autoSaverOn
                         //% "Limits background activity and turns off always-on-screen. When needed, GPS will be used from the phone. Automatically turns on at %1%."
                         ? qsTrId("id-saver-confirm-auto").arg(modes.autoSaverOnLevel)
                         //% "Limits background activity and turns off always-on-screen. When needed, GPS will be used from the phone."
                         : qsTrId("id-saver-confirm"),
                         function () { modes.batterySaver = true }, "ms-battery_saver")
            }
            onLongPressed: rootitem.openSettings("battery_saver")
        }
    }

    Component {
        id: settingsButtonComponent
        QuickPanelToggle {
            objectName: "settingsButton"
            icon: "ios-settings"
            //% "Settings"
            label: qsTrId("id-qs-settings")
            onActivated: appLauncher.launchApp("asteroid-settings")
        }
    }

    // Notifications and ring (kxx.java:358-369, 704-730): checked = not muted
    Component {
        id: soundToggleComponent
        QuickPanelToggle {
            id: soundToggle
            objectName: "soundToggle"
            checkable: true
            //% "Notifications and ring"
            label: qsTrId("id-qs-sound")

            icon: preMuteLevel.value > 0 || volume === 0 ? "ios-sound-indicator-mute" :
                  volume > 70 ? "ios-sound-indicator-high" :
                  volume > 30 ? "ios-sound-indicator-mid" :
                  volume > 0 ? "ios-sound-indicator-low" : "ios-sound-indicator-off"

            // checked reflects mute state only: volume at 0% while unmuted
            // is silent but not muted and should not deactivate the toggle
            checked: !(preMuteLevel.value > 0 || volume === 0)

            onActivated: {
                const tempVolume = volume
                let targetVolume = preMuteLevel.value
                if (tempVolume === 0 && targetVolume === 0) targetVolume = 100
                setVolume(targetVolume)
                preMuteLevel.value = tempVolume
                if (targetVolume > 0) soundDelayTimer.start()
                rootitem.showCaption(targetVolume > 0
                    //% "Ring & notifications on"
                    ? qsTrId("id-qs-sound-on")
                    //% "Ring & notifications off"
                    : qsTrId("id-qs-sound-off"))
            }
            onLongPressed: rootitem.openSettings("sound")

            Timer {
                id: soundDelayTimer
                interval: 150
                repeat: false
                onTriggered: unmuteSound.play()
            }
        }
    }

    Component {
        id: bedtimeToggleComponent
        QuickPanelToggle {
            objectName: "bedtimeToggle"
            icon: checked ? "ios-moon" : "ios-moon-outline"
            checkable: true
            checked: rootitem.modesReady && modes.bedtime
            //% "Bedtime mode"
            label: qsTrId("id-qs-bedtime")
            onActivated: {
                if (checked) {
                    // off at once; with the screen on and the home screen
                    // up ModeScreen shows "Turning off Bedtime mode…" (the
                    // engine's bedtimeEnding), no caption (stock has none)
                    modes.bedtime = false
                    return
                }
                //% "Turn on Bedtime mode?"
                rootitem.askFirst(askBedtime, qsTrId("id-bedtime-confirm-title"),
                         //% "Wind down for sleep.\n\nOnly selected sources such as alarms will reach you. Turns off watch screen wake gestures, and reduces brightness."
                         qsTrId("id-bedtime-confirm"),
                         function () { modes.bedtime = true }, "ios-moon")
            }
            onLongPressed: rootitem.openSettings("bedtime")
        }
    }

    Component {
        id: cinemaToggleComponent
        QuickPanelToggle {
            objectName: "theaterToggle"
            icon: checked ? "ios-film" : "ios-film-outline"
            checkable: true
            checked: rootitem.modesReady && modes.theater
            //% "Theater mode"
            label: qsTrId("id-qs-theater")
            onActivated: {
                if (checked) {
                    modes.theater = false
                    //% "Theater mode off"
                    rootitem.showCaption(qsTrId("id-qs-theater-off"))
                    return
                }
                //% "Turn on Theater mode?"
                rootitem.askFirst(askTheater, qsTrId("id-theater-confirm-title"),
                         //% "Silences everything including alarms.\n\nTurns off screen and wake gestures completely."
                         qsTrId("id-theater-confirm"),
                         function () {
                             modes.theater = true
                             //% "Theater mode on"
                             rootitem.showCaption(qsTrId("id-qs-theater-on"))
                             // the tray closes 700 ms later
                             rootitem.closeSoon(false)
                         }, "ios-film")
            }
            onLongPressed: rootitem.openSettings("theater")
        }
    }

    // Do Not Disturb: phone notifications arrive without banner or vibration
    // (alarms still ring); asteroid-btsyncd follows this key and syncs it with
    // the phone's Do Not Disturb
    ConfigurationValue {
        id: doNotDisturb
        key: "/org/asteroidos/notifications/do-not-disturb"
        defaultValue: false
    }

    Component {
        id: dndToggleComponent
        QuickPanelToggle {
            objectName: "dndToggle"
            // stock's do-not-disturb-on circle; the moon is Bedtime's
            icon: checked ? "ios-remove-circle" : "ios-remove-circle-outline"
            checkable: true
            checked: doNotDisturb.value
            //% "Do Not Disturb"
            label: qsTrId("id-qs-dnd")
            onActivated: {
                if (checked) {
                    doNotDisturb.value = false
                    //% "Do Not Disturb off"
                    rootitem.showCaption(qsTrId("id-qs-dnd-off"))
                    return
                }
                //% "Turn on Do Not Disturb?"
                rootitem.askFirst(askDnd, qsTrId("id-dnd-confirm-title"),
                         //% "Silences watch to minimize interruptions.\n\nOnly selected people and apps can reach you."
                         qsTrId("id-dnd-confirm"),
                         function () {
                             doNotDisturb.value = true
                             //% "Do Not Disturb on"
                             rootitem.showCaption(qsTrId("id-qs-dnd-on"))
                         }, "ios-remove-circle")
            }
            onLongPressed: rootitem.openSettings("dnd")
        }
    }

    // Airplane mode (equ.java cases 3-4, kxx.java:229-243): connman's offline mode
    // turns the radios off. Stock: Bluetooth stays on during airplane mode
    // (bluetooth_airplane_mode_toast), so it is switched back on after.
    Timer {
        id: restoreBluetooth
        interval: 1500
        onTriggered: if (connman.offlineMode && !btStatus.powered) btStatus.powered = true
    }
    property bool _btWasOn: false
    Component {
        id: airplaneToggleComponent
        QuickPanelToggle {
            objectName: "airplaneToggle"
            icon: "ms-airplanemode_active"
            checkable: true
            checked: connman.offlineMode
            //% "Airplane mode"
            label: qsTrId("id-qs-airplane")
            onActivated: {
                if (checked) {
                    connman.offlineMode = false
                    //% "Airplane mode off"
                    rootitem.showCaption(qsTrId("id-qs-airplane-off"))
                    return
                }
                //% "Turn on Airplane mode?"
                rootitem.askFirst(askAirplane, qsTrId("id-qs-airplane-title"),
                         //% "When airplane mode is on, Wi-Fi and mobile networks are turned off"
                         qsTrId("id-qs-airplane-message"),
                         function () {
                             rootitem._btWasOn = btStatus.powered
                             connman.offlineMode = true
                             if (rootitem._btWasOn)
                                 restoreBluetooth.restart()
                             //% "Airplane mode on"
                             rootitem.showCaption(qsTrId("id-qs-airplane-on"))
                         }, "ms-airplanemode_active")
            }
            // there is no Airplane page in Settings: the info dialog
            onLongPressed: modeDialog.info(qsTrId("id-qs-airplane"), qsTrId("id-qs-airplane-message"), "ms-airplanemode_active")
        }
    }

    // Flashlight: opens the Flashlight app, as the stock quick settings'
    // Flashlight button starts FlashlightActivity (STOCK-FLASHLIGHT.md); its
    // icon is the stock tile's (quantum_gm_ic_flashlight_on)
    Component {
        id: flashlightButtonComponent
        QuickPanelToggle {
            objectName: "flashlightButton"
            icon: "gm-flashlight-on"
            iconSize: Theme.dp(27)
            //% "Flashlight"
            label: qsTrId("id-qs-flashlight")
            onActivated: appLauncher.launchApp("asteroid-flashlight")
            onLongPressed: modeDialog.info(qsTrId("id-qs-flashlight"),
                                           //% "Lights up your watch screen"
                                           qsTrId("id-qs-flashlight-info"), "gm-flashlight-on")
        }
    }

    // Brightness: the tap opens the Settings Brightness page (wake-sleep-display-14; stock
    // BrightnessTileUserActionInteractor); no long press
    Component {
        id: brightnessButtonComponent
        QuickPanelToggle {
            objectName: "brightnessButton"
            icon: "ios-sunny"
            //% "Brightness"
            label: qsTrId("id-brightness")
            onActivated: rootitem.openSettings("brightness")
        }
    }

    // Touch lock: the power system's lock (W2-launcher-power-system) once it is there
    Component {
        id: touchLockComponent
        QuickPanelToggle {
            objectName: "touchLockToggle"
            icon: "ms-screen_lock_portrait"
            //% "Touch lock"
            label: qsTrId("id-qs-touch-lock")
            onActivated: {
                // stock asks first: 'Turn on Touch lock?' (touch_lock_dialog_title and _message)
                //% "Turn on Touch lock?"
                rootitem.askFirst(null, qsTrId("id-touch-lock-confirm-title"),
                                  //% "Turns off touch screen. Press & hold crown for 2 sec. to turn it back on."
                                  qsTrId("id-touch-lock-confirm"),
                                  function () {
                                      touchLock.lock()
                                      // the tray closes 700 ms later, without animation
                                      rootitem.closeSoon(true)
                                  }, "ms-screen_lock_portrait")
            }
            onLongPressed: rootitem.openSettings("touch_lock")
        }
    }

    // Mobile (kxx.java:381-395): off -> on at once; on -> asks first. The state is a
    // key; the modem is not touched (DECISIONS Q61: it waits for the LTE milestone).
    Component {
        id: mobileToggleComponent
        QuickPanelToggle {
            objectName: "mobileToggle"
            icon: "ios-radio-outline"
            checkable: true
            checked: mobileEnabled.value
            //% "Mobile"
            label: qsTrId("id-qs-mobile")
            onActivated: {
                if (!checked) {
                    mobileEnabled.value = true
                    //% "Mobile auto"
                    rootitem.showCaption(qsTrId("id-qs-mobile-on"))
                    return
                }
                //% "Turn off mobile networks?"
                rootitem.askFirst(null, qsTrId("id-qs-mobile-title"),
                         //% "Calls, messages, and mobile data will not be available when watch is disconnected from phone."
                         qsTrId("id-qs-mobile-message"),
                         function () {
                             mobileEnabled.value = false
                             //% "Mobile off"
                             rootitem.showCaption(qsTrId("id-qs-mobile-off"))
                         }, "ios-radio-outline")
            }
            onLongPressed: rootitem.openSettings("connectivity")
        }
    }

    // Find my phone: asteroid-btsyncd asks the phone (Gadgetbridge) to ring;
    // it stops when tapped again, when found on the phone, or after a while
    Item {
        id: findPhone
        property bool ringing: false

        function toggle() {
            var start = !ringing
            findPhoneDBus.typedCall("FindPhone", [{ "type": "b", "value": start }],
                                    function (ok) {
                                        if (start && !ok)
                                            findPhoneNoPhone.show()
                                        else
                                            findPhone.ringing = start
                                    },
                                    function () { if (start) findPhoneNoPhone.show() })
        }

        DBusInterface {
            id: findPhoneDBus
            bus: DBus.SessionBus
            service: "org.asteroidos.btsyncd"
            path: "/org/asteroidos/btsyncd/notifications"
            iface: "org.asteroidos.btsyncd.Notifications"
            signalsEnabled: true

            function rcFindPhoneChanged(ringing: bool) {
                findPhone.ringing = ringing
            }
        }

        Component.onCompleted: {
            findPhoneDBus.typedCall("FindingPhone", [],
                                    function (r) { findPhone.ringing = r },
                                    function () { findPhone.ringing = false })
            phoneDBus.typedCall("Connected", [], function (c) { findPhone.connected = c; findPhone.known = true })
        }

        // The phone's link (asteroid-btsyncd's phone status): the pill's phone icon and
        // the Find my phone tile's enabled state; `known` once btsyncd has answered
        property bool connected: false
        property bool known: false

        DBusInterface {
            id: phoneDBus
            bus: DBus.SessionBus
            service: "org.asteroidos.btsyncd"
            path: "/org/asteroidos/btsyncd/phone"
            iface: "org.asteroidos.btsyncd.Phone"
            signalsEnabled: true

            function rcConnectedChanged(connected: bool) {
                findPhone.connected = connected
                findPhone.known = true
            }
        }
    }

    Label {
        id: findPhoneNoPhone
        function show() {
            visible = true
            findPhoneNoPhoneTimer.restart()
        }
        visible: false
        z: 10
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.dp(60)
        color: Theme.color.error
        font.pixelSize: Theme.type.bodySmall.pixelSize
        // The voice reply page's string
        text: qsTrId("id-voice-no-phone")
        Timer {
            id: findPhoneNoPhoneTimer
            interval: 2500
            onTriggered: findPhoneNoPhone.visible = false
        }
    }

    // Find My Phone (krv.java cases 17-18): greyed out while the phone is not connected
    Component {
        id: findPhoneButtonComponent
        QuickPanelToggle {
            objectName: "findPhoneButton"
            icon: "ios-phone-portrait"
            iconSize: Theme.dp(32)
            checkable: true
            checked: findPhone.ringing
            enabled: findPhone.connected
            //% "Find My Phone"
            label: qsTrId("id-qs-find-phone")
            onActivated: findPhone.toggle()
            onLongPressed: modeDialog.info(qsTrId("id-qs-find-phone"),
                                           //% "Rings your phone even when the phone is muted or on vibrate"
                                           qsTrId("id-qs-find-phone-info"), "ios-phone-portrait")

            // Ringing: the icon pulses, only while the panel is on screen
            SequentialAnimation on opacity {
                running: findPhone.ringing && rootitem.visible
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 0.5; duration: 500; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1.0; duration: 500; easing.type: Easing.InOutQuad }
            }
        }
    }

    // ---- tiles that are not in stock's list: only a list that names them shows them ----

    Component {
        id: lockButtonComponent
        QuickPanelToggle {
            icon: "ios-unlock"
            onActivated: mce_dbus.call("req_display_state_lpm", undefined)
        }
    }

    Component {
        id: musicButtonComponent
        QuickPanelToggle {
            icon: "ios-musical-notes-outline"
            onActivated: appLauncher.launchApp("asteroid-music")
        }
    }

    Component {
        id: hapticsToggleComponent
        QuickPanelToggle {
            objectName: "hapticsToggle"
            icon: "ios-watch-vibrating"
            checkable: true
            // the master "Vibration & haptics": the crown ticks need it and haptics-crown;
            // this tile never writes haptics-crown (choice-settings-13)
            checked: vibrationEnabled.value

            onActivated: {
                if (checked) {
                    vibrationEnabled.value = false
                } else {
                    vibrationEnabled.value = true;
                    feedbackDelayTimer.start();
                }
            }

            Timer {
                id: feedbackDelayTimer
                interval: 125
                repeat: false
                onTriggered: feedback.play()
            }
        }
    }

    Component {
        id: wifiToggleComponent
        QuickPanelToggle {
            icon: wifiStatus.connected ? "ios-wifi" : "ios-wifi-outline"
            checkable: true
            checked: wifiStatus.powered
            onActivated: wifiStatus.powered = !checked
        }
    }

    Component {
        id: bluetoothToggleComponent
        QuickPanelToggle {
            icon: btStatus.connected ? "ios-bluetooth-connected" : "ios-bluetooth"
            checkable: true
            checked: btStatus.powered
            onActivated: btStatus.powered = !checked
        }
    }

    // Extra dim: this watch's own (Android's on the phone cannot be read):
    // the screen under the lowest brightness, at once as Android's tile
    Component {
        id: extraDimToggleComponent
        QuickPanelToggle {
            objectName: "extraDimToggle"
            icon: "ios-contrast"
            checkable: true
            checked: rootitem.modesReady && modes.extraDim
            onActivated: modes.extraDim = !checked
        }
    }

    // Always-on: writes only the key; the launcher's applyLowPower() turns the low power
    // mode on and off, so the off-wrist rule and the holds stay in one place
    // (choice-settings-13)
    Component {
        id: aodToggleComponent
        QuickPanelToggle {
            objectName: "aodToggle"
            readonly property bool blocked: rootitem.modesReady && modes.alwaysOnBlocked
            icon: checked ? "ios-watch-aod-on" : "ios-watch-aod-off"
            checkable: true
            enabled: !blocked
            checked: alwaysOnDisplay.value && !blocked
            onActivated: alwaysOnDisplay.value = !checked
        }
    }

    // Power off and Restart ask "Are you sure?" (stock's power entries; DECISIONS Q31).
    // One dialog with one pending answer: asking again replaces it (the old
    // RemorseTimer connected a handler for every tap, dialogs-pickers-feedback-20).
    Component {
        id: powerOffToggleComponent
        QuickPanelToggle {
            objectName: "powerOffToggle"
            icon: "ios-power-outline"
            onActivated: {
                //% "Power off"
                rootitem.askFirst(null, qsTrId("id-power-off"),
                                  //% "Are you sure?"
                                  qsTrId("id-qs-are-you-sure"),
                                  function () { login1DBus.call("PowerOff", [false]) }, "ios-power-outline")
            }
        }
    }

    Component {
        id: rebootToggleComponent
        QuickPanelToggle {
            objectName: "rebootToggle"
            icon: "ios-sync"
            onActivated: {
                //% "Restart device?"
                rootitem.askFirst(null, qsTrId("id-qs-restart-title"),
                                  qsTrId("id-qs-are-you-sure"),
                                  function () {
                                      login1DBus.call("SetRebootParameter", [""])
                                      login1DBus.call("Reboot", [false])
                                  }, "ios-sync")
            }
        }
    }
}
