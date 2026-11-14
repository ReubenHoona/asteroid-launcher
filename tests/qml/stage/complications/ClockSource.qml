// Copyright (C) 2026 eos-mainline contributors
// SPDX-License-Identifier: BSD-3-Clause
// Test double for the launcher QML tests: complications/ClockSource.qml (timed's alarms) on Backend.nextAlarmMs
import QtQuick
import LauncherTest
QtObject {
    property bool active: false
    property date now: new Date()
    readonly property real nextAlarmMs: Backend.nextAlarmMs
    property real countdownEnd: 0
    function refresh() {}
}
