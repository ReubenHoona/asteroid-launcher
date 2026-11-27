// Copyright (C) 2026 eos
// SPDX-License-Identifier: BSD-3-Clause
//
// A-16: two stock complication sources the face editor did not have:
//  - Show map (Google Maps' MapsLocationComplicationDataSourceService, ICON): the Map app's icon, "Show map",
//    a tap opens the Map app (stock: the map at the watch's place);
//  - Favorite contact (Google Contacts' ContactsComplicationProviderService, SMALL_IMAGE PHOTO, chosen with
//    ACTION_CHOOSE_CONTACTS_COMPLICATION): the slot keeps the contact (key and name); the photo from the Contacts
//    module's cache, else the letter on its colour (the module's own rule, as the Contacts app's monogram), a name
//    with no letter first gets the contact icon; a tap opens the Contacts app on the contact; the chooser's rows
//    are the module's list, starred first, then by name; nothing of the module is made unless a slot shows a
//    contact (or the editor lists them).
// Invented contacts only. Staged as tst_ambientsources.qml (MODE=amb) with ContactSource.qml; shot in
// /tmp/r5aod-shots/a16-slots.png.
import QtQuick
import QtTest
import LauncherTest
import LauncherQml
import "LauncherQml/complications/complications.js" as C
import "LauncherQml/complications/faceeditor.js" as FE

Item {
    id: root
    width: 384
    height: 384

    QtObject { id: localeManager; property string changesObserver: "" }
    QtObject {
        id: desktop
        property var launched: []
        function launchByName(name, origin) { launched = launched.concat([name]) }
    }

    ComplicationSources {
        id: sources
        active: true
        now: new Date(2026, 10, 25, 15, 0, 0)
    }

    property var shown: []
    function show(id) {
        var v = { source: id, slotItem: null }
        shown.push(v)
        sources.register(v)
        return v
    }

    Rectangle {
        id: face
        width: 384; height: 384
        color: "black"
        visible: false
        Repeater {
            model: [sources.contactParam("k1", "Ada Test"), sources.contactParam("k2", "7 Test"), "map"]
            delegate: Item {
                required property int index
                required property string modelData
                objectName: "eosComplication"
                property string slotId: "s" + index
                property string shape: "bulb"
                property string defaultSource: index < 2 ? "contact:" + modelData : modelData
                property color tint: "#A8C7FA"
                x: 40 + index * 110
                y: 149
                width: 86
                height: 86
            }
        }
    }

    TestCase {
        name: "ContactAndMap"
        when: windowShown

        function init() {
            Backend.reset()
            desktop.launched = []
        }
        function cleanup() {
            for (var i = 0; i < shown.length; i++)
                sources.unregister(shown[i])
            shown = []
            tryVerify(function () { return JSON.stringify(sources.demand) === "{}" }, 1000)
        }

        function test_01_sources_and_names() {
            verify(sources.isSource("map"))
            verify(!sources.isSource("contact"), "a contact needs its choice")
            verify(sources.parameterised.indexOf("contact") >= 0)
            verify(sources.isSource("contact:" + sources.contactParam("k1", "Ada Test")))
            compare(sources.name("map"), "Show map")
            compare(sources.name("contact"), "Favorite contact")
            compare(FE.appOf("map"), "maps")
            compare(FE.appOf("contact"), "contacts")
            // nothing of the Contacts module is made while no slot shows a contact
            compare(sources.contactSource, null)
        }

        function test_02_show_map() {
            var d = sources.info("map")
            compare(d.type, "icon")
            compare(d.title, "Show map")
            verify(d.icon !== "")
            sources.open("map", null)
            compare(desktop.launched, ["asteroid-map"])
            // it stays in the always-on screen (nothing in it goes stale)
            sources.ambient = true
            sources.hubDrawn = true
            compare(sources.info("map").text, "Show map")
            sources.ambient = false
            sources.hubDrawn = false
        }

        function test_03_contact_param_round_trip() {
            var p = sources.contactParam("k:1/2", "Ada \"Test\"")
            var c = sources.contactOf(p)
            compare(c.key, "k:1/2")
            compare(c.name, "Ada \"Test\"")
            compare(sources.contactOf("junk"), null)
            compare(sources.contactOf(""), null)
            var bad = sources.info("contact:junk")
            compare(bad.known, false)
        }

        function test_04_contact_letter_without_photo() {
            var id = "contact:" + sources.contactParam("k1", "Ada Test")
            show(id)
            tryVerify(function () { return sources.contactSource !== null })
            var d = sources.info(id)
            compare(d.type, "smallimage")
            compare(d.image, "", "no photo cached")
            compare(d.letter, "A")
            verify(d.tileColor !== "")
            compare(d.tileColor, sources.contactSource.colorOf("Ada Test"), "the module's colour rule")
            compare(d.title, "Ada Test")
            // a name with no letter first: the contact icon
            var n = sources.info("contact:" + sources.contactParam("k2", "7 Test"))
            compare(n.type, "icon")
            compare(n.icon, "ios-contact")
        }

        function test_05_contact_tap_opens_the_contact() {
            sources.open("contact:" + sources.contactParam("k1", "Ada Test"), null)
            compare(desktop.launched, ["asteroid-contacts"])
            var r = String(Backend.confGet("/org/asteroidos/contacts/ui/open"))
            verify(r.indexOf("contact:k1@") === 0, r)
        }

        function test_06_chooser_rows() {
            var list = [{ key: "b", name: "Bea Test", starred: false }, { key: "z", name: "Zed Test", starred: true },
                        { key: "a", name: "Ann Test", starred: false }, { key: "", name: "No Key" }, null]
            var rows = FE.contactRows(list, function (k, n) { return sources.contactParam(k, n) })
            compare(rows.map(function (r) { return r.title }), ["Zed Test", "Ann Test", "Bea Test"])
            verify(sources.isSource(rows[0].value))
            compare(sources.contactOf(rows[1].value.slice(8)).key, "a")
        }

        function test_07_shot() {
            sources.attach(face, "file:///tmp/r5aod-a16.qml")
            face.visible = true
            wait(300)
            var got = { ok: false }
            face.grabToImage(function (r) { got.r = r; got.ok = true })
            tryVerify(function () { return got.ok }, 10000)
            verify(got.r.saveToFile("/tmp/r5aod-shots/a16-slots.png"))
            var m = []
            function walk(it) { if (!it) return; if (it.objectName === "eosMonogram" && it.visible) m.push(it); for (var i = 0; i < it.children.length; i++) walk(it.children[i]) }
            walk(face)
            compare(m.length, 1, "one letter tile (the other contact has no letter: its icon)")
            face.visible = false
            // the views go: nothing shown any more
            var views = []
            function views_(it) { if (!it) return; if (it.objectName === "eosComplicationView") views.push(it); for (var i = 0; i < it.children.length; i++) views_(it.children[i]) }
            views_(face)
            for (var v = 0; v < views.length; v++)
                views[v].destroy()
        }
    }
}
