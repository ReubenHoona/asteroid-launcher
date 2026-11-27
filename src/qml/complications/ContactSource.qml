/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.contacts

/*
 * The Favorite contact complication's data (A-16), as Google Contacts'
 * ContactsComplicationProviderService: the chosen contact's photo (SMALL_IMAGE,
 * PHOTO style), a letter on its colour when there is no photo, as the Contacts
 * app draws one. Made by ComplicationSources only while a slot shows a contact
 * or the face editor lists them.
 *
 * The photo comes from the Contacts module's cache (ContactStore: a few small
 * photos the Contacts app or the Favorites tile fetched); nothing is asked of
 * the phone to draw the face. The editor's list is the module's ContactsLink:
 * the cached list at once, then the phone's (one round trip over Bluetooth, as
 * the Contacts app when it opens: only while the editor lists them).
 */
Item {
    id: src
    visible: false

    ContactStore { id: store }
    ContactsLink { id: link }
    readonly property alias contacts: link.contacts
    readonly property alias phase: link.phase
    // changes when a photo was saved (bindings on photoOf follow it)
    readonly property int photoRevision: link.photoRevision

    function photoOf(key, revision) {
        return key ? String(store.photoUrl(key)) : ""
    }
    // the letter and its tile colour, as the Contacts app's monogram (the module's ContactsLogic: initial,
    // tileColor); no letter (a digit or a symbol first) is "" (the icon then)
    function letterOf(name) { return ContactsLogic.initial(String(name || "")) }
    function colorOf(name) { return String(ContactsLogic.tileColor(String(name || ""))) }
    // the editor's list: the cached contacts at once, the phone's when it answers
    function load() { link.load() }
}
