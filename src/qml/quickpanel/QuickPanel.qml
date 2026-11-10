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
import Qt5Compat.GraphicalEffects
import org.asteroid.controls
import org.asteroid.utils
import org.asteroid.launcher
import org.asteroid.settings
import Nemo.Configuration
import Nemo.Mce
import Nemo.DBus
import Nemo.Ngf
import Connman

Item {
    id: rootitem
    width: parent.width
    height: parent.height

    property bool forbidLeft: true
    property bool forbidRight: true
    property int toggleSize: Dims.l(28)

    // Set true while a range toggle is scrubbing. Single source of truth that
    // drives all simultaneous panel fades via Behavior on opacity bindings.
    property bool activeScrub: false

    // scrubEventGuard stays true for guardTimer interval after scrub ends.
    // The MouseArea on scrubCover uses this to swallow stray touch events that
    // Qt may deliver to underlying toggles after preventStealing is released.
    // This is the primary fix for spurious toggle-on-scrub-release — wasScrubbing
    // in the toggle is a backup for the short-drag case where onClicked fires.
    property bool scrubEventGuard: false

    Timer {
        id: guardTimer
        interval: 250
        onTriggered: scrubEventGuard = false
    }

    // Tracks which toggle is scrubbing so scrubFill and scrubCaptionLabel
    // know which value and string to display
    property string scrubMode: ""

    // scrubRangeWidth defines both the visual scrubber width and the effective
    // input range. The 0.15 margin on each side of rootitem.width matches the
    // margin formula in QuickPanelToggle.updateValue so the visual bar
    // boundaries and finger position always correspond truthfully.
    readonly property real scrubRangeWidth: width * 0.80
    readonly property real scrubCoverHeight: Dims.l(20)

    readonly property real scrubCoverX: (width - scrubRangeWidth) / 2
    readonly property real scrubCoverY: (height - scrubCoverHeight) / 2

    // Stored valueMeter geometry captured at scrub start for symmetric reverse morph
    property real morphStartX: 0
    property real morphStartY: 0
    property real morphStartW: 0
    property real morphStartH: 0
    property color morphStartColor: Qt.rgba(1, 1, 1, 0.3)

    // -- Morph animation orchestration --
    // On scrub start: snapshot valueMeter position, set morphRect there, then
    // animate it to scrubCover geometry while the panel fades out via Behaviors.
    // scrubCover fades in after the morph is nearly complete.
    // On scrub end: reverse — scrubCover fades out, morphRect shrinks back to
    // valueMeter geometry as panel fades back in.
    onActiveScrubChanged: {
        if (activeScrub) {
            scrubEventGuard = true
            guardTimer.stop()
            scrubEndAnim.stop()
            var pos = valueMeter.mapToItem(rootitem, 0, 0)
            morphStartX = pos.x
            morphStartY = pos.y
            morphStartW = valueMeter.width
            morphStartH = valueMeter.height
            morphRect.x = morphStartX
            morphRect.y = morphStartY
            morphRect.width = morphStartW
            morphRect.height = morphStartH
            // onActiveScrubChanged — start morph at valueMeter fillColor
            morphRect.color = Qt.rgba(valueMeter.fillColor.r, valueMeter.fillColor.g, valueMeter.fillColor.b, 1.0)
            morphRect.opacity = valueMeter.fillColor.a
            morphRect.visible = true
            scrubCover.opacity = 0.0
            scrubStartAnim.start()
        } else {
            scrubStartAnim.stop()
            scrubEndAnim.start()
            guardTimer.restart()
        }
    }

    ParallelAnimation {
        id: scrubStartAnim
        NumberAnimation { target: morphRect; property: "opacity"; to: 0.75; duration: 250 }
        NumberAnimation { target: morphRect; property: "x"; to: scrubCoverX; duration: 250; easing.type: Easing.InOutQuad }
        NumberAnimation { target: morphRect; property: "y"; to: scrubCoverY; duration: 250; easing.type: Easing.InOutQuad }
        NumberAnimation { target: morphRect; property: "width"; to: scrubRangeWidth; duration: 250; easing.type: Easing.InOutQuad }
        NumberAnimation { target: morphRect; property: "height"; to: scrubCoverHeight; duration: 250; easing.type: Easing.InOutQuad }
        // Color transitions from valueMeter fill light to scrubCover dark during expand
        ColorAnimation { target: morphRect; property: "color"; to: Qt.rgba(0.13, 0.13, 0.13, 0.75); duration: 250 }
        SequentialAnimation {
            // scrubCover fades in after morphRect has nearly reached final geometry
            PauseAnimation { duration: 150 }
            NumberAnimation { target: scrubCover; property: "opacity"; to: 1.0; duration: 100 }
        }
    }

    SequentialAnimation {
        id: scrubEndAnim
        ParallelAnimation {
            NumberAnimation { target: scrubCover; property: "opacity"; to: 0.0; duration: 100 }
            SequentialAnimation {
                PauseAnimation { duration: 50 }
                ParallelAnimation {
                    NumberAnimation { target: morphRect; property: "x"; to: morphStartX; duration: 250; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: morphRect; property: "y"; to: morphStartY; duration: 250; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: morphRect; property: "width"; to: morphStartW; duration: 250; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: morphRect; property: "height"; to: morphStartH; duration: 250; easing.type: Easing.InOutQuad }
                    ColorAnimation { target: morphRect; property: "color"; to: morphStartColor; duration: 250 }
                    NumberAnimation { target: morphRect; property: "opacity"; to: valueMeter.fillColor.a; duration: 250 }
                }
            }
        }
        ScriptAction { script: morphRect.visible = false }
    }

    MceBatteryLevel { id: batteryChargePercentage }
    MceBatteryState { id: batteryChargeState }
    MceChargerType { id: mceChargerType }

    readonly property int volume: volumeControl ? (volumeControl.maximumVolume ? Math.round((volumeControl.volume / volumeControl.maximumVolume) * 100) : 0) : 0

    function setVolume(volume) {
        volumeControl.volume = Math.round((volume / 100) * volumeControl.maximumVolume);
    }

    readonly property bool isCharging: mceChargerType.type != MceChargerType.None

    AppLauncher { id: appLauncher }

    ConfigurationValue {
        id: preMuteLevel
        key: "/desktop/asteroid/pre-mute-level"
        defaultValue: 80
    }

    ConfigurationValue {
        id: fixedToggles
        key: "/desktop/asteroid/quickpanel/fixed"
        defaultValue: ["lockButton", "settingsButton"]
    }

    ConfigurationValue {
        id: sliderToggles
        key: "/desktop/asteroid/quickpanel/slider"
        defaultValue: ["brightnessToggle", "bluetoothToggle", "hapticsToggle", "wifiToggle", "soundToggle", "bedtimeToggle", "dndToggle", "cinemaToggle", "batterySaverToggle", "extraDimToggle", "aodToggle", "findPhoneButton", "powerOffToggle", "rebootToggle", "musicButton", "flashlightButton"]
    }

    ConfigurationValue {
        id: toggleEnabled
        key: "/desktop/asteroid/quickpanel/enabled"
        defaultValue: {
            "lockButton": true,
            "settingsButton": true,
            "brightnessToggle": true,
            "bluetoothToggle": true,
            "hapticsToggle": true,
            "wifiToggle": true,
            "soundToggle": true,
            "cinemaToggle": true,
            "aodToggle": true,
            "powerOffToggle": true,
            "rebootToggle": true,
            "musicButton": false,
            "flashlightButton": true,
            "findPhoneButton": true,
            "dndToggle": true,
            "bedtimeToggle": true,
            "batterySaverToggle": true,
            "extraDimToggle": true
        }
    }

    ConfigurationValue {
        id: options
        key: "/desktop/asteroid/quickpanel/options"
        defaultValue: {
            "batteryBottom": true,
            "batteryAnimation": true,
            "batteryColored": false,
            "particleDesign": "diamonds"
        }
    }

    DBusInterface {
        id: mce_dbus
        service: "com.nokia.mce"
        path: "/com/nokia/mce/request"
        iface: "com.nokia.mce.request"
        bus: DBus.SystemBus
    }

    DBusInterface {
        id: login1DBus
        bus: DBus.SystemBus
        service: "org.freedesktop.login1"
        path: "/org/freedesktop/login1"
        iface: "org.freedesktop.login1.Manager"
    }

    // a short, crisp click (ui_click, about 20 ms) instead of the 80 ms "press" buzz
    NonGraphicalFeedback { id: feedback; event: "ui_click" }
    ConfigurationValue {
        id: vibrationEnabled
        key: "/desktop/asteroid/vibration"
        defaultValue: true
    }
    DisplaySettings { id: displaySettings }

    NonGraphicalFeedback {
        id: unmuteSound
        event: "notification"
    }

    NetworkTechnology {
        id: wifiStatus
        path: "/net/connman/technology/wifi"
    }

    states: [
        State {
            name: "batteryBottom"
            when: options.value.batteryBottom

            AnchorChanges {
                target: fixedRow
                anchors.top: undefined
                anchors.bottom: slidingRow.top
            }
            PropertyChanges {
                target: fixedRow
                anchors.topMargin: 0
                anchors.bottomMargin: 0
            }

            AnchorChanges {
                target: valueMeter
                anchors.top: slidingRow.bottom
                anchors.bottom: undefined
            }
            PropertyChanges {
                target: valueMeter
                anchors.topMargin: Dims.l(12)
                anchors.bottomMargin: 0
            }

            AnchorChanges {
                target: valueMeterCaption
                anchors.top: valueMeter.bottom
                anchors.bottom: undefined
            }
            PropertyChanges {
                target: valueMeterCaption
                anchors.topMargin: Dims.l(1)
                anchors.bottomMargin: 0
            }

            AnchorChanges {
                target: pageDots
                anchors.top: slidingRow.bottom
                anchors.bottom: undefined
            }
            PropertyChanges {
                target: pageDots
                anchors.topMargin: Dims.l(4)
                anchors.bottomMargin: 0
            }
        },
        State {
            name: "batteryTop"
            when: !options.value.batteryBottom

            AnchorChanges {
                target: fixedRow
                anchors.top: slidingRow.bottom
                anchors.bottom: undefined
            }
            PropertyChanges {
                target: fixedRow
                anchors.topMargin: Dims.l(4)
                anchors.bottomMargin: 0
            }

            AnchorChanges {
                target: valueMeter
                anchors.top: undefined
                anchors.bottom: slidingRow.top
            }
            PropertyChanges {
                target: valueMeter
                anchors.topMargin: 0
                anchors.bottomMargin: Dims.l(12)
            }

            AnchorChanges {
                target: valueMeterCaption
                anchors.top: undefined
                anchors.bottom: valueMeter.top
            }
            PropertyChanges {
                target: valueMeterCaption
                anchors.topMargin: 0
                anchors.bottomMargin: Dims.l(1)
            }

            AnchorChanges {
                target: pageDots
                anchors.top: undefined
                anchors.bottom: slidingRow.top
            }
            PropertyChanges {
                target: pageDots
                anchors.topMargin: 0
                anchors.bottomMargin: Dims.l(4)
            }
        }
    ]

    // (the Flashlight tile too: stock's quick settings have it by default)
    readonly property var newToggles: ["findPhoneButton", "dndToggle", "bedtimeToggle", "batterySaverToggle", "extraDimToggle", "flashlightButton"]

    readonly property var toggleRegistry: {
        const map = {
            "lockButton": lockButtonComponent,
            "settingsButton": settingsButtonComponent,
            "brightnessToggle": brightnessToggleComponent,
            "bluetoothToggle": bluetoothToggleComponent,
            "hapticsToggle": hapticsToggleComponent,
            "cinemaToggle": cinemaToggleComponent,
            "aodToggle": aodToggleComponent,
            "powerOffToggle": powerOffToggleComponent,
            "rebootToggle": rebootToggleComponent,
            "musicButton": musicButtonComponent,
            "flashlightButton": flashlightButtonComponent,
            "findPhoneButton": findPhoneButtonComponent,
            "dndToggle": dndToggleComponent,
            "bedtimeToggle": bedtimeToggleComponent,
            "batterySaverToggle": batterySaverToggleComponent,
            "extraDimToggle": extraDimToggleComponent
        };

        if (DeviceSpecs.hasWlan) {
            map["wifiToggle"] = wifiToggleComponent;
        }
        if (DeviceSpecs.hasSpeaker) {
            map["soundToggle"] = soundToggleComponent;
        }

        const toggles = {};
        for (const key in map) {
            // Find phone and the modes are newer than the saved settings of
            // most watches: on unless switched off
            if (toggleEnabled.value[key] || (newToggles.indexOf(key) >= 0 && toggleEnabled.value[key] === undefined)) {
                toggles[key] = map[key];
            }
        }

        return toggles;
    }

    ListView {
        id: fixedRow
        anchors.horizontalCenter: parent.horizontalCenter
        width: toggleSize * 2 + spacing
        height: toggleSize
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        clip: true
        interactive: false
        boundsBehavior: Flickable.StopAtBounds
        spacing: Dims.l(4)
        opacity: activeScrub ? 0.0 : 1.0
        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
        }

        readonly property var allToggles: {
            return fixedToggles.value
                .map(id => toggleRegistry[id])
                .filter(Boolean)
        }

        model: [allToggles]

        contentWidth: width

        delegate: Item {
            id: pageItem
            width: fixedRow.width
            height: fixedRow.height

            Row {
                id: toggleRow
                spacing: Dims.l(8)
                Repeater {
                    model: modelData
                    delegate: Loader {
                        width: toggleSize - Dims.l(4)
                        height: width
                        sourceComponent: modelData
                    }
                }
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }

        Component.onCompleted: positionViewAtBeginning()
    }

    // Live value label shown in the fixedRow area during scrub
    Label {
        id: scrubValueLabel
        anchors.centerIn: options.value.batteryBottom ? fixedRow : valueMeter
        opacity: activeScrub ? 0.9 : 0.0
        text: scrubMode === "brightness" ? displaySettings.brightness + "%" : volume + "%"
        font {
            pixelSize: Dims.l(12)
            family: "Noto Sans"
            styleName: "SemiCondensed SemiBold"
        }
        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
        }
    }

    Connections {
        target: grid
        function onCurrentVerticalPosChanged() {
            if (grid.currentVerticalPos === -1) {
                slidingRow.positionViewAtBeginning()
            }
        }
    }

    ListView {
        id: slidingRow
        anchors.centerIn: parent
        width: toggleSize * 3 + spacing * 2
        height: toggleSize
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        clip: true
        interactive: true
        boundsBehavior: Flickable.StopAtBounds
        spacing: Dims.l(4)
        opacity: activeScrub ? 0.0 : 1.0
        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
        }

        readonly property var allToggles: {
            // A saved list from before find phone existed gets it at the end
            var ids = sliderToggles.value.slice()
            if (ids.indexOf("findPhoneButton") < 0 && fixedToggles.value.indexOf("findPhoneButton") < 0)
                ids.push("findPhoneButton")
            // ...and Do Not Disturb
            if (ids.indexOf("dndToggle") < 0 && fixedToggles.value.indexOf("dndToggle") < 0)
                ids.push("dndToggle")
            // ...and the modes: Bedtime before Do Not Disturb (stock's
            // order), Battery saver and Extra dim after Theater
            function missing(id) { return ids.indexOf(id) < 0 && fixedToggles.value.indexOf(id) < 0 }
            if (missing("bedtimeToggle"))
                ids.splice(Math.max(0, ids.indexOf("dndToggle")), 0, "bedtimeToggle")
            var after = ids.indexOf("cinemaToggle") >= 0 ? ids.indexOf("cinemaToggle") + 1 : ids.length
            if (missing("extraDimToggle"))
                ids.splice(after, 0, "extraDimToggle")
            if (missing("batterySaverToggle"))
                ids.splice(after, 0, "batterySaverToggle")
            // ...and the Flashlight at the end (stock has it by default)
            if (missing("flashlightButton"))
                ids.push("flashlightButton")
            return ids
                .map(id => toggleRegistry[id])
                .filter(Boolean)
        }

        property int rowCount: Math.ceil(allToggles.length / 3)

        model: {
            const rows = [];
            for (let i = 0; i < allToggles.length; i += 3) {
                rows.push(allToggles.slice(i, i + 3));
            }
            return rows;
        }

        contentWidth: width * rowCount

        delegate: Item {
            id: pageItem
            width: slidingRow.width
            height: slidingRow.height

            Row {
                id: toggleRow
                spacing: slidingRow.spacing
                Repeater {
                    model: modelData
                    delegate: Loader {
                        width: toggleSize
                        height: toggleSize
                        sourceComponent: modelData
                    }
                }
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }

        Component.onCompleted: positionViewAtBeginning()

        onContentXChanged: {
            const newIndex = Math.round(contentX / width)
            if (newIndex >= 0 && newIndex < rowCount) currentIndex = newIndex
        }
    }

    // morphRect — plain pill that animates between valueMeter geometry and
    // scrubCover geometry during scrub start/end transitions. Color animates
    // from valueMeter fill light to scrubCover dark on expand, and reverse on
    // collapse. Declared before scrubCover so scrubCover paints on top.
    Rectangle {
        id: morphRect
        visible: false
        color: "#eee0e0e0"
        radius: height / 2
        // x, y, width, height are set imperatively in onActiveScrubChanged
    }

    // scrubCover — the actual interactive scrubber display. Position and size
    // are fixed at scrubRangeWidth/scrubCoverHeight; only opacity is animated
    // by scrubStartAnim/scrubEndAnim. Declared after morphRect so it paints
    // above and cleanly takes over at morph completion.
    Rectangle {
        id: scrubCover
        x: scrubCoverX
        y: scrubCoverY
        width: scrubRangeWidth
        height: scrubCoverHeight
        radius: height / 2
        color: Qt.rgba(0, 0, 0, 0)
        opacity: 0 // managed exclusively by scrubStartAnim / scrubEndAnim

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: scrubCover.width
                height: scrubCover.height
                radius: scrubCover.radius
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0.13, 0.13, 0.13, 0.75)
        }

        // Value fill — width tracks current brightness or volume fraction.
        // Color matches ValueMeter: white when batteryColored off, accent when on.
        Rectangle {
            id: scrubFill
            height: parent.height
            width: parent.width * Math.max(0, Math.min(1,
                (scrubMode === "brightness" ? displaySettings.brightness : volume) / 100))
            color: !options.value.batteryColored ? Qt.rgba(1, 1, 1, 0.3) : "#4CA6005F"
            Behavior on width {
                NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
            }
        }

        // Event-swallowing MouseArea covering the full scrubCover area.
        // Enabled by scrubEventGuard which outlives activeScrub by guardTimer
        // interval, covering the fade-out window where stray Qt touch events
        // could otherwise reach the toggles underneath.
        MouseArea {
            anchors.fill: parent
            enabled: scrubEventGuard
            // No handlers needed — default MouseArea behaviour accepts and
            // swallows all mouse/touch events when enabled
        }
    }

    ValueMeter {
        id: valueMeter
        width: toggleSize * 1.8
        height: Dims.l(8)
        valueLowerBound: 0
        valueUpperBound: 100
        anchors.horizontalCenter: parent.horizontalCenter

        // Always shows battery. Fades out during scrub while scrubCover takes over.
        value: batteryChargePercentage.percent
        opacity: activeScrub ? 0.0 : 1.0

        // Disable value animation during scrub — the fill would constantly
        // restart the 250ms animation and permanently lag behind the label
        Behavior on value {
            enabled: !activeScrub
            NumberAnimation {
                duration: 250
                easing.type: Easing.InOutQuad
            }
        }

        isIncreasing: isCharging
        enableAnimations: options.value.batteryAnimation
        // a short show when the panel opens or charging starts, then still:
        // a static screen draws nothing (it drew 59 fps while charging)
        animationDuration: 2000
        particleDesign: options.value.particleDesign

        fillColor: {
            if (!options.value.batteryColored) return Qt.rgba(1, 1, 1, 0.3)
            const percent = batteryChargePercentage.percent
            if (percent <= 20) {
                const t = (20 - percent) / 20
                return Qt.rgba(1, 0.65 * (1 - t), 0, 0.3)
            }
            if (percent <= 50) {
                const t = (50 - percent) / 30
                return Qt.rgba(t, 1 - (t * 0.35), 0, 0.3)
            }
            return Qt.rgba(0, 1, 0, 0.3)
        }

        Behavior on fillColor {
            ColorAnimation { duration: 300 }
        }

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
        }
    }

    // flashIcon cannot share a Behavior on opacity with its own
    // SequentialAnimation on opacity, so visibility is toggled instead
    Icon {
        id: flashIcon
        width: Dims.l(8)
        height: Dims.l(8)
        name: "ios-flash"
        anchors.centerIn: valueMeter
        y: -Dims.l(10)
        visible: isCharging && !activeScrub
        opacity: 1.0

        // Only pulse while the panel is on screen. The panels grid toggles
        // rootitem.visible per panel, so this stops the infinite animation
        // from waking the CPU every 1.5s while charging on another panel.
        // One pulse with the meter's show, ending at full opacity
        SequentialAnimation on opacity {
            running: rootitem.visible && isCharging && options.value.batteryAnimation && valueMeter.animating
            alwaysRunToEnd: true
            NumberAnimation { to: 0.7; duration: 1000; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1.0; duration: 1000; easing.type: Easing.InOutQuad }
        }
    }

    Label {
        id: valueMeterCaption
        anchors.horizontalCenter: parent.horizontalCenter
        opacity: activeScrub ? 0.0 : 1.0

        font {
            pixelSize: Dims.l(9)
            family: "Noto Sans"
            styleName: "Condensed Medium"
        }

        text: batteryChargePercentage.percent + "%"

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
        }
    }

    // Mode caption shown in place of valueMeterCaption during scrub.
    // anchors.centerIn: valueMeterCaption tracks the batteryBottom/batteryTop
    // layout state automatically without needing its own AnchorChanges entries.
    Label {
        id: scrubCaptionLabel
        anchors{
            centerIn: options.value.batteryBottom ? valueMeter : fixedRow            
            verticalCenterOffset: -Dims.l(3)
        }
        opacity: activeScrub ? 0.9 : 0.0

        font {
            pixelSize: Dims.l(12)
            family: "Noto Sans"
            styleName: "Condensed Medium"
        }

        //% "Brightness"
        text: scrubMode === "brightness" ? qsTrId("id-brightness") :
        //% "Volume"
              qsTrId("id-volume")

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
        }
    }

    PageDot {
        id: pageDots
        height: Dims.l(4)
        anchors.horizontalCenter: parent.horizontalCenter
        currentIndex: slidingRow.currentIndex
        dotNumber: slidingRow.rowCount
        opacity: activeScrub ? 0.0 : 0.5
        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
        }
    }

    RemorseTimer {
        id: remorseTimer
        duration: 3000
        gaugeSegmentAmount: 6
        gaugeStartDegree: -130
        gaugeEndFromStartDegree: 265
        //% "Tap to cancel"
        cancelText: qsTrId("id-tap-to-cancel")
    }

    Component {
        id: brightnessToggleComponent
        QuickPanelToggle {
            id: brightnessToggle
            objectName: "brightnessToggle"
            icon: "ios-sunny"
            checkable: true
            enabled: !modesReady || modes.brightnessHolder === ""
            rangeBased: true
            rangeMin: 10
            rangeMax: 100
            rangeStepSize: 10
            scrubWidth: rootitem.width

            checked: displaySettings.brightness > 10
            
            onClicked: {
                if (wasScrubbing) { wasScrubbing = false; return }
                if (checked) {
                    displaySettings.brightness = rangeMin
                } else {
                    displaySettings.brightness = rangeMax
                }
            }

            // binding keeps rangeValue current so scrub always starts from the
            // real current brightness, not a snapshot from a previous interaction
            rangeValue: displaySettings.brightness
            onRangeValueChanged: displaySettings.brightness = rangeValue

            onScrubbingChanged: {
                if (scrubbing) {
                    rootitem.scrubMode = "brightness"
                    rootitem.activeScrub = true
                } else {
                    rootitem.activeScrub = false
                }
            }
        }
    }

    Component {
        id: hapticsToggleComponent
        QuickPanelToggle {
            icon: "ios-watch-vibrating"
            checkable: true
            checked: vibrationEnabled.value

            onClicked: {
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
            // checked binds directly to the system source of truth. No Connections
            // block needed to stay in sync with external state changes.
            checked: wifiStatus.powered

            // !checked reads the value before the click flips it, so this is
            // effectively: set powered to whatever it currently isn't
            onClicked: {
                wifiStatus.powered = !checked
            }
        }
    }

    Component {
        id: bluetoothToggleComponent
        QuickPanelToggle {
            id: bluetoothToggle

            icon: btStatus.connected ? "ios-bluetooth-connected" : "ios-bluetooth"

            checkable: true
            checked: btStatus.powered
            BluetoothStatus {
                id: btStatus
            }

            onClicked: {
                btStatus.powered = !checked
            }
        }
    }

    Component {
        id: soundToggleComponent
        QuickPanelToggle {
            id: soundToggle
            checkable: true
            rangeBased: true
            rangeMin: 0
            rangeMax: 100
            rangeStepSize: 10
            scrubWidth: rootitem.width

            icon: preMuteLevel.value > 0 || volume === 0 ? "ios-sound-indicator-mute" :
                  volume > 70 ? "ios-sound-indicator-high" :
                  volume > 30 ? "ios-sound-indicator-mid" :
                  volume > 0 ? "ios-sound-indicator-low" : "ios-sound-indicator-off"

            // checked reflects mute state only — volume at 0% while unmuted
            // is silent but not muted and should not deactivate the toggle
            checked: !(preMuteLevel.value > 0 || volume === 0)

            onClicked: {
                if (wasScrubbing) { wasScrubbing = false; return }
                const tempVolume = volume
                let targetVolume = preMuteLevel.value
                if (tempVolume === 0 && targetVolume === 0) targetVolume = 100
                setVolume(targetVolume)
                preMuteLevel.value = tempVolume
                if (targetVolume > 0) soundDelayTimer.start()
            }

            rangeValue: volume
            onRangeValueChanged: {
                if (scrubbing) {
                    // Scrubbing to any value > 0 while muted clears the mute
                    // state — the user is explicitly setting a volume level
                    if (rangeValue > 0 && preMuteLevel.value > 0) {
                        preMuteLevel.value = 0
                    }
                    setVolume(rangeValue)
                }
            }

            onScrubbingChanged: {
                if (scrubbing) {
                    rootitem.scrubMode = "volume"
                    rootitem.activeScrub = true
                } else {
                    rootitem.activeScrub = false
                    if (rangeValue > 0) soundDelayTimer.start()
                }
            }

            Timer {
                id: soundDelayTimer
                interval: 150
                repeat: false
                onTriggered: unmuteSound.play()
            }
        }
    }

    /*
     * The modes, as the stock quick settings (STOCK-MODES.md): the
     * launcher's modes engine (modes.h) does what each changes. Bedtime,
     * Theater, Battery saver and the first Do Not Disturb ask first, with
     * "Don't show again"; turning one off is at once. "cinemaToggle" keeps
     * its id (saved panels) and is Theater mode now.
     */
    ConfigurationValue { id: askDnd; key: "/org/asteroidos/modes/ask/do-not-disturb"; defaultValue: true }
    ConfigurationValue { id: askBedtime; key: "/org/asteroidos/modes/ask/bedtime"; defaultValue: true }
    ConfigurationValue { id: askTheater; key: "/org/asteroidos/modes/ask/theater"; defaultValue: true }
    ConfigurationValue { id: askBatterySaver; key: "/org/asteroidos/modes/ask/battery-saver"; defaultValue: true }

    readonly property bool modesReady: typeof modes !== "undefined" && modes !== null

    function askFirst(ask, title, message, apply) {
        if (!ask.value) {
            apply()
            return
        }
        modeDialog.ask(title, message, function (dontShowAgain) {
            if (dontShowAgain)
                ask.value = false
            apply()
        })
    }

    Component {
        id: bedtimeToggleComponent
        QuickPanelToggle {
            objectName: "bedtimeToggle"
            icon: checked ? "ios-moon" : "ios-moon-outline"
            checkable: true
            checked: modesReady && modes.bedtime
            onClicked: {
                if (checked) {
                    modes.bedtime = false
                    //% "Bedtime mode off"
                    modeToast.show(qsTrId("id-bedtime-off"))
                    return
                }
                //% "Turn on Bedtime mode?"
                askFirst(askBedtime, qsTrId("id-bedtime-confirm-title"),
                         //% "Watch screen, tilt-to-wake, and touch are turned off. Only alarms and timers will notify you."
                         qsTrId("id-bedtime-confirm"),
                         function () { modes.bedtime = true })
            }
        }
    }

    Component {
        id: cinemaToggleComponent
        QuickPanelToggle {
            objectName: "theaterToggle"
            icon: checked ? "ios-film" : "ios-film-outline"
            checkable: true
            checked: modesReady && modes.theater
            onClicked: {
                if (checked) {
                    modes.theater = false
                    return
                }
                //% "Turn on Theater mode?"
                askFirst(askTheater, qsTrId("id-theater-confirm-title"),
                         //% "Turns off screen and screen wake gestures, silences alerts."
                         qsTrId("id-theater-confirm"),
                         function () { modes.theater = true })
            }
        }
    }

    Component {
        id: batterySaverToggleComponent
        QuickPanelToggle {
            objectName: "batterySaverToggle"
            icon: checked ? "ios-leaf" : "ios-leaf-outline"
            checkable: true
            // off and greyed out on the charger, as stock
            enabled: modesReady && !modes.charging
            checked: modesReady && modes.batterySaver
            onClicked: {
                if (checked) {
                    modes.batterySaver = false
                    return
                }
                //% "Turn on Battery Saver mode?"
                askFirst(askBatterySaver, qsTrId("id-saver-confirm-title"),
                         //% "Turns off Always-on-screen and Tilt-to-wake to extend battery life"
                         qsTrId("id-saver-confirm"),
                         function () { modes.batterySaver = true })
            }
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
            checked: modesReady && modes.extraDim
            onClicked: modes.extraDim = !checked
        }
    }

    Component {
        id: lockButtonComponent
        QuickPanelToggle {
            id: lockedToggle
            icon: "ios-unlock"
            onClicked: mce_dbus.call("req_display_state_lpm", undefined)
        }
    }

    Component {
        id: settingsButtonComponent
        QuickPanelToggle {
            icon: "ios-settings"
            onClicked: appLauncher.launchApp("asteroid-settings")
        }
    }

    Component {
        id: musicButtonComponent
        QuickPanelToggle {
            icon: "ios-musical-notes-outline"
            onClicked: appLauncher.launchApp("asteroid-music")
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
            onClicked: {
                if (checked) {
                    doNotDisturb.value = false
                    return
                }
                //% "Turn on Do Not Disturb?"
                askFirst(askDnd, qsTrId("id-dnd-confirm-title"),
                         //% "Only alarms and timers will notify you."
                         qsTrId("id-dnd-confirm"),
                         function () { doNotDisturb.value = true })
            }
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
            phoneDBus.typedCall("Connected", [], function (c) { findPhone.connected = c })
            phoneDBus.typedCall("BatteryLevel", [], function (l) { findPhone.battery = l })
        }

        // The phone's link and battery (asteroid-btsyncd's phone status),
        // shown on the toggle
        property bool connected: false
        property int battery: -1

        DBusInterface {
            id: phoneDBus
            bus: DBus.SessionBus
            service: "org.asteroidos.btsyncd"
            path: "/org/asteroidos/btsyncd/phone"
            iface: "org.asteroidos.btsyncd.Phone"
            signalsEnabled: true

            function rcConnectedChanged(connected: bool) {
                findPhone.connected = connected
            }
            function rcBatteryChanged(level: int, charging: bool) {
                findPhone.battery = level
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
        anchors.top: slidingRow.bottom
        anchors.topMargin: Dims.l(2)
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

    Component {
        id: findPhoneButtonComponent
        QuickPanelToggle {
            icon: "ios-phone-portrait"
            checkable: true
            checked: findPhone.ringing
            onClicked: findPhone.toggle()

            // The phone's battery, or a cross while it is not connected
            Label {
                visible: findPhone.connected && findPhone.battery >= 0
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: parent.height * 0.06
                font.pixelSize: parent.height * 0.15
                opacity: 0.8
                text: findPhone.battery + "%"
            }
            Icon {
                visible: !findPhone.connected
                name: "ios-close-circle"
                width: parent.width * 0.26
                height: width
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: parent.width * 0.1
                color: Theme.color.error
            }

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

    // Flashlight: opens the Flashlight app, as the stock quick settings'
    // Flashlight button starts FlashlightActivity (STOCK-FLASHLIGHT.md); its
    // icon is the stock tile's (quantum_gm_ic_flashlight_on)
    Component {
        id: flashlightButtonComponent
        QuickPanelToggle {
            objectName: "flashlightButton"
            icon: "gm-flashlight-on"
            onClicked: appLauncher.launchApp("asteroid-flashlight")
        }
    }

    Component {
        id: aodToggleComponent
        QuickPanelToggle {
            objectName: "aodToggle"
            readonly property bool blocked: modesReady && modes.alwaysOnBlocked
            icon: checked ? "ios-watch-aod-on" : "ios-watch-aod-off"
            checkable: true
            enabled: !blocked
            checked: alwaysOnDisplay.value && !blocked

            onClicked: {
                alwaysOnDisplay.value = !checked;
                displaySettings.lowPowerModeEnabled = alwaysOnDisplay.value;
            }
        }
    }

    Component {
        id: powerOffToggleComponent
        QuickPanelToggle {
            icon: "ios-power-outline"
            onClicked: {
                //% "Powering off in"
                remorseTimer.action = qsTrId("id-power-off");
                remorseTimer.onTriggered.connect(function() {
                    login1DBus.call("PowerOff", [false]);
                });
                remorseTimer.start();
            }
        }
    }

    Component {
        id: rebootToggleComponent
        QuickPanelToggle {
            icon: "ios-sync"
            onClicked: {
                //% "Rebooting in"
                remorseTimer.action = qsTrId("id-reboot");
                remorseTimer.onTriggered.connect(function() {
                    login1DBus.call("SetRebootParameter", [""]);
                    login1DBus.call("Reboot", [false]);
                });
                remorseTimer.start();
            }
        }
    }

    ModeDialog { id: modeDialog; objectName: "modeDialog" }

    // a short line near the bottom, as stock's toast ("Bedtime mode off")
    Item {
        id: modeToast
        objectName: "modeToast"
        property string text: ""
        anchors.fill: parent
        z: 950
        visible: opacity > 0
        opacity: 0
        function show(message) {
            text = message
            toastFade.stop()
            opacity = 1
            toastTimer.restart()
        }
        Timer { id: toastTimer; interval: 2000; onTriggered: toastFade.start() }
        NumberAnimation { id: toastFade; target: modeToast; property: "opacity"; to: 0; duration: 200 }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Dims.h(12)
            width: Math.min(Dims.w(70), toastLabel.implicitWidth + Dims.w(10))
            height: toastLabel.height + Dims.h(5)
            radius: Theme.shape.clamp(Theme.shape.large, height)
            color: Theme.color.surfaceContainerHigh
            Label {
                id: toastLabel
                anchors.centerIn: parent
                width: Math.min(Dims.w(60), implicitWidth)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                clip: false
                text: modeToast.text
                font.pixelSize: Theme.type.labelSmall.pixelSize
            }
        }
    }
}
