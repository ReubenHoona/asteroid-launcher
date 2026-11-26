/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import "facepicker.js" as FP

/*
 * The 10:09 pictures of the face picker (N61-35). Wear OS 6 shows every carousel item, the face on the watch
 * included, as the face drawn at 10:09 on Thursday 24 May (S15, S15-b), never a snapshot of the face as it is.
 * An eos face (eoskit EosFace) is drawn here once per favourite, with the favourite's own style (FaceStyle,
 * dconf /org/asteroidos/watchface/style/<id>) and complications, at eosPreviewTime = FP.previewTime(): a hidden
 * instance (inside a clip of nothing, never on the screen) is grabbed at 384 px into the launcher's cache
 * (facePreviews, FacePreviews C++) as FP.renderKey(id).png. That happens when a favourite is added (or has no
 * picture yet) and when its style or complications were saved (the editor closed), never when the picker
 * opens. The upstream faces (FP.upstreamFace) read wallClock directly: their shipped picture is used instead.
 *
 * One favourite at a time, only while `active` (the display on: a grab needs a frame); the instance exists only
 * while it is drawn.
 */
Item {
    id: renderer
    visible: true
    width: 0
    height: 0

    // the cache the pictures go to (path(), exists(), remove()), and the favourites (entries: {id, file})
    property QtObject cache: null
    property QtObject store: null
    // the launcher's complications: the favourite's sources drawn in the face's slots (their preview data)
    property QtObject sources: null
    // frames may be drawn (the display is on)
    property bool active: true
    // the size of the picture, px
    property int side: 384
    // a picture was written (the picker reads the files again)
    property int version: 0
    readonly property bool busy: current !== ""

    signal rendered(string id, bool ok)

    // the favourites still to draw, in order, and the one being drawn
    property var queue: []
    property string current: ""
    property string currentFile: ""
    // faces found not to be eos faces this session (no picture of theirs is drawn)
    property var notEos: ({})

    // draw the picture of favourite `id` again (its style changed); a favourite of an upstream face is skipped
    function render(id) {
        if (!store || id === "" || !entryFile(id) || FP.upstreamFace(entryFile(id)))
            return false
        if (queue.indexOf(id) < 0 && id !== current)
            queue = queue.concat([id])
        Qt.callLater(next)
        return true
    }
    // every favourite of an eos face that has no picture yet (a fresh watch, a favourite just added, an update)
    function renderMissing() {
        if (!store || !cache)
            return 0
        var n = 0
        for (var i = 0; i < store.entries.length; i++) {
            var e = store.entries[i]
            if (FP.upstreamFace(e.file) || notEos[e.file] === true || cache.exists(FP.renderKey(e.id)))
                continue
            if (render(e.id))
                n++
        }
        return n
    }
    function entryFile(id) {
        if (!store)
            return ""
        for (var i = 0; i < store.entries.length; i++)
            if (store.entries[i].id === id)
                return store.entries[i].file
        return ""
    }

    onActiveChanged: if (active) Qt.callLater(next)

    function next() {
        if (current !== "" || !active || !cache)
            return
        while (queue.length > 0) {
            var id = queue[0]
            queue = queue.slice(1)
            var file = entryFile(id)
            if (file === "" || notEos[file] === true)
                continue
            current = id
            currentFile = file
            style.faceId = id
            style.schema = []
            // the time and the style before the first frame: the face never shows the wall clock here
            loader.setSource(file, { eosPreviewTime: FP.previewTime() })
            return
        }
    }
    function done(ok) {
        var id = current
        loader.source = ""
        current = ""
        currentFile = ""
        style.faceId = ""
        rendered(id, ok)
        Qt.callLater(next)
    }

    // the favourite's options, as FaceLayer hands them to the face on the watch
    FaceStyle {
        id: style
    }

    // never on the screen: the face is drawn inside a clip of nothing, and only grabbed
    Item {
        clip: true
        width: 0
        height: 0
        Item {
            id: stage
            objectName: "eosFaceRenderStage"
            width: renderer.side
            height: renderer.side
            Loader {
                id: loader
                objectName: "eosFaceRenderLoader"
                anchors.fill: parent
                asynchronous: false
                onStatusChanged: {
                    if (renderer.current === "")
                        return
                    if (status === Loader.Error)
                        renderer.done(false)
                    else if (status === Loader.Ready)
                        renderer.dress()
                }
            }
        }
    }

    function dress() {
        var f = loader.item
        if (!f || f.eosPreviewTime === undefined) {
            // not an eos face: its shipped picture is its picture
            var o = {}
            for (var k in notEos)
                o[k] = notEos[k]
            o[currentFile] = true
            notEos = o
            done(false)
            return
        }
        f.eosPreviewTime = FP.previewTime()
        style.schema = f.eosOptions !== undefined ? f.eosOptions : []
        if (f.eosStyle !== undefined)
            f.eosStyle = style.values
        // the favourite's complications, drawn from their preview data (ComplicationView with eosPreviewTime)
        if (sources && sources.attach)
            sources.attach(f, current)
        settle.restart()
    }
    // two frames: the slots' views and any layer take their sources a frame late
    Timer {
        id: settle
        interval: 50
        onTriggered: renderer.grab()
    }
    function grab() {
        var p = cache ? cache.path(FP.renderKey(current)) : ""
        if (p === "" || !stage.grabToImage(function (r) {
                var ok = r.saveToFile(p)
                if (ok)
                    renderer.version++
                renderer.done(ok)
            }, Qt.size(side, side)))
            done(false)
    }
}
