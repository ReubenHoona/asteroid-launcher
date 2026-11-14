/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import QtCore
import Qt.labs.folderlistmodel
import Nemo.Configuration
import "facepicker.js" as FP

/*
 * The favourites of the watch face carousel (face-interaction-18, -20,
 * watchface-catalogue-12), as stock's watch face picker: the carousel holds
 * the user's favourites, not every installed face. dconf
 * /org/asteroidos/watchface/favourites is a list of "id:file" (the face's
 * file URL); /org/asteroidos/watchface/current-id names the favourite on the
 * watch. The face on the watch is always a favourite. The id keys the
 * favourite's own style (FaceStyle) and complications
 * (/org/asteroidos/watchface/complications/<id>); the first favourites of a
 * watch take their face's file name as the id, which is the key the
 * complications had before (the existing choices carry over).
 *
 * Instantiated once by FaceLayer. `file` is the face on the home screen (dconf
 * /desktop/asteroid/watchface, written by FaceLayer); to change it the store
 * asks with fileRequested().
 */
Item {
    id: store
    visible: false
    width: 0
    height: 0

    // the face on the home screen, set by FaceLayer
    property string file: ""
    // a favourite was chosen and its face is not the one on the home screen
    signal fileRequested(string file)
    // another favourite of the same face was chosen: its face loads again (its complications)
    signal reloadRequested()
    // a favourite was removed (its cached preview goes)
    signal removed(string id)

    readonly property string systemFolder: "file:///usr/share/asteroid-launcher/watchfaces"
    // the faces of the Settings store (WatchfaceReloader's folder)
    readonly property string userFolder: StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/asteroid-launcher/watchfaces"

    // every installed face, as file URLs: the system folder, then the user's
    property var installed: []
    function refresh() {
        var list = []
        for (var i = 0; i < systemFaces.count; i++)
            list.push(systemFaces.get(i, "fileUrl").toString())
        // (a folder that does not exist lists the working directory: only files of the folder itself count)
        for (var j = 0; j < userFaces.count; j++) {
            var u = userFaces.get(j, "fileUrl").toString()
            if (u.indexOf(userFolder + "/") === 0)
                list.push(u)
        }
        installed = list
    }
    FolderListModel {
        id: systemFaces
        folder: store.systemFolder
        nameFilters: ["*.qml"]
        showDirs: false
        onStatusChanged: if (status === FolderListModel.Ready) { store.refresh(); store.resolve() }
        onCountChanged: store.refresh()
    }
    FolderListModel {
        id: userFaces
        folder: store.userFolder
        nameFilters: ["*.qml"]
        showDirs: false
        onCountChanged: store.refresh()
    }

    ConfigurationValue {
        id: favouritesValue
        key: "/org/asteroidos/watchface/favourites"
        defaultValue: []
        onValueChanged: store.load()
    }
    ConfigurationValue {
        id: currentIdValue
        key: "/org/asteroidos/watchface/current-id"
        defaultValue: ""
        onValueChanged: if (String(value) !== store.currentId) store.load()
    }

    // [{id, file}] in carousel order, and the favourite on the watch
    property var entries: []
    property string currentId: ""
    // the list is settled (written once the system faces are known)
    property bool ready: false

    function load() {
        var e = FP.parse(favouritesValue.value)
        if (!FP.same(e, entries))
            entries = e
        var id = String(currentIdValue.value)
        if (id !== currentId)
            currentId = id
        Qt.callLater(resolve)
    }

    // a face file that is not installed any more (only once its folder is read)
    function gone(f) {
        if (installed.indexOf(f) >= 0)
            return false
        if (f.indexOf(systemFolder + "/") === 0)
            return systemFaces.status === FolderListModel.Ready
        return userFaces.status === FolderListModel.Ready && f.indexOf(userFolder + "/") === 0
    }

    // the list as it must be now (a fresh watch gets the default carousel); written when it changed
    function resolve() {
        if (file === "" || systemFaces.status !== FolderListModel.Ready)
            return
        var list = FP.parse(favouritesValue.value)
        if (list.length === 0)
            list = FP.defaults(installed, file)
        var s = FP.settle(list, String(currentIdValue.value) === "" ? currentId : String(currentIdValue.value), file, gone)
        persist(s.entries, s.currentId)
        ready = true
    }
    onFileChanged: resolve()

    function persist(list, id) {
        if (!FP.same(list, entries))
            entries = list
        var raw = FP.serialize(list)
        if (!FP.same(raw, favouritesValue.value))
            favouritesValue.value = raw
        if (id !== currentId)
            currentId = id
        if (String(currentIdValue.value) !== id)
            currentIdValue.value = id
    }

    function indexOf(id) { return FP.indexOfId(entries, id) }
    function entryOf(id) {
        var i = indexOf(id)
        return i < 0 ? null : entries[i]
    }

    // a favourite goes on the watch
    function choose(id) {
        var e = entryOf(id)
        if (!e)
            return false
        var changed = id !== currentId
        persist(entries, id)
        if (e.file !== file)
            fileRequested(e.file)
        else if (changed)
            reloadRequested()
        return true
    }

    // a face of the add list becomes the last favourite (not put on the watch): its id
    function add(f) {
        var r = FP.add(entries, f)
        persist(r.entries, currentId)
        return r.id
    }

    // a favourite is removed; the last one stays. Removing the face on the watch puts the next on
    function remove(id) {
        var r = FP.remove(entries, id, currentId)
        if (!r.ok)
            return false
        persist(r.entries, r.applied ? currentId : r.currentId)
        removed(id)
        if (r.applied)
            choose(r.currentId)
        return true
    }

    // the favourite swaps with its neighbour, dir -1 (left) or +1 (right), and is saved at once
    function move(id, dir) {
        if (!FP.canMove(entries, id, dir))
            return false
        persist(FP.move(entries, id, dir), currentId)
        return true
    }

    Component.onCompleted: load()
}
