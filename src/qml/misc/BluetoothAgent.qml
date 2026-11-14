/*
 * Copyright (C) 2017 Florent Revest <revestflo@gmail.com>
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
import org.nemomobile.lipstick

/*
 * The Bluetooth pairing dialog on the shared M3 alert dialog (W3-launcher-misc), as stock
 * CP3A's pairing activities (connectivity-system-ux-01, -02, -03):
 *   - Confirm code: title "Secure pair with <name>" (the short "Secure pair <name>" when the
 *     whole title is over 18 characters, as BluetoothPairingDialogBuilder checks it), the text
 *     "Do codes match?" and the 6 digit code under it in the large title style, cancel and
 *     confirm buttons.
 *   - Consent: the title only, cancel and confirm.
 *   - Display passkey / PIN: "Enter this code on phone" (the device is a phone) or "Enter code
 *     on other device", then the code; no buttons, a swipe back or the crown cancels.
 *   - Enter PIN / passkey: "Enter PIN:" and a digit field of 1 to 16 digits; confirm is
 *     enabled only for those.
 *   - Legacy PIN requests say "Legacy pair with <name>".
 * There is no service prompt (the agent answers those itself) and the address is never shown:
 * a device without a name is "device". Leaving the dialog cancels the pairing; the agent's
 * own 120 s timeout and the display handling (mce) are unchanged. Nothing runs while it is
 * not up.
 */
Item {
    id: btAgent
    objectName: "bluetoothAgentDialog"

    anchors.fill: parent
    visible: bluetoothAgent.windowVisible || dialog.active

    /* the dialog is up (the crown closes it: KeyRouter, "closeSystemDialog") */
    readonly property bool shown: dialog.shown
    readonly property alias dialog: dialog

    /* leaving the dialog (the crown) cancels the pairing; the agent's state then closes it */
    function close() {
        if (dialog.shown)
            bluetoothAgent.userCancels()
    }
    readonly property alias inputField: inputField
    readonly property alias codeLabel: codeLabel
    readonly property alias entryRow: entryRow

    // 6 digits, padded (a passkey), or the PIN as given
    readonly property string passkeyText: ("000000" + bluetoothAgent.passkey).slice(-6)

    readonly property int st: bluetoothAgent.state
    readonly property bool legacy: st === BluetoothAgent.ReqPinCode || st === BluetoothAgent.DispPinCode
    readonly property bool displayOnly: st === BluetoothAgent.DispPasskey || st === BluetoothAgent.DispPinCode
    readonly property bool entry: st === BluetoothAgent.ReqPinCode || st === BluetoothAgent.ReqPasskey
    readonly property bool hasCode: st === BluetoothAgent.ReqConfirmation || displayOnly

    readonly property string deviceText: {
        var n = bluetoothAgent.deviceName
        //% "device"
        return n !== undefined && n !== "" ? n : qsTrId("id-btagent-device") + localeManager.changesObserver
    }

    /* stock's title: "Secure pair with %1", "Legacy pair with %1"; the short form when the
     * formatted title is over 18 characters ("Secure pair %1", "Legacy pair %1") */
    function pairTitle(name, isLegacy) {
        var full = isLegacy
            //% "Legacy pair with %1"
            ? qsTrId("id-btagent-legacy-pair-with").arg(name)
            //% "Secure pair with %1"
            : qsTrId("id-btagent-secure-pair-with").arg(name)
        if (full.length <= 18)
            return full
        return isLegacy
            //% "Legacy pair %1"
            ? qsTrId("id-btagent-legacy-pair").arg(name)
            //% "Secure pair %1"
            : qsTrId("id-btagent-secure-pair").arg(name)
    }

    readonly property string titleText: {
        if (entry)
            //% "Enter PIN:"
            return qsTrId("id-btagent-enter-pin") + localeManager.changesObserver
        if (displayOnly)
            return pairTitle(deviceText, legacy)
        return pairTitle(deviceText, false)
    }
    readonly property string messageText: {
        if (st === BluetoothAgent.ReqConfirmation)
            //% "Do codes match?"
            return qsTrId("id-btagent-codes-match") + localeManager.changesObserver
        if (displayOnly)
            return bluetoothAgent.deviceIsPhone
                //% "Enter this code on phone"
                ? qsTrId("id-btagent-code-on-phone") + localeManager.changesObserver
                //% "Enter code on other device"
                : qsTrId("id-btagent-code-on-other") + localeManager.changesObserver
        return ""
    }
    readonly property string codeText: st === BluetoothAgent.DispPinCode ? bluetoothAgent.pinCode : passkeyText

    // 1 to 16 digits (BluetoothEnterPinActivity: 1 <= length <= 16)
    readonly property bool inputValid: inputField.text.length >= 1 && inputField.text.length <= 16

    readonly property bool wanted: bluetoothAgent.windowVisible && st !== BluetoothAgent.Idle
                                   && st !== BluetoothAgent.AuthService

    // the agent answered or cancelled by itself: the dialog goes without asking again
    property bool closingByAgent: false

    onWantedChanged: {
        if (wanted) {
            inputField.text = ""
            dialog.open()
        } else if (dialog.shown) {
            closingByAgent = true
            dialog.close()
            closingByAgent = false
        }
    }

    AlertDialog {
        id: dialog
        objectName: "bluetoothAlert"
        title: btAgent.titleText
        text: btAgent.messageText
        buttons: btAgent.displayOnly ? "none" : "confirmDismiss"
        // a display-only code and a request leave through the agent: its state ends the window
        closeOnAction: true
        onConfirmed: {
            if (bluetoothAgent.state === BluetoothAgent.ReqPinCode)
                bluetoothAgent.pinCode = inputField.text
            if (bluetoothAgent.state === BluetoothAgent.ReqPasskey)
                bluetoothAgent.passkey = Number(inputField.text)
            bluetoothAgent.userAccepts()
        }
        onDismissed: if (!btAgent.closingByAgent) bluetoothAgent.userCancels()

        // the code, on its own line in the large title style. The rows of an alert dialog are
        // measured by what is visible, so these two do not toggle `visible`: a row with no content
        // is 0 px high
        Label {
            id: codeLabel
            objectName: "bluetoothCode"
            readonly property bool wanted: btAgent.hasCode
            height: wanted ? implicitHeight : 0
            opacity: wanted ? 1 : 0
            width: parent ? parent.width : 0
            horizontalAlignment: Text.AlignHCenter
            role: "titleLarge"
            color: Theme.color.onSurface
            text: btAgent.codeText
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        // the PIN: digits only
        Item {
            id: entryRow
            objectName: "bluetoothEntry"
            width: parent ? parent.width : 0
            height: btAgent.entry ? inputField.height : 0
            opacity: btAgent.entry ? 1 : 0
            TextField {
                id: inputField
                objectName: "bluetoothInput"
                enabled: btAgent.entry
                width: parent.width
                inputMethodHints: Qt.ImhDigitsOnly
                validator: RegularExpressionValidator { regularExpression: /^[0-9]{0,16}$/ }
            }
        }
    }

    // the confirm button of an entry is for 1 to 16 digits only
    Binding {
        target: dialog.confirmButton
        property: "enabled"
        value: !btAgent.entry || btAgent.inputValid
    }

    // Only while a pairing dialog with an entry shows: made at start, the keyboard's
    // style animated its hidden space key (32 frames after every launcher start)
    Loader {
        anchors.fill: parent
        z: 2
        active: btAgent.entry && dialog.shown
        sourceComponent: Component { HandWritingKeyboard { } }
    }

    // the agent's state ends the window: it is Idle after an answer or a remote cancel
    Connections {
        target: bluetoothAgent
        function onStateChanged() {
            if (bluetoothAgent.state === BluetoothAgent.Idle)
                bluetoothAgent.windowVisible = false
        }
    }
}
