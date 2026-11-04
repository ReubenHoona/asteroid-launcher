// Test double for the launcher QML tests (copied from asteroid-settings tests/mocks; see tests/qml/tst_quickpanel.qml)
// The watch the mocks stand for: dconf, mce, PulseAudio, BlueZ, connman,
// timedate1, login1, btsyncd. Every write a mock passes on to its backend
// is recorded in calls; reset() puts the defaults back.
pragma Singleton
import QtQuick

QtObject {
    // dconf
    property var conf: ({})
    signal confWritten(string key)
    function confHas(key) { return conf.hasOwnProperty(key) }
    function confGet(key) { return conf[key] }
    function confSet(key, v) {
        conf[key] = v
        record("dconf", key, [v])
        confWritten(key)
    }

    // mce settings (MceConfigValue) and the display
    property var mce: ({})
    signal mceWritten(string key)
    function mceSet(key, v) {
        mce[key] = v
        record("mce", key, [v])
        mceWritten(key)
    }
    property int brightness: 60
    property bool als: true
    property bool lpm: true
    property bool tilt: true
    property bool tiltAvailable: true
    property bool tap: true

    // battery (mce)
    property int batteryPercent: 57
    property int batteryState: 2      // MceBatteryState.Discharging
    property int chargerType: 0       // MceChargerType.None

    // sound (PulseAudio's main volume)
    property int volume: 70

    // Bluetooth (BlueZ adapter) and Wi-Fi (connman)
    property bool btPowered: true
    property bool btConnected: true
    property bool wifiPowered: true
    property bool wifiConnected: true
    property var wifiServices: []

    // time and language
    property string timezone: "Europe/London"
    property var now: new Date(2026, 10, 2, 10, 9, 0)
    property int languageIndex: 1

    // what was asked of the backends: { target, method, args }
    property var calls: []
    function record(target, method, args) {
        var l = calls.slice()
        l.push({ "target": target, "method": method, "args": args || [] })
        calls = l
    }
    function find(target, method) {
        for (var i = calls.length - 1; i >= 0; i--)
            if (calls[i].target === target && calls[i].method === method)
                return calls[i]
        return null
    }
    function clearCalls() { calls = [] }

    // D-Bus replies, "interface.method" -> value
    property var replies: ({})

    function reset() {
        conf = {}
        // the watch today: dim 10 s + blank 5 s, the screen on for 15 s
        mce = { "/system/osso/dsm/display/display_dim_timeout": 10,
                "/system/osso/dsm/display/display_blank_timeout": 5 }
        brightness = 60; als = true; lpm = true; tilt = true; tiltAvailable = true; tap = true
        batteryPercent = 57; batteryState = 2; chargerType = 0
        volume = 70
        btPowered = true; btConnected = true; wifiPowered = true; wifiConnected = true; wifiServices = []
        timezone = "Europe/London"; languageIndex = 1
        replies = {
            "org.asteroidos.btsyncd.Phone.Connected": true,
            "org.asteroidos.btsyncd.Phone.BatteryLevel": 80,
            "org.freedesktop.timedate1.ListTimezones": ["Africa/Abidjan", "America/New_York", "Europe/Berlin",
                                                        "Europe/London", "Europe/Paris", "Asia/Tokyo", "Zulu"]
        }
        calls = []
    }
    Component.onCompleted: reset()
}
