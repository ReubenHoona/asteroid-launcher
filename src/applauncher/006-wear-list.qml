/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import org.asteroid.utils

/*
 * An app list in the manner of Wear OS: one application per row, a coloured
 * icon disc and the name on a pill, over a dark background. Rows shrink and
 * fade towards the top and bottom of the round screen (EdgeEffect, the
 * ScalingLazyColumn numbers), the crown scrolls the list with a haptic tick
 * per step and the curved position indicator shows where the list is (the
 * crown support of org.asteroid.controls), and a tap grows the icon into the
 * launch splash. The second row starts in the middle of the screen and the
 * last one can be scrolled there, as Wear OS centres its lists.
 */
Item {
    id: root

    property alias currentIndex: appsView.currentIndex
    property alias count: appsView.count
    property real tutorialScroll: 0
    property bool fakePressed: false

    anchors.fill: parent

    /* Back to the top of the list, with the first rows centred.
     * positionViewAtBeginning() puts the first row at the very top, past
     * topMargin: the list was then not at its beginning, and a swipe down
     * scrolled the margin into view instead of going back to the watchface */
    function resetPosition() {
        appsView.cancelFlick()
        appsView.contentY = appsView.originY - appsView.topMargin
    }

    // Wear OS lists sit on black: darken whatever wallpaper is behind
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.7
    }

    ListView {
        id: appsView

        property int currentPos: 0
        // Wear OS buttons are 52 dp tall: about a quarter of the screen
        readonly property real rowHeight: Math.round(Math.min(width, height) * 0.26)
        readonly property real viewScale: Math.min(width, height) / Dims.l(100)

        anchors.fill: parent
        clip: true
        cacheBuffer: height
        topMargin: Math.max(0, height / 2 - rowHeight * 1.5)
        bottomMargin: Math.max(0, height / 2 - rowHeight / 2)
        model: launcherModel

        onCurrentPosChanged: {
            rightIndicator.animate()
            leftIndicator.animate()
            topIndicator.animate()
            bottomIndicator.animate()
        }

        onContentYChanged: currentPos = Math.round((contentY + topMargin) / rowHeight)

        onAtYBeginningChanged: {
            // the grid only moves back to the watchface from the top of the list
            if ((grid.currentHorizontalPos === 0) && (grid.currentVerticalPos === 1)) {
                forbidTop = !atYBeginning
                grid.changeAllowedDirections()
            }
        }

        Connections {
            target: grid
            function onCurrentVerticalPosChanged() {
                if (grid.currentVerticalPos === 0) {
                    // back on the watchface: the list opens at the top again
                    root.resetPosition()
                } else if (grid.currentVerticalPos === 1) {
                    forbidTop = !appsView.atYBeginning
                    grid.changeAllowedDirections()
                }
            }
        }

        delegate: MouseArea {
            id: launcherItem

            width: appsView.width
            height: appsView.rowHeight
            enabled: !appsView.dragging

            onClicked: (typeof desktop !== "undefined" && desktop.launchApp) ? desktop.launchApp(model.object, circle) : model.object.launchApplication()

            EdgeEffect { id: edge; item: launcherItem }
            transform: Scale {
                origin.x: launcherItem.width / 2
                origin.y: launcherItem.height / 2
                xScale: edge.scale
                yScale: edge.scale
            }

            Item {
                id: row
                anchors.fill: parent
                opacity: edge.alpha
                // a pressed row sinks a little, as a Wear OS button does
                scale: launcherItem.pressed || root.fakePressed ? 0.96 : 1.0
                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutQuad } }

                Rectangle {
                    id: pill
                    anchors {
                        fill: parent
                        leftMargin: Dims.w(9)
                        rightMargin: Dims.w(9)
                        topMargin: parent.height * 0.05
                        bottomMargin: parent.height * 0.05
                    }
                    radius: height / 2
                    color: launcherItem.pressed || root.fakePressed ? "#40ffffff" : "#22ffffff"
                }

                Rectangle {
                    id: circle
                    anchors {
                        left: pill.left
                        leftMargin: pill.height * 0.14
                        verticalCenter: pill.verticalCenter
                    }
                    height: pill.height * 0.72
                    width: height
                    radius: width / 2
                    color: alb.centerColor(launcherModel.get(index).filePath)
                }

                Icon {
                    anchors.centerIn: circle
                    width: circle.width * 0.62
                    height: width
                    color: "white"
                    name: model.object.iconId === "" ? "ios-help" : model.object.iconId
                }

                Label {
                    anchors {
                        left: circle.right
                        leftMargin: pill.height * 0.16
                        right: pill.right
                        rightMargin: pill.height * 0.3
                        verticalCenter: pill.verticalCenter
                    }
                    text: model.object.title + localeManager.changesObserver
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    // Wear OS label large, 15 sp at 2 px per dp on 384 px
                    font.pixelSize: Dims.l(7.8) * appsView.viewScale
                    font.styleName: "SemiCondensed Medium"
                }
            }
        }
    }

    Component.onCompleted: {
        toLeftAllowed = false
        toRightAllowed = false
        toBottomAllowed = Qt.binding(function() { return !appsView.atYBeginning })
        toTopAllowed = Qt.binding(function() { return !appsView.atYEnd })
        forbidTop = Qt.binding(function() { return !appsView.atYBeginning })
        forbidBottom = false
        forbidLeft = false
        forbidRight = false
        launcherColorOverride = true
    }
}
