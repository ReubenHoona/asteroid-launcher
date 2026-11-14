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
 * Contact, as the Google Contacts tile (tiles-individual-27; STRINGS contacts single_contact_tile_*): the title is the
 * contact's name, under it the round photo (a letter on a colour without one) and the buttons "Call" and "Text".
 * Nothing chosen yet: "Select who you want to quickly reach out to" and the edge button "Select".
 *
 * Call asks the phone for the contact's numbers (the Contacts module, numbers stay on the phone) and calls the only or
 * the default one through Gadgetbridge; with several, or when the phone cannot, the Contacts app opens on the
 * contact (its "Choose a number" and its messages). Text opens the Contacts app on the contact.
 * The chosen contact is dconf /org/asteroidos/launcher/tile-contact (JSON { "k": key, "n": name, "p": 1 if it has a
 * photo }); "Select" asks the Contacts app to pick one (/org/asteroidos/contacts/ui/open = "pick-tile@<ms>"): the app's
 * half of that is not built yet (NOTES.md).
 *
 * Battery (M1): nothing runs; the phone is asked only on a tap.
 */
TileBase {
    id: tile
    objectName: "contactTile"
    title: (tile.contact ? tile.contact.name
                         //% "Contact"
                         : qsTrId("id-tile-contact")) + localeManager.changesObserver
    backgroundTap: false
    chipText: (tile.contact ? ""
                            //% "Select"
                            : qsTrId("id-tile-select")) + localeManager.changesObserver
    onChipClicked: tile.select()

    ConfigurationValue { id: chosen; key: "/org/asteroidos/launcher/tile-contact"; defaultValue: "" }
    ConfigurationValue { id: contactsRequest; key: "/org/asteroidos/contacts/ui/open"; defaultValue: "" }

    readonly property var contact: TC.chosenContact(String(chosen.value))

    ContactsLink {
        id: link
        objectName: "contactLink"
    }
    readonly property alias contactsLink: link

    function select() {
        contactsRequest.value = "pick-tile@" + Date.now()
        desktop.launchByName("asteroid-contacts", null)
    }
    function openContact(from) {
        if (tile.contact)
            contactsRequest.value = "contact:" + tile.contact.key + "@" + Date.now()
        desktop.launchByName("asteroid-contacts", from)
    }
    // the only or the default number is called; anything else is the Contacts app's to ask
    function call(from) {
        if (!tile.contact)
            return
        link.numbers(tile.contact, function (r) {
            if (r.ok === true && r.numbers && r.numbers.length > 0) {
                var pick = r.numbers.length === 1 ? r.numbers[0] : null
                for (var i = 0; !pick && i < r.numbers.length; i++)
                    if (r.numbers[i].isDefault === true || r.numbers[i].def === true || r.numbers[i].d === 1)
                        pick = r.numbers[i]
                if (pick) {
                    link.call(pick, function (c) { if (c.ok !== true) tile.openContact(from) })
                    return
                }
            }
            tile.openContact(from)
        })
    }

    Column {
        id: column
        objectName: "contactBody"
        visible: tile.contact !== null
        anchors.fill: parent
        spacing: Theme.dp(4)

        TileCard {
            id: photoCard
            objectName: "contactPhoto"
            width: Theme.dp(44)
            height: width
            anchors.horizontalCenter: parent.horizontalCenter
            containerColor: Theme.color.surfaceContainer
            contentColor: Theme.color.onSurface
            preview: tile.preview
            accessibleName: tile.contact ? tile.contact.name : ""
            onClicked: tile.openContact(photoCard)
            ContactPhoto {
                anchors.centerIn: parent
                size: photoCard.width
                link: link
                key: tile.contact ? tile.contact.key : ""
                name: tile.contact ? tile.contact.name : ""
                hasPhoto: tile.contact ? tile.contact.photo : false
            }
        }

        Row {
            id: buttons
            spacing: Theme.dp(4)
            width: parent.width
            readonly property real buttonWidth: (width - spacing) / 2
            TileCard {
                id: callButton
                objectName: "contactCall"
                width: buttons.buttonWidth
                height: Math.min(Theme.dp(44), column.height - photoCard.height - column.spacing)
                containerColor: Theme.color.primary
                contentColor: Theme.color.onPrimary
                preview: tile.preview
                //% "Call"
                accessibleName: qsTrId("id-tile-call")
                onClicked: tile.call(callButton)
                Icon {
                    anchors.centerIn: parent
                    name: "ms-call"
                    color: Theme.color.onPrimary
                    width: Theme.dp(20)
                    height: width
                }
            }
            TileCard {
                id: textButton
                objectName: "contactText"
                width: buttons.buttonWidth
                height: callButton.height
                containerColor: Theme.color.surfaceContainerHigh
                contentColor: Theme.color.onSurface
                preview: tile.preview
                //% "Text"
                accessibleName: qsTrId("id-tile-text")
                onClicked: tile.openContact(textButton)
                Icon {
                    anchors.centerIn: parent
                    name: "ms-chat"
                    color: Theme.color.onSurface
                    width: Theme.dp(20)
                    height: width
                }
            }
        }
    }

    Label {
        id: setup
        objectName: "contactSetup"
        visible: tile.contact === null
        anchors.centerIn: parent
        width: parent.width - Theme.dp(8)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        //% "Select who you want to quickly reach out to"
        text: qsTrId("id-tile-contact-setup") + localeManager.changesObserver
        role: "bodyMedium"
        color: Theme.color.onSurface
    }
}
