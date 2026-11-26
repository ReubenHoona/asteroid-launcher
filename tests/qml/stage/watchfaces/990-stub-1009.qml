// SPDX-License-Identifier: BSD-3-Clause
//
// A stand-in eos face for tst_facepicker.qml (N61-35): an EosFace (src/eoskit, staged beside this folder) that
// prints its `now`, on the log and in its pixels: a 16 px block in its accent at x = 8 x minute, y = 16 x hour
// (10:09 is x 72, y 160; the test's wall clock, 07:29, would be x 232, y 112), on nothing. One option, Color.
import QtQuick
import "../eoskit"
import "../eoskit/facekit.js" as Kit

EosFace {
    id: stub
    eosOptions: [Kit.colorOption("cloud")]
    Rectangle {
        objectName: "stubBlock"
        x: 8 * stub.minute
        y: 16 * stub.hour24
        width: 16
        height: 16
        color: stub.accent
    }
    onNowChanged: console.log("stub face now " + stub.now.toString())
    Component.onCompleted: console.log("stub face now " + stub.now.toString())
}
