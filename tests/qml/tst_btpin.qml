/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

// R5 B-14: the Bluetooth pairing PIN entry (BluetoothAgent.qml, "Enter PIN:") takes its digits from the full
// screen keyboard's PIN pad (qml-asteroid WearKeyboard, Qt.ImhDigitsOnly), as every digits-only field of the
// watch, and never from the Qt Virtual Keyboard InputPanel (HandWritingKeyboard): CP3A hides handwriting
// (text-input-24, connectivity-system-ux-02). The agent is a stand-in with the real object's properties and
// slots. MODE=st (the staged tree; the image's org.asteroid.controls).
import QtQuick
import QtTest
import org.nemomobile.lipstick

Item {
    id: top
    width: 384
    height: 384

    QtObject { id: localeManager; property string changesObserver: "" }
    QtObject {
        id: bluetoothAgent
        property bool windowVisible: false
        property int state: BluetoothAgent.Idle
        property string pinCode: ""
        property int passkey: 0
        property string deviceName: ""
        property bool deviceIsPhone: false
        property int accepts: 0
        property string lastPin: ""
        property int lastPasskey: -1
        function userAccepts() { accepts++; lastPin = pinCode; lastPasskey = passkey; state = BluetoothAgent.Idle }
        function userCancels() { state = BluetoothAgent.Idle }
        function request(s) { windowVisible = true; state = s }
    }

    Rectangle { anchors.fill: parent; color: "black" }
    Loader { id: ld; anchors.fill: parent; z: 10; source: Qt.resolvedUrl("st/qml/connectivity/BluetoothAgent.qml") }

    TestCase {
        name: "BluetoothPin"
        when: windowShown
        property var a: null

        function initTestCase() {
            tryCompare(ld, "status", Loader.Ready, 20000)
            a = ld.item
        }
        function init() {
            bluetoothAgent.windowVisible = false
            bluetoothAgent.state = BluetoothAgent.Idle
            bluetoothAgent.accepts = 0
            bluetoothAgent.pinCode = ""
            bluetoothAgent.passkey = 0
            wait(20)
            tryVerify(function () { return !a.dialog.active }, 5000)
        }

        // every item under root whose type name starts with one of the names
        function findType(root, names, out) {
            if (!root)
                return out
            var t = String(root)
            for (var i = 0; i < names.length; i++)
                if (t.indexOf(names[i]) === 0)
                    out.push(root)
            var kids = root.children || []
            for (var k = 0; k < kids.length; k++)
                findType(kids[k], names, out)
            return out
        }
        // the full screen keyboard the field opened (created in the window's content item)
        function keyboard() {
            var root = top.Window.contentItem
            var kids = root ? root.children : []
            for (var i = 0; i < kids.length; i++)
                if (kids[i].numberPad !== undefined && kids[i].typeKey !== undefined)
                    return kids[i]
            return null
        }
        function up(state) {
            bluetoothAgent.request(state)
            tryVerify(function () { return a.dialog.shown }, 3000)
            wait(50)
        }

        function test_01_no_handwriting_keyboard() {
            up(BluetoothAgent.ReqPinCode)
            compare(a.dialog.title, "Enter PIN:")
            verify(a.entryRow.height > 0)
            // no Qt Virtual Keyboard anywhere in the dialog or the window
            compare(findType(a, ["HandWritingKeyboard", "InputPanel", "HandwritingInputPanel"], []).length, 0)
            compare(findType(top.Window.contentItem, ["HandWritingKeyboard", "InputPanel", "HandwritingInputPanel"], []).length, 0)
            compare(keyboard(), null, "no keyboard before the tap")
        }

        function test_02_a_tap_opens_the_pin_pad_and_the_pin_is_sent() {
            up(BluetoothAgent.ReqPinCode)
            verify(a.inputField.inputMethodHints & Qt.ImhDigitsOnly)
            verify(a.inputField.fullScreenKeyboard)
            mouseClick(a.inputField)
            tryVerify(function () { return keyboard() !== null }, 3000)
            var kb = keyboard()
            verify(kb.numberPad, "the PIN pad (WearKeyboard numberPad)")
            wait(400)
            grabImage(top).save("/tmp/r5ui-shots/b14-pin-pad.png")
            kb.typeKey("0"); kb.typeKey("0"); kb.typeKey("4"); kb.typeKey("2")
            compare(kb.text, "0042")
            kb.accepted(kb.text)
            compare(a.inputField.text, "0042")
            tryVerify(function () { return keyboard() === null }, 3000)
            verify(a.dialog.confirmButton.enabled)
            a.dialog.confirmed()
            compare(bluetoothAgent.accepts, 1)
            compare(bluetoothAgent.lastPin, "0042")
        }

        function test_03_passkey_too() {
            up(BluetoothAgent.ReqPasskey)
            mouseClick(a.inputField)
            tryVerify(function () { return keyboard() !== null }, 3000)
            var kb = keyboard()
            verify(kb.numberPad)
            kb.typeKey("1"); kb.typeKey("2"); kb.typeKey("3")
            kb.accepted(kb.text)
            tryVerify(function () { return keyboard() === null }, 3000)
            a.dialog.confirmed()
            compare(bluetoothAgent.lastPasskey, 123)
        }

        function test_04_no_entry_no_keyboard() {
            bluetoothAgent.passkey = 654321
            up(BluetoothAgent.ReqConfirmation)
            compare(a.entryRow.height, 0)
            compare(findType(top.Window.contentItem, ["HandWritingKeyboard", "InputPanel"], []).length, 0)
        }
    }
}
