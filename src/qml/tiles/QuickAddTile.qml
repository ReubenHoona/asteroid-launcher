/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import QtQuick.Shapes
import org.asteroid.controls
import "tilecontent.js" as TC

/*
 * Quick Add, as the SysUI tile (tiles-framework-30, tiles-individual-29; AddTileTileService.java:121-187, :530;
 * add_tile.png): no title; a large scalloped shape in dark blue (#1A438F, our own drawing: twelve rounded lobes round
 * a 200 px disc) with a plus (64 px) in it and "Add new" curved along the bottom edge. A tap opens the tiles editor
 * straight in the list of widgets to add (the editor's "Add new"). Not a default; in the add list.
 */
TileBase {
    id: tile
    objectName: "quickAddTile"
    title: ""
    backgroundTap: false
    // CP3A's Add tile builds a layout of its own (AddTileTileService.java:108-614; sysui has no M3_PL
    // tag anywhere), so the renderer reports no reserved icon and the app icon fades 500 ms after the
    // pager stops (D60-22)
    m3Layout: false
    // the tile has no body of its own: the shape fills the page
    readonly property real diameter: Theme.dp(100)

    TileCard {
        id: card
        objectName: "quickAddCard"
        // the whole shape is the button, centred on the page (the frame's body starts under the title slot)
        width: tile.diameter
        height: tile.diameter
        x: (tile.width - width) / 2 - tile.body.x
        y: (tile.height - height) / 2 - tile.body.y - Theme.dp(8)
        radius: width / 2
        containerColor: "transparent"
        contentColor: "#FFFFFF"
        preview: tile.preview
        //% "Add new widget"
        accessibleName: qsTrId("id-tile-add-new-widget")
        opensCarouselEditor: false
        onClicked: desktop.openTilesEditor(true)
        onLongPressed: desktop.openTilesEditor()

        Shape {
            id: shape
            objectName: "quickAddShape"
            anchors.fill: parent
            ShapePath {
                strokeColor: "transparent"
                strokeWidth: 0
                fillColor: TC.QUICKADD
                PathPolyline {
                    path: {
                        var flat = TC.scallop(shape.width / 2, shape.height / 2, shape.width / 2, 12, shape.width * 0.045, 360)
                        var out = []
                        for (var i = 0; i < flat.length; i += 2)
                            out.push(Qt.point(flat[i], flat[i + 1]))
                        out.push(out[0])
                        return out
                    }
                }
            }
        }
        // the plus: two bars
        Rectangle {
            objectName: "quickAddPlusH"
            anchors.centerIn: parent
            width: Theme.dp(32)
            height: Theme.dp(4)
            radius: height / 2
            color: "#FFFFFF"
        }
        Rectangle {
            objectName: "quickAddPlusV"
            anchors.centerIn: parent
            width: Theme.dp(4)
            height: Theme.dp(32)
            radius: width / 2
            color: "#FFFFFF"
        }
    }

    CurvedText {
        id: label
        objectName: "quickAddLabel"
        // along the edge of the page, not of the frame's body
        parent: tile
        x: 0
        y: 0
        width: tile.width
        height: tile.height
        //% "Add new"
        text: qsTrId("id-tile-add-new") + localeManager.changesObserver
        role: "arcLarge"
        color: Theme.color.onBackground
    }
}
