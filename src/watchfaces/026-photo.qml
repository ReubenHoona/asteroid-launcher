// Copyright (C) 2026 eos-mainline contributors
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick
import Qt.labs.folderlistmodel
import QtCore
import "../eoskit"
import "../eoskit/facekit.js" as Kit

/*
 * Photo: a picture behind the time and one line slot (watchface-catalogue-38; stock's
 * Photos face shows a Google Photos picture, here it is a picture of the watch: the
 * wallpapers in /usr/share/asteroid-launcher/wallpapers or the pictures folder of the
 * user). Layout Linear or Stacked (default); the option "Photo" picks the picture.
 * The time is white over a shade that keeps it readable; the slot is the weather, or
 * the date. Always-on: only the time (a picture lights too many pixels), thin and dim,
 * the digits drawn by the sensor hub.
 */
EosFace {
    id: face

    readonly property var d: Kit.SLOT_DEFAULTS.photo

    // the pictures: the system wallpapers, then the user's pictures
    property var pictures: []
    FolderListModel {
        id: wallpapers
        folder: "file:///usr/share/asteroid-launcher/wallpapers"
        nameFilters: ["*.jpg", "*.jpeg", "*.png"]
        showDirs: false
        onCountChanged: face.collect()
    }
    FolderListModel {
        id: userPictures
        folder: StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        nameFilters: ["*.jpg", "*.jpeg", "*.png"]
        showDirs: false
        onCountChanged: face.collect()
    }
    function collect() {
        var list = []
        var i
        for (i = 0; i < wallpapers.count; i++)
            list.push(wallpapers.get(i, "fileUrl").toString())
        for (i = 0; i < userPictures.count; i++) {
            var u = userPictures.get(i, "fileUrl").toString()
            // (a folder that does not exist lists the working directory: only the folder's own files count)
            if (u.indexOf(String(userPictures.folder) + "/") === 0)
                list.push(u)
        }
        pictures = list
    }
    function nameOf(url) {
        return String(url).split("/").pop().replace(/\.[a-z]+$/i, "")
    }
    readonly property var pictureIds: pictures.map(nameOf)

    eosOptions: [
        Kit.listOption("layout", Kit.PHOTO_LAYOUTS, ["Stacked", "Linear"], "stacked"),
        Kit.listOption("photo", pictureIds.length ? pictureIds : ["none"], pictureIds.length ? pictureIds : ["None"],
                       pictureIds.length ? pictureIds[0] : "none")
    ]
    readonly property var g: Kit.photo(opt("layout"))
    readonly property string chosen: opt("photo")
    readonly property string pictureUrl: {
        var i = pictureIds.indexOf(chosen)
        return i >= 0 ? pictures[i] : ""
    }

    Image {
        objectName: "eosPhoto"
        anchors.fill: parent
        source: face.pictureUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // only the time in the always-on screen
        visible: face.blend < 1 && face.pictureUrl !== ""
        sourceSize.width: 384
        sourceSize.height: 384
    }
    Rectangle {
        objectName: "eosShade"
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, Kit.PHOTO_SHADE)
        visible: face.blend < 1
    }

    EosTimeStack {
        objectName: "eosTime"
        visible: face.g.stacked
        owner: face
        hourBox: face.g.hour
        minuteBox: face.g.minute ? face.g.minute : face.g.hour
        size: face.g.size
        color: face.white
        minuteColor: face.white
        ambientColor: face.whiteAmbient
        minuteAmbientColor: face.whiteAmbient
    }
    EosTimeRow {
        objectName: "eosTimeLinear"
        visible: !face.g.stacked
        owner: face
        box: face.g.hour
        size: face.g.size
        color: face.white
        ambientColor: face.whiteAmbient
    }

    EosSlot {
        owner: face; slotId: "line"; shape: "text"; defaultSource: face.d.line
        spec: face.g.slot
        tint: face.white
        // nothing but the time in the always-on screen
        opacity: face.blend < 1 ? 1 : 0
    }
}
