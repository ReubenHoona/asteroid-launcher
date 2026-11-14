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
 * The assistant, as on a Pixel Watch 2 (Wear OS CP3A, the stock Assistant's
 * plate): over whatever shows, a black screen with the assistant's mark and
 * "Ask Assistant" at the top and a glow on the bottom bezel
 * (AssistantGlow.qml). The glow opens when the microphone does, widens with
 * the voice and narrows when it is quiet; the words appear in the middle as
 * they are heard (the last two lines, the older ones fade away at the top);
 * a bead runs through the glow while the answer is worked out; the answer is
 * a list (text, chips, the disclaimer and the thumbs under an answer from
 * the phone's model, then the microphone button); an error is an alert
 * dialog with one Close button; nothing heard leaves the plate idle with the
 * microphone button.
 *
 * A tap while it listens ends the turn and answers what was heard (Stop());
 * while it thinks or shows an answer a tap does nothing. The crown and a swipe
 * right close it at any time, and so does the display going off. It opens on
 * a hold of the side button (assistantKey: at once, no transition), from the
 * app list's Assistant and from the Assistant tile (open(text) with a
 * suggestion's text asks that directly; these open with the shared fade).
 *
 * The work is asteroid-assistant's (org.asteroidos.assistant, D-Bus
 * activated); the actions are AssistantActions'.
 *
 * A card can ask back, as Wear OS does ("What's the message?", "Where to?"):
 * { dictate: true, prompt, kind?, onText: function (text, done, code, contact) }.
 * The overlay shows the prompt (or the stepped ellipsis when there is none)
 * and listens again (Dictate("assistant"): recognised where the commands are,
 * the phone's recogniser while it is connected); the text goes to onText, ""
 * when nothing was heard (code says why). kind "contact" ("Who do you want to
 * text?", "Which Sam?"): the daemon also matches the name against the phone's
 * contact names on the watch and gives the list's spelling as contact ("" when
 * it is none of them).
 *
 * The display stays on while it listens and thinks (mce's blanking pause; the
 * watch face is not the lock screen while the assistant shows, see
 * compositor.qml), as stock holds the screen during a state and 2 s after it,
 * and at most 18 s while it thinks or listens for a follow-up; then the
 * normal timeout runs.
 *
 * Battery: the glow and the ellipsis animate only while the display is on and
 * only in the states that show them; with an answer or an error on screen
 * nothing moves; no timer repeats.
 */
Item {
    id: overlay
    anchors.fill: parent

    property bool shown: false
    // opened over a call (OverlayArbiter): no listening, an alert says it
    // cannot help (stock errormsg_phone_call_active)
    property bool inCall: false
    // starting | listening | thinking | card | idle | error
    property string phase: "starting"
    property real level: 0
    property string heard: ""
    property string request: ""
    property var cardData: null
    // { icon, text } of the alert dialog while phase is error
    property var errorData: null
    property int session: 0
    // a session's result belongs to the overlay that started it
    property bool waitingStart: false
    // the session's Result came (its actions may still work)
    property bool resultSeen: false
    // one per turn: what an action or a chip answers late (a phone
    // query, a reply being sent) is dropped once another session began
    property int generation: 0
    // the card's question being listened for ({ prompt, onText }), else null
    property var followUp: null
    // what the listening page asks: "Ask Assistant" unless a card asked
    property string promptText: ""
    // the microphone button under an answer starts a new turn in place: the
    // answer stays until words arrive
    property bool keepAnswer: false
    // the first loud sample of this turn came (the glow stops idling)
    property bool talking: false
    // Level (0 .. 1: -60 .. -12 dB) above which the voice is "wide"; below it,
    // once the voice began, "narrow"
    readonly property real voiceThreshold: 0.35
    // the side button's hold opens at once; the app list and the tile use the fade
    property bool instantOpen: false
    // false while the display is off: the animations pause
    property bool screenOn: true
    // "up", "down" or "": the rating of the answer on screen (logged, nothing leaves the watch)
    property string rated: ""
    readonly property bool active: shown
    // the turn is over: an answer, the idle plate or an alert shows
    readonly property bool settled: phase === "card" || phase === "idle" || phase === "error"
    readonly property string glowMode: !shown ? "closed"
        : phase === "starting" ? "idle"
        : phase === "listening" ? (talking ? (level > voiceThreshold ? "wide" : "narrow") : "idle")
        : phase === "thinking" ? "processing" : "closed"
    // the answer list's rows (see buildItems)
    readonly property var answerItems: buildItems(cardData)

    visible: opacity > 0
    opacity: shown ? 1 : 0
    scale: shown ? 1 : 0.92
    Behavior on opacity {
        enabled: !overlay.instantOpen
        NumberAnimation { duration: Motion.duration(220); easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0, 0.2, 1, 1, 1] }
    }
    Behavior on scale {
        enabled: !overlay.instantOpen
        NumberAnimation { duration: Motion.duration(250); easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0, 0.2, 1, 1, 1] }
    }

    function loc(id, en) {
        var s = qsTrId(id)
        return (s === id || s === "") ? en : s
    }

    // the alert dialog's icon and text for a daemon error code (stock
    // qwx.java:12-22: offline, unavailable, in a call); a code with a
    // meaning of its own (the microphone, another user of it) keeps the
    // daemon's sentence
    function errorFor(code, text) {
        if (code === "in-call")
            return { icon: "ios-call", text: loc("id-asst-in-call", "Sorry, I can't help with that when you're in a call.") }
        if (code === "offline" || code === "no-backend" || code === "no-phone")
            return { icon: "ios-wifi-outline", slashed: true,
                     text: loc("id-asst-offline", "Your watch isn't connected to the internet. Please connect and try again.") }
        if ((code === "mic" || code === "no-engine" || code === "busy" || code === "engine" || code === "phone") && text)
            return { icon: code === "engine" || code === "phone" ? "ios-alert-outline" : "ios-mic-off-outline", text: text }
        return { icon: "ios-alert-outline",
                 text: loc("id-asst-unavailable", "The assistant is currently unavailable. Try again in a few minutes.") }
    }

    // the answer list: icon, title, text, chips, then, under an answer from
    // the phone's model, the disclaimer and the thumbs, and last the
    // microphone button (stock qko.java:38-170)
    function buildItems(c) {
        var out = []
        if (!c)
            return out
        if (c.icon)
            out.push({ kind: "icon", icon: c.icon, accent: String(c.accent || "") })
        if (c.title)
            out.push({ kind: "title", text: c.title })
        if (c.text)
            out.push({ kind: "text", text: c.text })
        var chips = c.chips || []
        for (var i = 0; i < chips.length; i++)
            out.push({ kind: "chip", n: i })
        if (c.disclaimer) {
            out.push({ kind: "disclaimer" })
            out.push({ kind: "thumbs" })
        }
        out.push({ kind: "mic" })
        return out
    }

    // forget the turn that was (the answer too, unless it stays under a new turn)
    function clearTurn(keep) {
        keepAnswer = keep === true && cardData !== null
        if (!keepAnswer)
            cardData = null
        errorData = null
        heard = ""
        request = ""
        level = 0
        talking = false
        session = 0
        resultSeen = false
        followUp = null
        promptText = ""
        rated = ""
    }

    function open(text, instant) {
        instantOpen = instant === true
        if (inCall) {
            swipe.reset()
            generation++
            waitingStart = false
            clearTurn(false)
            shown = true
            showError(errorFor("in-call", ""))
            return
        }
        // listening already: the second hold changes nothing
        if (shown && !settled && !text)
            return
        begin(text, false)
    }
    // a turn: listen, or ask the text directly; keep leaves the answer under it
    function begin(text, keep) {
        swipe.reset()
        clearTurn(keep)
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
    // the microphone button under an answer and on the idle plate
    function listenAgain() {
        begin("", phase === "card")
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
        } else if (session === 0 && !settled) {
            // the daemon refused (its Result names the reason, but it may
            // have come before this overlay listened to its signals)
            failedStart()
        }
    }
    function failedStart() {
        waitingStart = false
        showError(errorFor("unavailable", ""))
    }
    function hide() {
        // closes with the fade, whichever way it opened; what it shows stays for the fade
        // (an alert dialog is taken away once the overlay is gone, see onVisibleChanged)
        instantOpen = false
        shown = false
        keepAnswer = false
    }
    onVisibleChanged: if (!visible && !shown) errorData = null
    function close() {
        if (!shown)
            return
        // Cancel() ends whatever session the daemon runs: only while this
        // overlay's own may still be going (not once its Result came, as
        // an action that opens an app closes the overlay)
        if (!settled && !resultSeen)
            daemon.typedCall("Cancel", [])
        hide()
    }
    // A card asked back: listen for the answer (same generation: the flow goes on)
    function startFollowUp(c) {
        cardData = null
        keepAnswer = false
        heard = ""
        request = ""
        level = 0
        talking = false
        session = 0
        resultSeen = false
        followUp = c
        promptText = c.prompt || ""
        waitingStart = true
        phase = "starting"
        daemon.typedCall("Dictate", [{ "type": "s", "value": c.kind ? "assistant:" + c.kind : "assistant" }], started, failedStart)
    }
    // a tap while it listens: the turn ends, what was heard is answered
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
        errorData = null
        keepAnswer = false
        rated = ""
        phase = "card"
        answerList.positionViewAtBeginning()
        // RESPONSE: two thuds when the answer arrives (stock response.xml); an error says nothing
        if (c && !c.error)
            Haptics.play("assistant_response")
        // a card that goes by itself ("Calling Sam Carter on your phone.": the call screen follows)
        if (c && c.autoCloseMs > 0) {
            autoClose.interval = c.autoCloseMs
            autoClose.restart()
        } else {
            autoClose.stop()
        }
    }
    // nothing heard: the plate goes idle (the prompt, the microphone button, no error text)
    function showIdle() {
        cardData = null
        errorData = null
        keepAnswer = false
        heard = ""
        request = ""
        rated = ""
        phase = "idle"
        autoClose.stop()
    }
    // an alert dialog with one Close button
    function showError(e) {
        errorData = e
        keepAnswer = false
        phase = "error"
        autoClose.stop()
    }
    function rate(v) {
        rated = rated === v ? "" : v
        console.info("assistant: answer rated", rated === "" ? "none" : rated)
    }
    function runChip(n) {
        var chips = cardData && cardData.chips ? cardData.chips : []
        var chip = chips[n]
        var g = generation
        if (chip && chip.run)
            chip.run(function (c) { if (overlay.generation === g) overlay.done(c) })
    }
    Timer {
        id: autoClose
        repeat: false
        onTriggered: if (overlay.shown && overlay.phase === "card" && overlay.cardData && overlay.cardData.autoCloseMs > 0) overlay.close()
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
            f.onText(text, function (c) { if (overlay.generation === g) overlay.done(c) }, r.type === "dictation" ? "" : (r.code || r.type),
                     r.type === "dictation" ? (r.contact || "") : "")
            return
        }
        if (r.type === "cancel")
            return close()
        if (r.type === "intent") {
            actions.run(r.intent, r.slots, r.transcript, function (c) { if (overlay.generation === g) overlay.done(c) })
            return
        }
        if (r.type === "error") {
            if (r.code === "no-speech")
                return showIdle()
            return showError(errorFor(r.code, r.text))
        }
        showCard({ icon: r.icon || "ios-chatbubbles-outline", title: r.title || "", text: r.text || "",
                   chips: [], accent: r.via === "watch" ? Theme.color.primary : "#c3e7ff",
                   // a model's answer carries the disclaimer and the thumbs; the watch's own do not
                   disclaimer: r.intent === "question" && r.via !== undefined && r.via !== "watch" })
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

    // what the daemon says about this overlay's session (the D-Bus handlers
    // below only pass it on)
    function daemonState(s, state) {
        adopt(s, state)
        if (!mine(s) || settled)
            return
        if (state === "idle" && !resultSeen) {
            // the daemon dropped this session without a result (another
            // client started one): nothing more will come for it
            hide()
            return
        }
        if (state === "listening" && phase !== "listening") {
            phase = "listening"
            // the microphone is open: stock's MIC_OPEN thud, at every listening start
            Haptics.play("assistant_mic_open")
        } else if (state === "recognising" || state === "thinking") {
            // the user is done: the bead runs while it works the answer out
            phase = "thinking"
            keepAnswer = false
        }
    }
    function daemonLevel(l) {
        if (shown && phase === "listening") {
            level = l
            if (l > voiceThreshold)
                talking = true
        }
    }
    function daemonPartial(s, text) {
        if (mine(s) && !settled) {
            heard = text
            if (text !== "")
                keepAnswer = false
        }
    }
    function daemonTranscript(s, text) {
        if (mine(s)) {
            heard = text
            request = text
            if (!settled) {
                phase = "thinking"
                keepAnswer = false
            }
        }
    }

    DBusInterface {
        id: daemon
        bus: DBus.SessionBus
        service: "org.asteroidos.assistant"
        path: "/org/asteroidos/assistant"
        iface: "org.asteroidos.assistant"
        // always on: the first signals come before Listen() returns
        signalsEnabled: true

        function rcStateChanged(s: int, state: string) { overlay.daemonState(s, state) }
        function rcLevel(l: real) { overlay.daemonLevel(l) }
        function rcPartial(s: int, text: string) { overlay.daemonPartial(s, text) }
        function rcTranscript(s: int, text: string) { overlay.daemonTranscript(s, text) }
        function rcResult(s: int, json: string) {
            if (overlay.mine(s))
                overlay.handleResult(json)
        }
    }

    AssistantActions { id: actions }

    // The display stays on while the assistant works, as Wear OS keeps the
    // screen on for it: during starting, listening and thinking, 2 s after
    // them, and not for more than 18 s of thinking or of a follow-up's
    // listening (stock AssistantScreenTimeout); then the normal timeout.
    readonly property bool working: shown && (phase === "starting" || phase === "listening" || phase === "thinking")
    property bool capped: false
    property bool tail: false
    readonly property bool holdingDisplay: shown && ((working && !capped) || tail)
    property var holdMs: ({ tail: 2000, cap: 18000 })
    onWorkingChanged: {
        if (!working)
            capped = false
        if (!working && shown) {
            tail = true
            tailTimer.restart()
        } else {
            tail = false
            tailTimer.stop()
        }
    }
    onShownChanged: if (!shown) { tail = false; tailTimer.stop(); capped = false }
    Timer {
        id: tailTimer
        interval: overlay.holdMs.tail
        repeat: false
        onTriggered: overlay.tail = false
    }
    Timer {
        id: capTimer
        interval: overlay.holdMs.cap
        repeat: false
        running: overlay.working && (overlay.phase === "thinking" || overlay.followUp !== null)
        onTriggered: overlay.capped = true
    }
    DisplayBlanking {
        preventBlanking: overlay.holdingDisplay
    }

    // the screen goes away with the display, as Wear OS returns to the face
    Connections {
        target: typeof Lipstick !== "undefined" && Lipstick.compositor ? Lipstick.compositor : null
        ignoreUnknownSignals: true
        function onDisplayOff() { overlay.screenOn = false; overlay.close() }
        function onDisplayOn() { overlay.screenOn = true }
    }

    BackSwipeArea {
        id: swipe
        anchors.fill: parent
        swipeEnabled: overlay.shown
        onFinished: {
            // stock's rule (W1 BackSwipeArea.committed: 500 dp/s goes, else the lerped distance)
            if (committed) {
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

            /* the listening, thinking and idle plate */
            Item {
                id: plate
                objectName: "plate"
                anchors.fill: parent
                visible: !overlay.keepAnswer && (overlay.phase === "starting" || overlay.phase === "listening"
                                                 || overlay.phase === "thinking" || overlay.phase === "idle")

                AssistantSpark {
                    id: spark
                    objectName: "spark"
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Theme.dp(10)
                    width: Theme.dp(20)
                    height: width
                    // goes when the microphone button takes its place
                    shown: overlay.phase !== "idle"
                }

                Label {
                    id: prompt
                    objectName: "prompt"
                    role: "titleMedium"
                    // follow-up with no prompt: the stepped ellipsis
                    readonly property bool stepped: overlay.followUp !== null && overlay.promptText === ""
                    property string ellipsis: "   "
                    anchors.horizontalCenter: parent.horizontalCenter
                    // 5.2 % of the height under the icon (rcg.java:296-347)
                    y: Math.round(0.052 * parent.height) + spark.height
                    width: Math.round(parent.width * 0.8)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    visible: overlay.heard === "" && overlay.request === "" && overlay.phase !== "thinking"
                    text: overlay.promptText !== "" ? overlay.promptText
                          : stepped ? ellipsis : overlay.loc("id-asst-ask", "Ask Assistant")
                    // '   ', '.  ' at 150 ms, '.. ' at 300, '...' at 450, 1450 ms in all (rbq.java:62-92)
                    SequentialAnimation {
                        running: prompt.stepped && prompt.visible && overlay.screenOn && !Motion.reduceMotion
                        loops: Animation.Infinite
                        PropertyAction { target: prompt; property: "ellipsis"; value: "   " }
                        PauseAnimation { duration: 150 }
                        PropertyAction { target: prompt; property: "ellipsis"; value: ".  " }
                        PauseAnimation { duration: 150 }
                        PropertyAction { target: prompt; property: "ellipsis"; value: ".. " }
                        PauseAnimation { duration: 150 }
                        PropertyAction { target: prompt; property: "ellipsis"; value: "..." }
                        PauseAnimation { duration: 1000 }
                    }
                }

                // what is heard, as it is heard: the last two lines in the middle, the older
                // ones scroll up and fade at the top (rbq.java:246-600)
                Item {
                    id: transcript
                    objectName: "transcript"
                    readonly property string words: overlay.heard !== "" ? overlay.heard : overlay.request
                    readonly property real lineHeight: Theme.type.bodyLarge.lineHeight
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.round(parent.width * 0.8)
                    height: Math.min(heardText.lineCount, 2) * lineHeight
                    y: Math.round((parent.height - height) / 2)
                    clip: true
                    visible: words !== "" && overlay.phase !== "idle"
                    Behavior on height { NumberAnimation { duration: Motion.duration(50) } }

                    Label {
                        id: heardText
                        objectName: "heardText"
                        width: parent.width
                        // the last line's box ends at the bottom (the label's own padding is negative)
                        y: parent.height - heardText.lineCount * transcript.lineHeight - topPadding
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: transcript.words
                    }
                    // the older line fades out at the top
                    Rectangle {
                        objectName: "transcriptFade"
                        width: parent.width
                        height: transcript.lineHeight
                        visible: heardText.lineCount > 2
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#FF000000" }
                            GradientStop { position: 1.0; color: "#00000000" }
                        }
                    }
                }

                // idle: the suggestions to tap (the tile's), then the microphone button
                Column {
                    id: suggestions
                    objectName: "suggestions"
                    visible: overlay.phase === "idle"
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.round(parent.height * 0.30)
                    spacing: Theme.dp(4)
                    readonly property var texts: [
                        overlay.loc("id-tile-asst-weather", "What's the weather?"),
                        overlay.loc("id-tile-asst-timer", "Set a timer for 5 minutes"),
                        overlay.loc("id-tile-asst-alarm", "When is my next alarm?")
                    ]
                    Repeater {
                        model: suggestions.texts
                        delegate: MouseArea {
                            objectName: "suggestion" + index
                            width: Math.round(plate.width * 0.78)
                            height: Theme.dp(22)
                            onClicked: overlay.open(modelData, false)
                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                color: Theme.color.surfaceContainer
                            }
                            Label {
                                anchors.centerIn: parent
                                width: parent.width - 2 * Theme.space.xl
                                role: "labelSmall"
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: modelData
                            }
                        }
                    }
                }

                IconButton {
                    id: idleMic
                    objectName: "idleMic"
                    visible: overlay.phase === "idle"
                    // 24 dp icon in a 48 dp box, 4 % of the height above the edge
                    size: Theme.size.iconButtonSmall
                    iconName: "ios-mic"
                    iconColor: Theme.color.onSurface
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height - Math.round(0.04 * parent.height) - height
                    Accessible.name: overlay.loc("id-asst-mic", "Microphone")
                    onClicked: overlay.listenAgain()
                }
            }

            /* the answer */
            ScalingList {
                id: answerList
                objectName: "answerList"
                anchors.fill: parent
                visible: overlay.cardData !== null && (overlay.phase === "card" || overlay.keepAnswer)
                interactive: overlay.phase === "card"
                model: overlay.answerItems
                bottomMargin: Math.round(height * 0.10)
                itemDelegate: rowDelegate
            }

            /* the glow on the bezel */
            AssistantGlow {
                id: glow
                objectName: "glow"
                anchors.fill: parent
                mode: overlay.glowMode
                screenOn: overlay.screenOn
            }

            /* an error: the shared alert dialog, one Close button */
            Loader {
                id: errorLoader
                objectName: "errorLoader"
                anchors.fill: parent
                active: overlay.errorData !== null
                sourceComponent: AlertDialog {
                    id: errorDialog
                    objectName: "errorDialog"
                    iconName: overlay.errorData && !overlay.errorData.slashed ? overlay.errorData.icon : ""
                    // Wi-Fi off: the Wi-Fi icon struck through
                    icon: overlay.errorData && overlay.errorData.slashed ? slashedIcon : null
                    text: overlay.errorData ? overlay.errorData.text : ""
                    buttons: "none"
                    swipeToDismiss: false
                    closeOnSwipe: false
                    Component.onCompleted: open()
                    // the X in an edge button (stock qko.java:1178-1205)
                    EdgeButton {
                        objectName: "errorClose"
                        parent: errorDialog.content
                        preferredHeight: Theme.size.edgeButtonMedium
                        Accessible.name: overlay.loc("id-asst-close", "Close")
                        // after the click: closing takes this dialog away
                        onClicked: Qt.callLater(overlay.close)
                        DialogGlyph {
                            anchors.centerIn: parent
                            width: Theme.dp(28)
                            height: width
                            glyph: "close"
                            color: Theme.color.onPrimary
                        }
                    }
                }
            }

            // a tap while it listens ends the turn (stock onTappedOutside); not while it
            // thinks or shows an answer
            MouseArea {
                objectName: "tapStop"
                anchors.fill: parent
                enabled: overlay.phase === "listening"
                onClicked: overlay.stopListening()
            }
        }
    }

    Component {
        id: slashedIcon
        Item {
            Icon {
                anchors.fill: parent
                name: overlay.errorData ? overlay.errorData.icon : ""
                color: Theme.color.onBackground
            }
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 1.1
                height: Theme.dp(2)
                radius: height / 2
                rotation: 45
                color: Theme.color.onBackground
            }
        }
    }

    /* the answer's rows: ScalingList gives each its index and modelData */
    Component {
        id: rowDelegate
        Item {
            id: row
            property int index
            property var modelData
            readonly property var entry: modelData || ({})
            height: rowLoader.item ? rowLoader.item.height : 0
            Loader {
                id: rowLoader
                width: row.width
                sourceComponent: row.entry.kind === "icon" ? iconRow
                    : row.entry.kind === "title" ? titleRow
                    : row.entry.kind === "text" ? textRow
                    : row.entry.kind === "chip" ? chipRow
                    : row.entry.kind === "disclaimer" ? disclaimerRow
                    : row.entry.kind === "thumbs" ? thumbsRow
                    : row.entry.kind === "mic" ? micRow : null
                onLoaded: item.entry = Qt.binding(function () { return row.entry })
            }
        }
    }
    Component {
        id: iconRow
        Item {
            property var entry: ({})
            height: Theme.size.iconLarge + Theme.space.m
            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.size.iconLarge
                height: width
                name: entry.icon || ""
                color: entry.accent && entry.accent !== "" ? entry.accent : Theme.color.primary
            }
        }
    }
    Component {
        id: titleRow
        Label {
            property var entry: ({})
            role: "titleMedium"
            width: parent ? parent.width : 0
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: entry.text || ""
            objectName: "answerTitle"
        }
    }
    Component {
        id: textRow
        Label {
            property var entry: ({})
            role: "bodyLarge"
            width: parent ? parent.width : 0
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: entry.text || ""
            objectName: "answerText"
        }
    }
    Component {
        id: chipRow
        FilledTonalButton {
            property var entry: ({})
            readonly property var chip: overlay.cardData && overlay.cardData.chips ? overlay.cardData.chips[entry.n] : null
            width: parent ? parent.width : 0
            centered: true
            text: chip ? chip.label : ""
            iconName: chip && chip.icon ? chip.icon : ""
            objectName: "answerChip" + (entry.n === undefined ? "" : entry.n)
            onClicked: overlay.runChip(entry.n)
        }
    }
    Component {
        id: disclaimerRow
        Item {
            property var entry: ({})
            // 12 dp above the line (stock gemini_response_disclaimer)
            height: Theme.dp(12) + line.height
            Label {
                id: line
                objectName: "disclaimer"
                y: Theme.dp(12)
                role: "bodySmall"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: "#747775"
                text: overlay.loc("id-asst-disclaimer", "The assistant can make mistakes, so double-check it")
            }
        }
    }
    Component {
        id: thumbsRow
        Item {
            property var entry: ({})
            height: Theme.size.iconButtonExtraSmall + Theme.space.m
            Row {
                objectName: "thumbs"
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.dp(24)
                IconButton {
                    objectName: "thumbUp"
                    size: Theme.size.iconButtonExtraSmall
                    iconName: overlay.rated === "up" ? "ios-thumbs-up" : "ios-thumbs-up-outline"
                    iconColor: Theme.color.onSurfaceVariant
                    Accessible.name: overlay.loc("id-asst-good", "Good response")
                    onClicked: overlay.rate("up")
                }
                IconButton {
                    objectName: "thumbDown"
                    size: Theme.size.iconButtonExtraSmall
                    iconName: overlay.rated === "down" ? "ios-thumbs-down" : "ios-thumbs-down-outline"
                    iconColor: Theme.color.onSurfaceVariant
                    Accessible.name: overlay.loc("id-asst-bad", "Bad response")
                    onClicked: overlay.rate("down")
                }
            }
        }
    }
    Component {
        id: micRow
        Item {
            property var entry: ({})
            // 12 dp above the button
            height: Theme.dp(12) + Theme.size.iconButtonSmall
            IconButton {
                objectName: "answerMic"
                y: Theme.dp(12)
                anchors.horizontalCenter: parent.horizontalCenter
                size: Theme.size.iconButtonSmall
                iconName: "ios-mic"
                iconColor: Theme.color.onSurface
                Accessible.name: overlay.loc("id-asst-mic", "Microphone")
                onClicked: overlay.listenAgain()
            }
        }
    }
}
