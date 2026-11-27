// Copyright (C) 2026 eos
// SPDX-License-Identifier: BSD-3-Clause
//
// The World clock complication with time zones (A-13), as stock's WorldClockProviderService and its zone
// chooser (WorldClockProviderConfigActivity), on a zone double with invented zones (the real offsets and the
// zone.tab list are tests/tst_worldzones.cpp):
//  - the rules: the time text (stock gyp.h: "HH:mm"; "h:mma" in 12 h when it fits 7 characters), the short
//    code of an old fixed offset, the region rows (sorted by name), the zone rows ("City (CODE)");
//  - the source: the zone's offset at `now` (a summer and a winter moment of an invented zone with summer
//    time), the code as the title (our caption), the city in a long slot, no AM/PM caption any more, an old
//    "+0530" slot still a fixed offset, an unknown zone "- -";
//  - a tap: the zone chooser of that slot is asked for (face, slot, zone);
//  - the chooser: the regions sorted by name, opened on the slot's region; a region opens its zones in the
//    double's order; back goes to the regions, back again closes; a pick is stored for the face's slot (with
//    the face's other slots kept) and given as the source.
// Staged as module LauncherQml (MODE=amb, as tst_ambientsources.qml) with the chooser and the editor lists.
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

    // the zone double: invented ids, an invented summer time (+1 from April to September)
    QtObject {
        id: zoneDouble
        readonly property var table: ({
            "Test/Summer_Town": { region: "europe", winter: 60, summer: 120, code: "STO", city: "Summer Town" },
            "Test/Fixed_Two": { region: "europe", winter: 120, summer: 120, code: "FTW", city: "Fixed Two" },
            "Test/West_Point": { region: "northamerica", winter: -300, summer: -240, code: "WPO", city: "West Point" },
            "Etc/UTC": { region: "universal", winter: 0, summer: 0, code: "UTC", city: "UTC" }
        })
        property int asked: 0
        function isZone(id) { return table[id] !== undefined }
        function summer(ms) { var m = new Date(ms).getUTCMonth(); return m >= 3 && m <= 8 }
        function offsetMinutes(id, ms) {
            asked++
            var z = table[id]
            return z ? (summer(ms) ? z.summer : z.winter) : -100000
        }
        function code(id) { return table[id] ? table[id].code : "" }
        function city(id) { return table[id] ? table[id].city : "" }
        function regions() { return ["europe", "northamerica", "universal"] }
        function regionOfZone(id) { return table[id] ? table[id].region : "" }
        function zones(region, ms) {
            var out = []
            for (var id in table)
                if (table[id].region === region)
                    out.push({ id: id, city: table[id].city, code: table[id].code, offset: offsetMinutes(id, ms) })
            out.sort(function (a, b) { return a.offset - b.offset || (a.city < b.city ? -1 : 1) })
            return out
        }
    }

    ComplicationSources {
        id: sources
        active: true
        zones: zoneDouble
        now: new Date(Date.UTC(2026, 0, 15, 9, 10, 0))
    }
    WorldClockChooser {
        id: chooser
        sources: sources
    }
    SignalSpy { id: asks; target: sources; signalName: "worldClockChooserRequested" }
    SignalSpy { id: picks; target: chooser; signalName: "picked" }
    SignalSpy { id: closes; target: chooser; signalName: "closed" }

    // the wall clock of a UTC moment in a zone of `minutes`, as the source shows it in 24 h
    function hhmm(ms, minutes) {
        var d = new Date(ms + minutes * 60000)
        return C.pad2(d.getUTCHours()) + ":" + C.pad2(d.getUTCMinutes())
    }

    TestCase {
        name: "WorldClock"
        when: windowShown

        function init() {
            Backend.reset()
            sources.use12h = false
            sources.now = new Date(Date.UTC(2026, 0, 15, 9, 10, 0))
            chooser.closeNow()
            asks.clear()
            picks.clear()
            closes.clear()
        }

        function test_01_rules() {
            var d = new Date(2026, 0, 15, 21, 5)
            compare(C.worldClockText(d, false, "AM", "PM"), "21:05")
            compare(C.worldClockText(new Date(2026, 0, 15, 9, 5), false, "AM", "PM"), "09:05")
            compare(C.worldClockText(d, true, "AM", "PM"), "9:05PM")
            compare(C.worldClockText(new Date(2026, 0, 15, 0, 30), true, "AM", "PM"), "12:30AM")
            // a marker that makes "12:mm" longer than 7: stock drops it
            compare(C.worldClockText(d, true, "a.m.", "p.m."), "9:05")
            compare(C.worldClockText(d, true, "a m", "p m"), "9:05pm")
            compare(C.offsetCode(330), "+5:30")
            compare(C.offsetCode(-480), "-8")
            compare(C.offsetCode(0), "UTC")
            var rows = FE.regionRows(["universal", "europe", "northamerica"], { europe: "Europe", northamerica: "North America", universal: "Universal" })
            compare(rows.map(function (r) { return r.title }), ["Europe", "North America", "Universal"])
            verify(FE.isRegionRow(rows[0].value))
            compare(FE.regionOfRow(rows[1].value), "northamerica")
            compare(rows[0].icon, "ms-language")
            var z = FE.zoneRows([{ id: "Test/Summer_Town", city: "Summer Town", code: "STO" }])
            compare(z[0].value, "worldclock:Test/Summer_Town")
            compare(z[0].title, "Summer Town (STO)")
            verify(sources.isSource(z[0].value))
        }

        function test_02_the_zone_now_with_summer_time() {
            var id = "worldclock:Test/Summer_Town"
            var winter = sources.now.getTime()
            var d = sources.info(id)
            compare(d.known, true)
            compare(d.short, hhmm(winter, 60))
            compare(d.caption, "STO", "the zone's code as the title (stock), not AM/PM")
            compare(d.title, "Summer Town")
            compare(d.icon, "ms-language")
            // the same moment of the day in July: an hour later on the zone's clock
            sources.now = new Date(Date.UTC(2026, 6, 15, 9, 10, 0))
            d = sources.info(id)
            compare(d.short, hhmm(sources.now.getTime(), 120))
            verify(d.short !== hhmm(sources.now.getTime(), 60))
            // west of UTC, and a fixed one
            compare(sources.info("worldclock:Test/West_Point").short, hhmm(sources.now.getTime(), -240))
            compare(sources.info("worldclock:Test/Fixed_Two").short, hhmm(sources.now.getTime(), 120))
            compare(sources.info("worldclock:Etc/UTC").caption, "UTC")
        }

        function test_03_twelve_hours_has_the_marker_in_the_text() {
            sources.use12h = true
            sources.now = new Date(Date.UTC(2026, 0, 15, 15, 10, 0))
            // 15:10 UTC is 17:10 in a zone of +2: "5:10" and the locale's PM marker when it fits
            var d = sources.info("worldclock:Test/Fixed_Two")
            var loc = Qt.locale()
            var am = loc.amText.replace(/\s/g, ""), pm = loc.pmText.replace(/\s/g, "")
            compare(d.short, 5 + Math.max(am.length, pm.length) <= 7 ? "5:10" + pm : "5:10")
            compare(d.caption, "FTW")
        }

        function test_04_old_offsets_and_unknown_zones() {
            var d = sources.info("worldclock:+0530")
            compare(d.known, true)
            compare(d.short, hhmm(sources.now.getTime(), 330))
            compare(d.caption, "+5:30")
            var u = sources.info("worldclock:Test/Nowhere")
            compare(u.known, false)
            compare(u.short, "- -")
            verify(sources.isSource("worldclock:Test/Summer_Town"))
            verify(!sources.isSource("worldclock"))
        }

        function test_05_a_tap_asks_for_the_zone_chooser_of_the_slot() {
            var view = { faceName: "021-classic", slotItem: { slotId: "bottom" } }
            sources.open("worldclock:Test/Summer_Town", view)
            compare(asks.count, 1)
            compare(asks.signalArguments[0][0], "021-classic")
            compare(asks.signalArguments[0][1], "bottom")
            compare(asks.signalArguments[0][2], "Test/Summer_Town")
        }

        function test_06_chooser_regions_then_zones() {
            chooser.openFor("Test/Summer_Town", "021-classic", "bottom")
            compare(chooser.shown, true)
            var rs = chooser.regionSheet
            compare(rs.shown, true)
            compare(rs.title, "World clock")
            compare(rs.model.map(function (r) { return r.title }), ["Europe", "North America", "Universal"])
            compare(rs.current, 0, "opened on the slot's region")
            verify(chooser.rotaryTarget === rs.list)
            // a region: its zones, by offset then name (the double's order), "City (CODE)"
            rs.picked(rs.model[0].value)
            var zs = chooser.zoneSheet
            compare(zs.shown, true)
            compare(zs.title, "Europe")
            compare(zs.model.map(function (r) { return r.title }), ["Summer Town (STO)", "Fixed Two (FTW)"])
            compare(zs.current, 0, "on the slot's zone")
            verify(chooser.rotaryTarget === zs.list)
            // back: the regions again; back again: closed, nothing picked
            verify(chooser.back())
            compare(zs.shown, false)
            compare(rs.shown, true)
            verify(chooser.back())
            compare(chooser.shown, false)
            compare(closes.count, 1)
            compare(picks.count, 0)
            compare(Backend.confHas("/org/asteroidos/watchface/complications/021-classic"), false)
        }

        function test_07_a_pick_is_stored_for_the_slot() {
            Backend.confSet("/org/asteroidos/watchface/complications/021-classic", ["top=steps"])
            chooser.openFor("+0530", "021-classic", "bottom")
            compare(chooser.regionSheet.current, 0, "an old offset has no region: the first row")
            chooser.regionSheet.picked(chooser.regionSheet.model[1].value)
            compare(chooser.zoneSheet.model[0].value, "worldclock:Test/West_Point")
            chooser.zoneSheet.picked(chooser.zoneSheet.model[0].value)
            compare(chooser.shown, false)
            compare(picks.count, 1)
            compare(picks.signalArguments[0][0], "worldclock:Test/West_Point")
            compare(Backend.confGet("/org/asteroidos/watchface/complications/021-classic").join(), "bottom=worldclock:Test/West_Point,top=steps")
        }

        function test_08_the_editor_way_stores_nothing_itself() {
            chooser.openFor("", "", "")
            chooser.regionSheet.picked(chooser.regionSheet.model[2].value)
            compare(chooser.zoneSheet.model.length, 1)
            chooser.zoneSheet.picked(chooser.zoneSheet.model[0].value)
            compare(picks.signalArguments[0][0], "worldclock:Etc/UTC")
            compare(Backend.confHas("/org/asteroidos/watchface/complications/"), false)
        }

        function test_09_shot() {
            chooser.openFor("Test/Summer_Town", "x", "y")
            chooser.regionSheet.picked(chooser.regionSheet.model[0].value)
            wait(200)
            var got = { ok: false }
            root.grabToImage(function (r) { got.r = r; got.ok = true })
            tryVerify(function () { return got.ok }, 10000)
            verify(got.r.saveToFile("/tmp/r5aod-shots/a13-zones.png"))
            chooser.closeNow()
            chooser.openFor("Test/Summer_Town", "x", "y")
            wait(200)
            got = { ok: false }
            root.grabToImage(function (r) { got.r = r; got.ok = true })
            tryVerify(function () { return got.ok }, 10000)
            verify(got.r.saveToFile("/tmp/r5aod-shots/a13-regions.png"))
            chooser.closeNow()
        }
    }
}
