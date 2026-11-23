// D60-23 (WO-10): Settings > Display > Go to watch face reaches the app list and Recents when the
// always-on screen is used. AppLifecycle.qml (compositor/) with lipstick's Compositor mocked, on a
// fake boot clock (lipstick bootTimeMs):
//  - an AP ambient update (the hub's layout hand-over) emits displayAboutToBeOn, which clears
//    displayIsOff; the real wake 70 s after the display went off still shows the face;
//  - while the AP is awake under the always-on screen the 2 s check (ambientExpiry) runs for the
//    app list and Recents too, and shows the face once the count has run out;
//  - Go to watch face 15 s: 14 s keeps the list, 15 s is the face; Never keeps the list.
//  - the home screen comes after AppLifecycle, as on the watch (compositor.qml's homeLoader loads
//    MainScreen in its componentComplete, after AppLifecycle's bindings were first evaluated, and
//    MainScreen sets Desktop.desktop in its Component.onCompleted): AppLifecycle takes it through its
//    `home` property (compositor.qml: home: homeLoader.item), so the check's binding sees it arrive.
// Stock: HeadlessTaskManagementSession.expireTask moves the expired task to the back and
// maybeHandleHomeTaskExpiration drops a home task whose top activity is not the home activity to the
// face (:327-374, :452-469); the timer is a non-wakeup alarm (TaskTimeoutController.java:208).
// Run by motion-wt/wo10/run.sh (qmltestrunner under qemu-aarch64 on the image rootfs; st/qml is the
// tree staged as its qrc lays it out).
import QtQuick
import QtTest
import org.nemomobile.lipstick
import "st/qml/desktop.js" as Desktop
import "st/qml/compositor/lifecycle.js" as Life

Item {
    id: top
    width: 384
    height: 384

    // the boot-time clock (lipstick bootTimeMs), in ms
    property real now: 1000000

    // compositor.qml's parts as AppLifecycle reads them through the context
    QtObject { id: root; property bool assistantShown: false; property var ambientLite: null }
    Item { id: appLayer; property bool ready: true }
    QtObject { id: launchSplash; property bool active: false; function finish() {} function cancel() {} }
    QtObject {
        id: transitions
        property bool windowMoving: false
        function openWindow(w, overSplash) {}
        function endEdgeSwipe() {}
    }
    Item { id: arbiter; property Item alertLayer: Item {} }
    QtObject { id: lipstickSettings; property bool lockscreenVisible: false }
    QtObject { id: keyguard; property bool locked: false; function appRequested(t) {} }
    QtObject { id: hubOffload; function invalidate() {} }

    // lipstick's compositor object (Lipstick.compositor) as AppLifecycle calls it
    QtObject {
        id: lipstickComp
        property int screenOrientation: 1
        property bool displayAmbient: false
        property bool displayDimmed: false
        signal displayOff()
        signal displayOn()
        signal displayAboutToBeOn()
        signal displayAboutToBeOff()
        signal displayAmbientUpdate()
        function bootTimeMs() { return top.now }
        function freezeClientForWindowId(id, on) {}
        function closeClientForWindowId(id) {}
        function offloadAmbientUpdateWanted() { return false }
        function setAmbientUpdatesEnabled(on) {}
    }

    // the home screen (MainScreen): the app list, Recents, and the way back to the face. Loaded after
    // AppLifecycle (homeLoader below), and it sets Desktop.desktop when it completes, as MainScreen does
    QtObject { id: drawerMock; property bool isOpen: false }
    QtObject { id: recentsMock; property bool isOpen: false }
    Component {
        id: homeComponent
        Item {
            id: homeItem
            property QtObject appDrawer: drawerMock
            property QtObject recents: recentsMock
            property int faceShows: 0
            function showWatchface() {
                faceShows++
                drawerMock.isOpen = false
                recentsMock.isOpen = false
            }
            Component.onCompleted: Desktop.desktop = homeItem
        }
    }
    Loader { id: homeLoader; active: false; sourceComponent: homeComponent }
    readonly property QtObject home: homeLoader.item

    // compositor.qml: AppLifecycle { id: comp; home: homeLoader.item }
    Loader {
        id: loader
        active: false
        source: Qt.resolvedUrl("st/qml/compositor/AppLifecycle.qml")
        onLoaded: item.home = Qt.binding(function () { return homeLoader.item })
    }

    SignalSpy { id: goneSpy; signalName: "goneToFace" }

    TestCase {
        id: tc
        name: "GoToFace"
        when: windowShown

        property var life: null
        // what initTestCase saw (asserted in test_00, so the other tests still run when it fails)
        property var homeAtLoad: undefined
        property var desktopAtLoad: undefined
        property var homeAfter: undefined

        function initTestCase() {
            Lipstick.compositor = lipstickComp
            Desktop.desktop = null
            loader.active = true
            tryCompare(loader, "status", Loader.Ready, 30000)
            life = loader.item
            verify(life !== null, "AppLifecycle loaded")
            goneSpy.target = life
            compare(life.appActive, false, "no application: the home screen")
            homeAtLoad = life.home
            desktopAtLoad = Desktop.desktop
            // then the home screen, as compositor.qml's homeLoader brings MainScreen
            homeLoader.active = true
            tryCompare(homeLoader, "status", Loader.Ready, 5000)
            homeAfter = life.home
        }

        function test_00_home_screen_arrives_after_applifecycle() {
            compare(homeAtLoad, null, "AppLifecycle loaded with no home screen yet")
            compare(desktopAtLoad, null, "nor Desktop.desktop")
            verify(home !== null, "the home screen loaded")
            compare(homeAfter, home, "AppLifecycle.home follows homeLoader.item")
            compare(Desktop.desktop, home, "the home screen set Desktop.desktop when it completed")
            compare(life.homeScreen(), home)
        }

        // the display on, the face, nothing open, Go to watch face 1 minute (the default)
        function init() {
            lipstickComp.displayAmbient = false
            drawerMock.isOpen = false
            recentsMock.isOpen = false
            if (life.displayIsOff) {
                top.now += 1000
                life.displayAboutToBeOn()
            }
            life.goToFaceSetting.value = 60000
            Life.episodeEnd(life.episode)
            home.faceShows = 0
            goneSpy.clear()
            top.now += 3600000
        }

        // the display goes to always-on with `list` open; t0 is then top.now
        function offWith(list) {
            list.isOpen = true
            lipstickComp.displayAmbient = true
            life.displayOff()
            compare(life.displayIsOff, true)
        }
        // an AP ambient update: the layout handed to the hub emits displayAboutToBeOn
        function ambientUpdate() {
            life.displayAboutToBeOn()
        }
        // the real wake (the crown or a tap): out of always-on, display on
        function realWake() {
            lipstickComp.displayAmbient = false
            life.displayAboutToBeOn()
            life.displayOn()
        }

        function test_01_app_list_wake_after_ambient_update() {
            compare(life.goToFaceMs, 60000, "Go to watch face: 1 minute by default")
            offWith(drawerMock)
            top.now += 5000
            ambientUpdate()
            compare(life.displayIsOff, false, "the ambient update took displayIsOff (the case of the defect)")
            compare(home.faceShows, 0, "5 s: the list stays")
            // 70 s after the display went off, the AP asleep in between (no timer ran)
            top.now += 65000
            realWake()
            compare(home.faceShows, 1, "70 s: the wake shows the face")
            compare(drawerMock.isOpen, false, "the app list is closed")
            compare(goneSpy.count, 1)
        }

        function test_02_recents_wake_after_ambient_update() {
            offWith(recentsMock)
            top.now += 5000
            ambientUpdate()
            top.now += 65000
            realWake()
            compare(home.faceShows, 1, "70 s: the wake shows the face")
            compare(recentsMock.isOpen, false, "Recents is closed")
        }

        function test_03_short_wake_keeps_the_list() {
            offWith(drawerMock)
            top.now += 5000
            ambientUpdate()
            top.now += 54999
            realWake()
            compare(home.faceShows, 0, "59.999 s: the list stays")
            compare(drawerMock.isOpen, true)
        }

        // while the AP is awake under the always-on screen: the 2 s check, as for an app under Ambient Lite
        function test_04_check_under_always_on() {
            offWith(recentsMock)
            compare(life.ambientExpiry.interval, 2000)
            verify(life.ambientExpiry.running, "the check runs with Recents under the always-on screen")
            top.now += 59999
            compare(life.expireWhileOff(), false, "59.999 s: not yet")
            compare(home.faceShows, 0)
            top.now += 1
            tryCompare(home, "faceShows", 1, 5000, "60 s: the check shows the face")
            compare(recentsMock.isOpen, false)
            verify(!life.ambientExpiry.running, "nothing open: the check stops")
        }

        function test_05_check_runs_only_for_an_open_list_in_always_on() {
            lipstickComp.displayAmbient = true
            verify(!life.ambientExpiry.running, "the face under the always-on screen: no check")
            lipstickComp.displayAmbient = false
            drawerMock.isOpen = true
            verify(!life.ambientExpiry.running, "awake with the app list: no check (the wake decides)")
            lipstickComp.displayAmbient = true
            verify(life.ambientExpiry.running, "the app list under the always-on screen: the check runs")
            // the binding follows the lists themselves (home's appDrawer.isOpen and recents.isOpen)
            drawerMock.isOpen = false
            verify(!life.ambientExpiry.running, "the app list closed: no check")
            recentsMock.isOpen = true
            verify(life.ambientExpiry.running, "Recents under the always-on screen: the check runs")
            lipstickComp.displayAmbient = false
            verify(!life.ambientExpiry.running, "awake: no check (the wake decides)")
        }

        function test_06_fifteen_seconds() {
            life.goToFaceSetting.value = 15000
            compare(life.goToFaceMs, 15000)
            offWith(drawerMock)
            top.now += 3000
            ambientUpdate()
            top.now += 11000
            realWake()
            compare(home.faceShows, 0, "14 s: the list stays")
            // the next display off, past 15 s (a short wake restarts the count)
            lipstickComp.displayAmbient = true
            life.displayOff()
            top.now += 2000
            ambientUpdate()
            top.now += 13000
            realWake()
            compare(home.faceShows, 1, "15 s after that display off: the face")
        }

        function test_07_never() {
            life.goToFaceSetting.value = 86400000
            offWith(drawerMock)
            top.now += 5000
            ambientUpdate()
            compare(life.expireWhileOff(), false)
            top.now += 2 * 86400000
            realWake()
            compare(home.faceShows, 0, "Never: the list stays")
            compare(drawerMock.isOpen, true)
        }
    }
}
