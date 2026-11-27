/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

// R5 B-04: the open card's conversation (NotificationConversation.qml) with the times and avatars asteroid-btsyncd
// passes (x-asteroid-messages: ts seconds, a the avatar's file): stock's time section headers (hfu.l / kha.b: the
// first message with a time and each one an hour or more after the one before; kls words: Now, %dm ago, the time,
// the weekday and time, the month, day and time) and the sender row's 18 dp round avatar, 4 dp before the name
// (grw.java am()); a run of the others' bubbles is cut where a minute passed (kha.d). Invented senders and texts
// only. The avatar picture is one of the image's face previews (read only through the -L root). MODE=st.
import QtQuick
import QtTest
import org.asteroid.controls
import LauncherTest
import "st/qml"

Item {
    id: top
    width: 384
    height: 520

    Rectangle { anchors.fill: parent; color: "black" }

    readonly property string avatarFile: "/usr/share/asteroid-launcher/watchfaces-preview/182/000-default-digital.png"

    QtObject {
        id: card
        property string summary: "Weekend plans"
        property var hints: ({})
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: conv.height + 40
        NotificationConversation {
            id: conv
            x: 24
            y: 20
            width: 336
            notification: card
        }
    }

    TestCase {
        name: "Conversation"
        when: windowShown

        // now, in seconds; the messages are placed before it
        property real nowS: 0

        function set(list) {
            card.hints = { "x-asteroid-messages": JSON.stringify(list) }
            wait(60)
        }
        function bubbles() {
            var out = []
            for (var i = 0; i < conv.children.length; i++)
                if (conv.children[i].objectName === "bubble")
                    out.push(conv.children[i])
            return out
        }
        function init() {
            Backend.reset()
            Backend.confSet("/org/asteroidos/settings/use-12h-format", false)
            nowS = Math.floor(Date.now() / 1000)
        }

        function test_01_the_words_of_a_header() {
            var now = nowS * 1000
            compare(conv.sectionText(nowS - 10, now, false), "Now")
            compare(conv.sectionText(nowS - 5 * 60, now, false), "5m ago")
            compare(conv.sectionText(nowS - 59 * 60, now, false), "59m ago")
            var d = new Date((nowS - 3 * 3600) * 1000)
            compare(conv.sectionText(nowS - 3 * 3600, now, false), Qt.formatTime(d, "HH:mm"))
            compare(conv.sectionText(nowS - 3 * 3600, now, true), Qt.formatTime(d, "h:mm AP"))
            var d2 = new Date((nowS - 2 * 86400) * 1000)
            compare(conv.sectionText(nowS - 2 * 86400, now, false), Qt.formatDate(d2, "ddd") + " " + Qt.formatTime(d2, "HH:mm"))
            var d3 = new Date((nowS - 9 * 86400) * 1000)
            compare(conv.sectionText(nowS - 9 * 86400, now, false), Qt.formatDate(d3, "MMM d") + ", " + Qt.formatTime(d3, "HH:mm"))
        }

        function test_02_when_a_header_shows() {
            verify(conv.sectionShown(null, { ts: 100 }), "the first with a time")
            verify(!conv.sectionShown(null, { ts: 0 }), "no time, no header")
            verify(!conv.sectionShown({ ts: 100 }, { ts: 100 + 3599 }), "within the hour")
            verify(conv.sectionShown({ ts: 100 }, { ts: 100 + 3600 }), "an hour later")
            verify(conv.sectionShown({ ts: 0 }, { ts: 5000 }), "the one before had no time")
            // a run is cut where a minute passed
            verify(conv.sameRun({ me: false, s: "Alex", ts: 100 }, { me: false, s: "Alex", ts: 159 }))
            verify(!conv.sameRun({ me: false, s: "Alex", ts: 100 }, { me: false, s: "Alex", ts: 160 }))
            verify(conv.sameRun({ me: false, s: "Alex", ts: 0 }, { me: false, s: "Alex", ts: 500 }), "no time: as before")
            verify(!conv.sameRun({ me: true, s: "", ts: 100 }, { me: true, s: "", ts: 400 }))
        }

        function test_03_a_group_with_times_and_avatars() {
            set([{ s: "Alex", t: "Are we still on for Saturday?", ts: nowS - 2 * 3600, a: top.avatarFile },
                 { s: "Alex", t: "I can bring the map", ts: nowS - 2 * 3600 + 20, a: top.avatarFile },
                 { s: "Sam", t: "Yes, ten o'clock", ts: nowS - 2 * 3600 + 90 },
                 { s: "Me", t: "See you there", me: true, ts: nowS - 3 * 60 }])
            var b = bubbles()
            compare(b.length, 4)
            // headers: before the first, and before the last (more than an hour later)
            verify(b[0].sectioned)
            verify(!b[1].sectioned)
            verify(!b[2].sectioned)
            verify(b[3].sectioned)
            compare(b[3].section.text, "3m ago")
            compare(b[0].section.text, Qt.formatTime(new Date((nowS - 2 * 3600) * 1000), "HH:mm"))
            compare(b[0].section.horizontalAlignment, Text.AlignHCenter)
            // the sender rows: Alex with the avatar, Sam without (none sent); the run of Alex's two goes on
            verify(b[0].named)
            verify(b[0].hasAvatar)
            verify(b[1].joinedAbove)
            verify(!b[1].named)
            verify(b[2].named)
            verify(!b[2].hasAvatar)
            compare(b[0].avatar.width, Theme.dp(18))
            compare(b[0].avatar.radius, Theme.dp(9))
            tryVerify(function () { return b[0].avatar.pictureState === 1 }, 5000, "the avatar loaded")
            var nameX = b[0].sender.mapToItem(b[0], 0, 0).x
            var avX = b[0].avatar.mapToItem(b[0], 0, 0).x
            compare(nameX - avX, Theme.dp(18) + Theme.dp(4))
            // the header gaps: 2 dp above the first header, 8 dp above a later one
            compare(b[0].topGap, Theme.dp(2))
            compare(b[3].topGap, Theme.dp(8))
            // the avatars are no message pictures (the big picture of the card is not suppressed by them)
            compare(conv.picturePaths.length, 0)
            wait(200)
            grabImage(top).save("/tmp/r5ui-shots/b04-conversation.png")
        }

        function test_04_without_times_or_avatars_as_before() {
            set([{ s: "Alex", t: "hello" }, { s: "Alex", t: "again" }, { s: "Sam", t: "hi" }])
            var b = bubbles()
            compare(b.length, 3)
            for (var i = 0; i < 3; i++) {
                verify(!b[i].sectioned)
                verify(!b[i].hasAvatar)
            }
            verify(b[1].joinedAbove)
            compare(b[0].topGap, 0)
        }
    }
}
