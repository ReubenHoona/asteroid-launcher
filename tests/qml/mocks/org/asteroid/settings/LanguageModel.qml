// Test double for the launcher QML tests (C-23, tst_setupupdate.qml): qml-asteroid's LanguageModel as the setup
// (firstrun/FirstRunConfig.qml) uses it: the roles, rowCount / index / data, setSystemLocale (recorded)
import QtQuick
import LauncherTest
QtObject {
    enum Role { NameRole = 257, LocaleRole = 258, RegionLabelRole = 259 }
    enum Update { UpdateWithoutReboot = 0, UpdateAndReboot = 1 }
    property var rows: [{ "name": "English", "locale": "en_GB", "region": "" }]
    function rowCount() { return rows.length }
    function index(row, column) { return row }
    function data(ix, role) {
        var r = rows[ix] || {}
        return role === 257 ? r.name : role === 258 ? r.locale : role === 259 ? r.region : undefined
    }
    function setSystemLocale(locale, how) { Backend.record("language", "setSystemLocale", [locale, how]) }
}
