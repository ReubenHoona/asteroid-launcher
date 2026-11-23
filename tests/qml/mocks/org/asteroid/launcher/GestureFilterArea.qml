/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * Test stand-in of the launcher's C++ GestureFilterArea (src/gesturefilterarea.h): the
 * properties and signals PanelsGrid.qml uses, so the grid can be made in a QML test. Nothing
 * here filters touches; a test moves the grid's content itself.
 */
import QtQuick

Item {
    property point pressPosition: Qt.point(0, 0)
    property point touchPosition: Qt.point(0, 0)
    property real swipeVelocityX: 0
    property real swipeVelocityY: 0
    property bool toRightAllowed: false
    property bool toLeftAllowed: false
    property bool toBottomAllowed: false
    property bool toTopAllowed: false
    property bool captureRight: false

    signal swipeStarted(bool horizontal)
    signal swipeMoved(bool horizontal, real delta)
    signal swipeReleased(bool horizontal, real velocity, bool tracing)
    signal touchMoved()
    signal touchEnded()
}
