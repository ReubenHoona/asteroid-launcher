/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.DBus
import Nemo.KeepAlive
import org.nemomobile.lipstick
import org.asteroid.controls
import "../desktop.js" as Desktop

/*
 * The assistant, as on a Pixel Watch 2 (Wear OS): over whatever shows, a
 * black screen with "Hi, how can I help?" and the four dots; they bounce
 * with the voice while it listens and the words appear as they are heard;
 * then the dots spin while it works the answer out, and the answer card
 * replaces them: the request on top, an icon, the answer in large type and a
 * spoken-style sentence, with up to three chips. A confirmation haptic
 * when the microphone is open.
 *
 * A tap cancels while it listens or thinks; a tap on the card closes it; the
 * crown and a swipe right close it at any time, and so does the display
 * going off. It opens on a hold of the side button (assistantKey), from the
 * app list's Assistant and from the Assistant tile (open(text) with a
 * suggestion's text asks that directly).
 *
 * The work is asteroid-assistant's (org.asteroidos.assistant, D-Bus
 * activated); the actions are AssistantActions'. Nothing animates once the
 * card is on screen.
 *
 * A card can ask back, as Wear OS does ("What's the message?", "Where to?"):
 * { dictate: true, prompt, onText: function (text, done, code) }. The overlay
 * shows the prompt and listens again (Dictate("assistant"): recognised where
 * the commands are, the phone's recogniser while it is connected); the text
 * goes to onText, "" when nothing was heard (code says why).
 *
 * The display stays on while it listens and thinks (mce's blanking pause; the
 * watch face is not the lock screen while the assistant shows, see
 * compositor.qml): before, the face's 10 s lock screen timeout blanked the
 * display during a slow answer, and the overlay closed with it.
 */
Item {
    id: overlay
    anchors.fill: parent

    property bool shown: false
    // starting | listening | recognising | thinking | card
    property string phase: "starting"
    property real level: 0
    property string heard: ""
    property string request: ""
    property var cardData: null
    property int session: 0
    // a session's result belongs to the overlay that started it
    property bool waitingStart: false
    // the session's Result came (its actions may still be working)
    property bool resultSeen: false
    // one per open(): what an action or a chip answers late (a phone
    // query, a reply being sent) is dropped once another session began
    property int generation: 0
    // the card's question being listened for ({ prompt, onText }), else null
    property var followUp: null
    // what the listening page asks: "Hi, how can I help?" unless a card asked
    property string promptText: ""
    readonly property bool active: shown

    visible: opacity > 0
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.92
    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0, 0.2, 1, 1, 1] } }
    Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0, 0.2, 1, 1, 1] } }

    function loc(id, en) {
        var s = qsTrId(id)
        return (s === id || s === "") ? en : s
    }

    function open(text) {
        if (shown && phase !== "card" && !text)
            return
        swipe.reset()
        cardData = null
        heard = ""
        request = ""
        level = 0
        session = 0
        resultSeen = false
        followUp = null
        promptText = ""
        generation++
        shown = true
        waitingStart = true
        if (text) {
            request = text
            phase = "thinking"
            daemon.typedCall("Ask", [{ "type": "s", "value": text }], started, failedStart)
        } else {
            phase = "starting"
            daemon.typedCall("Listen", [{ "type": "s", "value": "" }], started, failedStart)
        }
    }
    function started(s) {
        if (!waitingStart)
            return
        waitingStart = false
        if (!shown)
            return
        if (s > 0) {
            if (session === 0)
                session = s
        } else if (session === 0 && phase !== "card") {
            // the daemon refused (its Result names the reason, but it may
            // have come before this overlay listened to its signals)
            failedStart()
        }
    }
    function failedStart() {
        waitingStart = false
        showCard({ icon: "ios-alert", text: loc("id-asst-unavailable", "The assistant isn't available."), chips: [] })
    }
    function close() {
        if (!shown)
            return
        // Cancel() ends whatever session the daemon runs: only while this
        // overlay's own may still be going (not once its Result came, as
        // an action that opens an app closes the overlay)
        if (phase !== "card" && !resultSeen)
            daemon.typedCall("Cancel", [])
        shown = false
        phase = "starting"
    }
    // A card asked back: listen for the answer (same generation: the flow goes on)
    function startFollowUp(c) {
        cardData = null
        heard = ""
        request = ""
        level = 0
        session = 0
        resultSeen = false
        followUp = c
        promptText = c.prompt || ""
        waitingStart = true
        phase = "starting"
        daemon.typedCall("Dictate", [{ "type": "s", "value": "assistant" }], started, failedStart)
    }
    function stopListening() {
        if (phase === "listening")
            daemon.typedCall("Stop", [])
    }
    // The session this overlay started: the one whose "starting" state
    // comes while open() waits for Listen()/Ask() (the daemon emits it
    // before it returns), else the one they return. Not the first session
    // named: starting a session first ends the one going on (another
    // client's dictation: a btsyncd voice reply, the keyboard) with that
    // session's "idle", which used to be taken for this overlay's; every
    // signal of its own session was then ignored and the overlay stayed on
    // its first screen.
    function adopt(s, state) {
        if (shown && waitingStart && session === 0 && s > 0 && state === "starting")
            session = s
    }
    function mine(s) {
        return shown && s > 0 && s === session
    }
    function showCard(c) {
        cardData = c
        phase = "card"
        flick.contentY = 0
    }
    function handleResult(json) {
        resultSeen = true
        var g = generation
        var r
        try { r = JSON.parse(json) } catch (e) { r = { type: "error", text: loc("id-asst-error", "Something went wrong.") } }
        if (r.transcript)
            request = r.transcript
        if (followUp) {
            // the answer to a card's question: back to the action that asked
            var f = followUp
            followUp = null
            promptText = ""
            var text = r.type === "dictation" ? (r.text || "") : ""
            f.onText(text, function (c) { if (overlay.generation === g) overlay.done(c) }, r.type === "dictation" ? "" : (r.code || r.type))
            return
        }
        if (r.type === "cancel")
            return close()
        if (r.type === "intent") {
            actions.run(r.intent, r.slots, r.transcript, function (c) { if (overlay.generation === g) overlay.done(c) })
            return
        }
        if (r.type === "error") {
            showCard({ icon: r.code === "no-speech" ? "ios-mic-off-outline" : "ios-cloud-offline-outline",
                       text: r.text, chips: [{ label: loc("id-asst-try-again", "Try again"), icon: "ios-mic",
                                               run: function () { overlay.open("") } }] })
            return
        }
        showCard({ icon: r.icon || "ios-chatbubbles-outline", title: r.title || "", text: r.text || "",
                   chips: [], accent: r.via === "watch" ? "#a8c7fa" : "#c3e7ff" })
    }
    // what an action gives back: a card, or close (then an app opens)
    function done(c) {
        if (!shown)
            return
        if (c && c.dictate)
            return startFollowUp(c)
        if (c && c.close) {
            close()
            if (c.confirm && Desktop.confirmation)
                Desktop.confirmation.show(c.confirm)
            if (c.then)
                c.then()
            return
        }
        showCard(c)
    }

    DBusInterface {
        id: daemon
        bus: DBus.SessionBus
        service: "org.asteroidos.assistant"
        path: "/org/asteroidos/assistant"
        iface: "org.asteroidos.assistant"
        // always on: the first signals come before Listen() returns
        signalsEnabled: true

        function rcStateChanged(s: int, state: string) {
            overlay.adopt(s, state)
            if (!overlay.mine(s) || overlay.phase === "card")
                return
            if (state === "idle" && !overlay.resultSeen) {
                // the daemon dropped this session without a result (another
                // client started one): nothing more will come for it
                overlay.shown = false
                overlay.phase = "starting"
                return
            }
            if (state === "listening" && overlay.phase !== "listening") {
                overlay.phase = "listening"
                // the microphone is open: Wear OS's ready haptic
                Haptics.confirm()
            } else if (state === "recognising" || state === "thinking") {
                // the user is done: the dots spin while it works it out
                overlay.phase = "thinking"
            }
        }
        function rcLevel(l: real) {
            if (overlay.shown && overlay.phase === "listening")
                overlay.level = l
        }
        function rcPartial(s: int, text: string) {
            if (overlay.mine(s) && overlay.phase !== "card")
                overlay.heard = text
        }
        function rcTranscript(s: int, text: string) {
            if (overlay.mine(s)) {
                overlay.heard = text
                overlay.request = text
                if (overlay.phase !== "card")
                    overlay.phase = "thinking"
            }
        }
        function rcResult(s: int, json: string) {
            if (overlay.mine(s))
                overlay.handleResult(json)
        }
    }

    AssistantActions { id: actions }

    // the display stays on while the assistant listens and thinks, as Wear OS
    // keeps the screen on for it; the card then times out as usual
    DisplayBlanking {
        preventBlanking: overlay.shown && overlay.phase !== "card"
    }

    // the screen goes away with the display, as Wear OS returns to the face
    Connections {
        target: typeof Lipstick !== "undefined" && Lipstick.compositor ? Lipstick.compositor : null
        ignoreUnknownSignals: true
        function onDisplayOff() { overlay.close() }
    }

    BackSwipeArea {
        id: swipe
        anchors.fill: parent
        swipeEnabled: overlay.shown
        onFinished: {
            if (progress >= 0.5 || flung) {
                overlay.close()
                reset()
            } else {
                settle.start()
            }
        }
        NumberAnimation { id: settle; target: swipe; property: "value"; to: 0; duration: 200
            easing.type: Easing.BezierSpline; easing.bezierCurve: [0, 0, 0.2, 1, 1, 1]; onFinished: swipe.reset() }

        Item {
            id: content
            width: parent.width
            height: parent.height
            x: swipe.value
            opacity: 1 - 0.6 * swipe.progress

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "#000000"
            }

            // a tap: cancel while it listens or thinks, close on the card
            MouseArea {
                anchors.fill: parent
                onClicked: overlay.close()
            }

            /* listening */
            Item {
                id: listenPage
                anchors.fill: parent
                visible: overlay.phase !== "card"

                Label {
                    id: prompt
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.round(parent.height * 0.2)
                    width: Math.round(parent.width * 0.7)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    visible: overlay.heard === "" && overlay.request === ""
                    opacity: 0.75
                    text: overlay.phase === "thinking" ? ""
                          : overlay.promptText !== "" ? overlay.promptText : overlay.loc("id-asst-hi", "Hi, how can I help?")
                    font.pixelSize: Math.round(parent.height * 0.062)
                }

                // what is heard, as it is heard (the newest words stay in sight)
                Label {
                    id: heardText
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: dots.top
                    anchors.bottomMargin: Math.round(parent.height * 0.06)
                    width: Math.round(parent.width * 0.78)
                    height: Math.round(parent.height * 0.42)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignBottom
                    wrapMode: Text.Wrap
                    elide: Text.ElideLeft
                    maximumLineCount: 4
                    text: overlay.heard !== "" ? overlay.heard : overlay.request
                    font.pixelSize: Math.round(parent.height * 0.072)
                    font.styleName: "SemiCondensed Medium"
                }

                AssistantDots {
                    id: dots
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.round(parent.height * 0.66)
                    width: Math.round(parent.width * 0.42)
                    height: Math.round(parent.height * 0.2)
                    mode: !overlay.shown || overlay.phase === "card" ? "hidden"
                          : overlay.phase === "listening" ? "listening"
                          : overlay.phase === "starting" ? "starting" : "thinking"
                    level: overlay.level
                }
            }

            /* the answer */
            Flickable {
                id: flick
                anchors.fill: parent
                visible: overlay.phase === "card" && overlay.cardData !== null
                contentHeight: cardColumn.height + Math.round(height * 0.3)
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                interactive: contentHeight > height

                MouseArea {
                    width: flick.width
                    height: Math.max(flick.height, flick.contentHeight)
                    onClicked: overlay.close()
                }

                Column {
                    id: cardColumn
                    width: Math.round(flick.width * 0.76)
                    x: Math.round((flick.width - width) / 2)
                    y: Math.round(flick.height * 0.12)
                    spacing: Math.round(flick.height * 0.025)
                    readonly property var c: overlay.cardData || ({})

                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        visible: overlay.request !== ""
                        opacity: 0.6
                        text: overlay.request
                        font.pixelSize: Math.round(flick.height * 0.045)
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.round(flick.width * 0.15)
                        height: width
                        radius: width / 2
                        color: cardColumn.c.accent || "#a8c7fa"
                        visible: (cardColumn.c.icon || "") !== ""
                        Icon {
                            anchors.centerIn: parent
                            width: parent.width * 0.58
                            height: width
                            name: cardColumn.c.icon || ""
                            color: "#000000"
                        }
                    }

                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        visible: (cardColumn.c.title || "") !== ""
                        text: cardColumn.c.title || ""
                        font.pixelSize: Math.round(flick.height * (String(cardColumn.c.title || "").length > 12 ? 0.075 : 0.12))
                        font.styleName: "SemiCondensed Medium"
                    }

                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: cardColumn.c.text || ""
                        font.pixelSize: Math.round(flick.height * 0.058)
                        lineHeight: 1.05
                    }

                    // chips: Wear OS's compact chips, side by side or stacked
                    Flow {
                        width: parent.width
                        spacing: Math.round(flick.width * 0.02)
                        visible: chips.count > 0
                        topPadding: Math.round(flick.height * 0.015)
                        Repeater {
                            id: chips
                            model: (cardColumn.c.chips || []).length
                            delegate: MouseArea {
                                readonly property var chip: cardColumn.c.chips[index]
                                width: chips.count === 1 ? cardColumn.width : Math.floor((cardColumn.width - (chips.count > 2 ? 0 : parent.spacing)) / (chips.count > 2 ? 1 : 2))
                                height: Math.round(flick.height * 0.14)
                                onClicked: {
                                    Haptics.click()
                                    var g = overlay.generation
                                    if (chip && chip.run)
                                        chip.run(function (c) { if (overlay.generation === g) overlay.done(c) })
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: height / 2
                                    color: "#2d2d30"
                                    opacity: parent.pressed ? 0.7 : 1
                                }
                                Row {
                                    anchors.centerIn: parent
                                    spacing: Math.round(flick.width * 0.015)
                                    Icon {
                                        visible: (chip && chip.icon) ? true : false
                                        name: chip && chip.icon ? chip.icon : ""
                                        width: Math.round(flick.height * 0.055)
                                        height: width
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Label {
                                        text: chip ? chip.label : ""
                                        font.pixelSize: Math.round(flick.height * 0.05)
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
