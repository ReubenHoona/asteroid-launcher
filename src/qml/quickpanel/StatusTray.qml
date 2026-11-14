/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "qs.js" as QS

/*
 * The status tray of the quick settings, as stock CP3A's (SysUI kxr.java:2395-2560,
 * kzd.java:46-108, kyw.java:125-290; VALUES.tsv compose_qss_statustray_*): a
 * full-round pill, 26 dp high and at least 50 dp wide, surfaceContainerLow, 5 dp
 * of padding at the sides, 20 dp icons 4 dp apart in their own colours, and a
 * "+N" circle (22 dp, surfaceContainer, primary text) when they do not all fit.
 * One icon: a tap opens its popup (icon, title, body, the Settings button of
 * its page and Close). Several: a list ("Connected to phone", "Bluetooth is
 * off"...), then the popup of the row.
 *
 * Only signals feed it: the phone link, Bluetooth, Wi-Fi and the next alarm
 * (QuickPanel.qml); it holds no timer and polls nothing. The popups are made
 * in `dialogHost` (the panel), not in the pill.
 */
Item {
    id: tray

    property bool phoneKnown: true
    property bool phoneConnected: false
    property bool btPowered: true
    property bool wifiConnected: false
    property string wifiName: ""
    /*! When the next alarm rings, ms (0 none). */
    property real alarmMs: 0
    /*! The screen the popups cover. */
    property Item dialogHost: null

    /*! A popup's button asks for this Settings page (the /org/asteroidos/settings/ui/open route). */
    signal settingsRequested(string page)

    readonly property var icons: QS.statusIcons({ phoneKnown: phoneKnown, phoneConnected: phoneConnected,
                                                  btPowered: btPowered, wifiConnected: wifiConnected,
                                                  alarmMs: alarmMs })
    readonly property var split: QS.pillSplit(icons)
    readonly property alias pill: _pill
    readonly property alias popup: _popup
    readonly property alias list: _list

    visible: icons.length > 0
    width: Theme.dp(QS.pillWidthDp(split.shown.length, split.more))
    height: Theme.dp(QS.PILL_HEIGHT_DP)

    function titleOf(kind) {
        switch (kind) {
        case "phone":
            //% "Connected to"
            return qsTrId("id-qs-connected-to")
        case "phoneOff":
            //% "Disconnected from phone"
            return qsTrId("id-qs-disconnected-phone")
        case "btOff":
            //% "Bluetooth is off"
            return qsTrId("id-qs-bluetooth-off")
        case "wifi":
            return qsTrId("id-qs-connected-to")
        case "alarm":
            //% "Upcoming alarm"
            return qsTrId("id-qs-upcoming-alarm")
        }
        return ""
    }
    function bodyOf(kind) {
        switch (kind) {
        case "phone":
            //% "Phone"
            return qsTrId("id-qs-phone")
        case "phoneOff":
            //% "Make sure your phone is nearby and Bluetooth is turned on"
            return qsTrId("id-qs-phone-nearby")
        case "wifi":
            //% "wi-fi"
            return tray.wifiName !== "" ? tray.wifiName : qsTrId("id-qs-wifi")
        case "alarm":
            return alarmMs > 0 ? Qt.formatTime(new Date(alarmMs), Qt.locale().timeFormat(Locale.ShortFormat)) : ""
        }
        return ""
    }
    // the list row of a status (quicksettings_disambig_*)
    function rowOf(kind) {
        switch (kind) {
        case "phone":
            //% "Connected to phone"
            return qsTrId("id-qs-disambig-phone")
        case "phoneOff":
            return qsTrId("id-qs-disconnected-phone")
        case "btOff":
            return qsTrId("id-qs-bluetooth-off")
        case "wifi":
            //% "Connected to Wifi"
            return qsTrId("id-qs-disambig-wifi")
        case "alarm":
            return qsTrId("id-qs-upcoming-alarm")
        }
        return ""
    }
    // the Settings page a popup's button opens, and its label ("" no button)
    function pageOf(kind) {
        switch (kind) {
        case "phone":
        case "phoneOff":
        case "btOff":
            return "bluetooth"
        case "wifi":
            return "wifi"
        case "alarm":
            return "main"
        }
        return ""
    }
    function buttonOf(kind) {
        var p = pageOf(kind)
        if (p === "bluetooth")
            //% "Bluetooth Settings"
            return qsTrId("id-qs-bluetooth-settings")
        if (p !== "")
            //% "Settings"
            return qsTrId("id-qs-settings")
        return ""
    }

    function showPopup(kind) {
        _popup.kind = kind
        _popup.open()
    }
    function showList() {
        _list.open()
    }
    // the tap on the pill
    function tapped() {
        if (icons.length === 1)
            showPopup(icons[0])
        else if (icons.length > 1)
            showList()
    }

    /* one status glyph: a Material/Ionicons glyph tinted in a colour of its own, or
     * the eos-status SVG (a disc with its own colours: an Image, never tinted) */
    component Glyph: Item {
        id: g
        property string kind: ""
        property real size: Theme.dp(20)
        readonly property bool own: kind === "phoneOff" || kind === "btOff"
        readonly property string iconName: kind === "phone" ? "ios-phone-portrait" : kind === "wifi" ? "ios-wifi"
                                          : kind === "alarm" ? "ios-alarm" : ""
        readonly property string imageName: kind === "phoneOff" ? "eos-status-phone-disconnected"
                                           : kind === "btOff" ? "eos-status-bluetooth-off" : ""
        width: size
        height: size
        Icon {
            anchors.fill: parent
            visible: !g.own
            name: g.iconName !== "" ? g.iconName : "ios-information-circle-outline"
            color: g.kind === "alarm" ? Theme.color.tertiary : Theme.color.onSurface
        }
        Image {
            anchors.fill: parent
            visible: g.own
            source: g.own ? "file:///usr/share/icons/asteroid/" + g.imageName + ".svg" : ""
            sourceSize: Qt.size(width, height)
            fillMode: Image.PreserveAspectFit
            asynchronous: false
        }
    }

    Rectangle {
        id: _pill
        objectName: "statusPill"
        anchors.fill: parent
        radius: Theme.shape.full(height)
        color: Theme.color.surfaceContainerLow

        Row {
            anchors.centerIn: parent
            spacing: Theme.dp(QS.PILL_GAP_DP)
            Repeater {
                model: tray.split.shown
                delegate: Glyph {
                    objectName: "statusIcon-" + modelData
                    kind: modelData
                }
            }
            Rectangle {
                objectName: "statusMore"
                visible: tray.split.more > 0
                width: Theme.dp(QS.PILL_OVERFLOW_DP)
                height: width
                radius: width / 2
                color: Theme.color.surfaceContainer
                Label {
                    anchors.centerIn: parent
                    text: "+" + tray.split.more
                    role: "labelSmall"
                    color: Theme.color.primary
                }
            }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: tray.tapped()
        }
    }

    /* the popup of one status */
    AlertDialog {
        id: _popup
        objectName: "statusPopup"
        parent: tray.dialogHost
        property string kind: ""
        iconName: kind === "phone" ? "ios-phone-portrait" : kind === "wifi" ? "ios-wifi" : kind === "alarm" ? "ios-alarm"
                  : kind === "btOff" ? "ios-bluetooth-outline" : kind === "phoneOff" ? "ios-close-circle-outline" : ""
        title: tray.titleOf(kind)
        text: tray.bodyOf(kind)
        buttons: "edge"
        //% "Close"
        edgeText: qsTrId("id-qs-close")
        closeOnAction: true
        readonly property alias settingsButton: _settingsBtn
        // The wrapper keeps its own visibility and only changes its height: a Column
        // does not hear about a child that turns visible under an invisible parent
        // (AlertDialog hides a row of no height), so a button that came and went by
        // `visible` would never come back.
        Item {
            width: parent.width
            height: tray.buttonOf(_popup.kind) !== "" ? _settingsBtn.height : 0
            Button {
                id: _settingsBtn
                objectName: "statusSettings"
                visible: tray.buttonOf(_popup.kind) !== ""
                width: parent.width
                variant: "tonal"
                centered: true
                text: tray.buttonOf(_popup.kind)
                onClicked: {
                    var page = tray.pageOf(_popup.kind)
                    _popup.close()
                    tray.settingsRequested(page)
                }
            }
        }
    }

    /* the list of several */
    Dialog {
        id: _list
        objectName: "statusList"
        parent: tray.dialogHost
        onDismissRequested: close()
        Flickable {
            id: _lf
            anchors.fill: parent
            contentWidth: width
            contentHeight: _lc.height
            topMargin: Math.ceil(0.10 * height)
            bottomMargin: Math.ceil(0.10 * height)
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: _lc
                x: Math.ceil(0.052 * parent.width)
                width: _lf.width - 2 * x
                spacing: Theme.dp(4)
                Repeater {
                    model: tray.icons
                    delegate: Button {
                        objectName: "statusRow-" + modelData
                        width: _lc.width
                        variant: "tonal"
                        text: tray.rowOf(modelData)
                        onClicked: {
                            _list.close()
                            tray.showPopup(modelData)
                        }
                    }
                }
            }
        }
    }
}
