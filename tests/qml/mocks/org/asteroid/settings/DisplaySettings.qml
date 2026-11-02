// Test double for the launcher QML tests (copied from asteroid-settings tests/mocks; see tests/qml/tst_quickpanel.qml)
// qml-asteroid's DisplaySettings (mce display settings)
import QtQuick
import LauncherTest
QtObject {
    id: ds
    property int brightness: Backend.brightness
    readonly property int maximumBrightness: 100
    property bool lowPowerModeEnabled: Backend.lpm
    property bool ambientLightSensorEnabled: Backend.als
    onBrightnessChanged: if (brightness !== Backend.brightness) {
        Backend.brightness = brightness
        Backend.record("mce", "display_brightness", [brightness])
    }
    onLowPowerModeEnabledChanged: if (lowPowerModeEnabled !== Backend.lpm) {
        Backend.lpm = lowPowerModeEnabled
        Backend.record("mce", "use_low_power_mode", [lowPowerModeEnabled])
    }
    onAmbientLightSensorEnabledChanged: if (ambientLightSensorEnabled !== Backend.als) {
        Backend.als = ambientLightSensorEnabled
        Backend.record("mce", "als_enabled", [ambientLightSensorEnabled])
    }
    property Connections _sync: Connections {
        target: Backend
        function onBrightnessChanged() { if (ds.brightness !== Backend.brightness) ds.brightness = Backend.brightness }
        function onLpmChanged() { if (ds.lowPowerModeEnabled !== Backend.lpm) ds.lowPowerModeEnabled = Backend.lpm }
        function onAlsChanged() { if (ds.ambientLightSensorEnabled !== Backend.als) ds.ambientLightSensorEnabled = Backend.als }
    }
}
