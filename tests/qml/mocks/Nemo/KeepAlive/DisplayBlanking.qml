/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

// Test double for the launcher QML tests: Nemo.KeepAlive's DisplayBlanking, each
// change of preventBlanking recorded in Backend.calls (target "keepalive")
import QtQuick
import LauncherTest

QtObject {
    property bool preventBlanking: false
    onPreventBlankingChanged: Backend.record("keepalive", "preventBlanking", [preventBlanking])
}
