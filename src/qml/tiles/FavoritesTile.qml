/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.controls
import org.asteroid.contacts
import "tilecontent.js" as TC

/*
 * Favorites, as the Google Contacts tile (tiles-individual-27; STRINGS contacts favorite_contacts_tile_*): the title
 * "Favorites", the photos of four starred contacts in two rows of two (a letter on a colour for one without a
 * photo, as the Contacts app shows them), the edge button "See all" (the Contacts app). A tap on a photo opens that
 * contact in the Contacts app. Without starred contacts: "Add contacts to your Favorites to see them here" and the
 * button "Add"; when the phone does not answer and nothing is cached: "To see favorites here, add them on your
 * phone" and "Refresh". The contacts, their stars and photos are the Contacts module's (org.asteroid.contacts
 * ContactsLink: the phone over Gadgetbridge, the numbers kept on the phone, DECISIONS Q38; the list and the small
 * photos are cached by the module).
 *
 * Battery (M1): the list is read from the cache when the tile comes on screen and asked of the phone at most once in
 * ten minutes (one round trip over Bluetooth); nothing is polled and nothing runs while the tile is off screen.
 */
TileBase {
    id: tile
    objectName: "favoritesTile"
    //% "Favorites"
    title: qsTrId("id-tile-favorites") + localeManager.changesObserver
    backgroundTap: false
    chipText: (tile.mode === "grid"
               //% "See all"
               ? qsTrId("id-tile-see-all")
               : tile.mode === "empty"
                 //% "Add"
                 ? qsTrId("id-tile-add")
                 //% "Refresh"
                 : tile.mode === "trouble" ? qsTrId("id-tile-refresh") : "") + localeManager.changesObserver
    onChipClicked: {
        if (tile.mode === "trouble")
            link.retry()
        else
            desktop.launchByName("asteroid-contacts", null)
    }

    ConfigurationValue { id: contactsRequest; key: "/org/asteroidos/contacts/ui/open"; defaultValue: "" }

    ContactsLink {
        id: link
        objectName: "favoritesLink"
    }
    readonly property alias contactsLink: link

    // the list is asked of the phone at most once in ten minutes
    property real loadedAt: 0
    property int refreshMs: 600000
    function refresh() {
        var now = Date.now()
        if (loadedAt > 0 && now - loadedAt < refreshMs && link.phase === "ready")
            return
        loadedAt = now
        link.load()
    }
    onLiveChanged: if (live) Qt.callLater(function () { if (live && !preview) refresh() })
    // after the editor has said it is a picture (a preview asks the phone for nothing)
    Component.onCompleted: Qt.callLater(function () { if (live && !preview) refresh() })

    readonly property var shown: TC.favorites(link.contacts, 4)
    // "grid" (starred contacts), "empty" (the list is there and none is starred), "trouble" (no list), "loading"
    readonly property string mode: shown.length > 0 ? "grid"
                                   : link.contacts.length > 0 || link.phase === "ready" ? "empty"
                                   : link.phase === "loading" || link.phase === "idle" ? "loading" : "trouble"

    Grid {
        id: grid
        objectName: "favoritesGrid"
        visible: tile.mode === "grid"
        anchors.centerIn: parent
        columns: 2
        spacing: Theme.dp(4)
        readonly property real cell: Math.min((tile.body.height - spacing) / 2, (tile.body.width * 0.6 - spacing) / 2)
        Repeater {
            model: tile.shown
            delegate: TileCard {
                id: cell
                objectName: "favorite" + index
                width: grid.cell
                height: grid.cell
                containerColor: Theme.color.surfaceContainer
                contentColor: Theme.color.onSurface
                preview: tile.preview
                accessibleName: modelData.name
                onClicked: {
                    contactsRequest.value = "contact:" + modelData.key + "@" + Date.now()
                    desktop.launchByName("asteroid-contacts", cell)
                }
                ContactPhoto {
                    anchors.centerIn: parent
                    size: cell.width
                    link: link
                    key: modelData.key
                    name: modelData.name
                    hasPhoto: modelData.photo === true
                }
            }
        }
    }

    Label {
        id: message
        objectName: "favoritesMessage"
        visible: tile.mode === "empty" || tile.mode === "trouble"
        anchors.centerIn: parent
        width: parent.width - Theme.dp(8)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: (tile.mode === "empty"
               //% "Add contacts to your Favorites to see them here"
               ? qsTrId("id-tile-fav-add-text")
               //% "To see favorites here, add them on your phone"
               : qsTrId("id-tile-fav-setup-text")) + localeManager.changesObserver
        role: "bodyMedium"
        color: Theme.color.onSurface
    }
}
