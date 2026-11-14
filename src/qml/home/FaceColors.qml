/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "../complications/faceeditor.js" as FE

/*
 * The system colours follow the watch face (face-interaction-31, stock
 * DynamicColorOverlayModule, jbz.java:136-146): after a face change the face's
 * colour goes to the theme as its seed (Theme.reportFaceColors: the Color theme
 * "Match watch face" then derives the palette; with another source the call only
 * stores the colours). A face declares its colour with `seedColor` (and
 * optionally `accentColor`) on its root item; a bundled face without one has the
 * colour its preview was sampled to (faceeditor.js FACE_COLORS); a face with
 * neither leaves the theme on its default seed.
 *
 * Nothing runs in the always-on screen or with the display off: a face that
 * changed there is reported when the screen comes back (stock applies it at once
 * on the face, else on return). No timer, no polling: the signals are a face
 * file, the loaded face item, the display and ambient state.
 */
Item {
    id: colors
    objectName: "eosFaceColors"
    visible: false
    width: 0
    height: 0

    // the face file on the home screen and its loaded item
    property string file: ""
    property Item face: null
    property bool awake: true
    property bool ambient: false
    // where the colours go (the tests replace it)
    property var reporter: function (seed, accent) { Theme.reportFaceColors(seed, accent) }

    // the colours last handed to the theme (faceeditor.js faceColors)
    property string reportedSeed: ""
    property string reportedAccent: ""
    property int reports: 0
    // a face change that has not been reported yet (the display was off)
    property bool pending: false

    readonly property var current: FE.faceColors(file,
        face && face.seedColor !== undefined ? face.seedColor : "",
        face && face.accentColor !== undefined ? face.accentColor : "")

    function update() {
        if (file === "")
            return
        if (!FE.reportNow(awake, ambient)) {
            pending = true
            return
        }
        pending = false
        var c = FE.faceColors(file, face && face.seedColor !== undefined ? face.seedColor : "",
                              face && face.accentColor !== undefined ? face.accentColor : "")
        if (c.seed === reportedSeed && c.accent === reportedAccent && reports > 0)
            return
        reportedSeed = c.seed
        reportedAccent = c.accent
        reports++
        reporter(c.seed, c.accent)
    }
    onFileChanged: update()
    onFaceChanged: update()
    onCurrentChanged: update()
    onAwakeChanged: if (pending) update()
    onAmbientChanged: if (pending) update()
    Component.onCompleted: update()
}
