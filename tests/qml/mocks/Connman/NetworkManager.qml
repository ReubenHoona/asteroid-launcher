// Copyright (C) 2026 eos-mainline contributors
// SPDX-License-Identifier: BSD-3-Clause
// Test double for the launcher QML tests: Connman's NetworkManager (offline mode = Airplane mode, the connected Wi-Fi)
import QtQuick
import LauncherTest
QtObject {
    id: nm
    property bool offlineMode: Backend.offline
    readonly property var connectedWifi: Backend.wifiName !== "" ? ({ "name": Backend.wifiName }) : null
    onOfflineModeChanged: if (offlineMode !== Backend.offline) {
        Backend.offline = offlineMode
        Backend.record("connman", "OfflineMode", [offlineMode])
    }
    property Connections _sync: Connections {
        target: Backend
        function onOfflineChanged() { if (nm.offlineMode !== Backend.offline) nm.offlineMode = Backend.offline }
    }
}
