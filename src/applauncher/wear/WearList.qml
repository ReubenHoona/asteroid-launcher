/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "WearEdge.js" as Edge

/*
 * The list of stock's launcher screens (W2-launcher-app-list): the app list,
 * the grid and Recents are this one frame with different content.
 *
 *   - a 13 % spacer (Theme.margin.launcherTop, 25 dp = 50 px), then the header
 *     (titleLarge, 18 sp on a 20 sp line, weight 500, 0.2 sp tracking,
 *     onSurface, centred, up to 2 lines, 4 dp above and 12 dp below), so the
 *     first row's top is at 61 dp (122 px) (app-launcher-02, -03);
 *   - rows (columns: 1): 52 dp pills 172 dp wide (5.2 % side padding), 4 dp
 *     apart (app-launcher-04); or a grid (columns: 3) of 48 dp icons 6 dp
 *     apart in rows of three (app-launcher-16);
 *   - the end: a Medium (70 dp) edge button 12 dp under the last row
 *     ("Grid view", "List view", "All apps"; app-launcher-15);
 *   - every row, the header and the grid rows take the launcher's edge
 *     transformation, packed (WearEdge.js layout, app-launcher-07);
 *   - no TimeText (app-launcher-21).
 *
 * The base is the shared ScalingList (stock fling, stretch at the ends and
 * the crown with its tick haptics). The rows keep their natural place in it,
 * so it scrolls evenly and its end is where the edge button expects it; what
 * is drawn where is the layout property, computed again as the list moves.
 *
 * Content: model (rows: its "object" role holds a LauncherItem) or, for the
 * grid, cells (an object with itemCount and get(i)). The rows' colours come
 * from colorOf(filePath), their status line from statusOf(object).
 */
Item {
    id: root

    anchors.fill: parent

    property var model: null
    property string headerText: ""
    property string edgeText: ""
    property string edgeIcon: ""
    property string emptyText: ""
    property int columns: 1
    property var cells: null
    property var spec: columns > 1 ? Edge.GRID : Edge.LIST
    property var colorOf: function (path) { return Theme.color.primary }
    property var statusOf: function (object) { return "" }
    // a row looks pressed (the first run tutorial): the first row or icon
    property bool fakePressed: false
    property alias currentIndex: view.currentIndex
    property alias count: view.count

    readonly property alias view: view
    readonly property alias edgeButton: edgeButton
    readonly property alias headerItem: headerItem
    readonly property real rowHeight: Theme.size.button
    readonly property real cellSize: Theme.dp(48)
    readonly property real gap: Theme.space.xs
    readonly property real cellGap: Theme.dp(6)
    readonly property real sidePadding: Theme.margin.listSide
    // what a row or a cell of the list is
    readonly property real itemHeight: columns > 1 ? cellSize : rowHeight
    readonly property real itemGap: columns > 1 ? cellGap : gap
    // the distance of one row to the next
    readonly property real pitch: itemHeight + itemGap
    // the list at rest, scrolled to its top: the spacer shows
    readonly property real topPosition: view.originY - view.topMargin
    readonly property int cellCount: cells ? cells.itemCount : 0

    signal activated(var object, Item origin)
    signal longPressed(var object)
    signal edgeClicked()

    // the item of cell i: cells.get(i) is the item itself (LauncherSortModel) or a row with an "object" (a ListModel)
    function cellItem(i) {
        var c = cells ? cells.get(i) : null
        return c && c.object !== undefined ? c.object : c
    }

    function resetPosition() {
        view.cancelFlick()
        view.contentY = topPosition
    }

    /*
     * Where the header and the rows are drawn (WearEdge.js layout): item 0 is the
     * header, item i + 1 the row i. Computed again with every move of the list,
     * from the natural places only.
     */
    readonly property var layout: {
        var n = view.count
        var vh = view.height
        var tops = [headerItem.y], hs = [headerItem.rawHeight], gaps = [0]
        for (var i = 0; i < n; i++) {
            tops.push(view.originY + i * root.pitch - view.contentY)
            hs.push(root.itemHeight)
            gaps.push(root.itemGap)
        }
        return Edge.layout(root.spec, tops, hs, gaps, vh, Motion.reduceMotion)
    }

    ScalingList {
        id: view
        anchors.fill: parent
        clip: true
        cacheBuffer: height
        spacing: root.itemGap
        // 13 % of the height, then the header (4 dp, its line, 12 dp): the first row's top at 61 dp
        topMargin: Theme.margin.launcherTop + headerItem.rawHeight
        // the edge button 70 dp high, 3 dp above the edge, and 12 dp between it and the last row
        bottomMargin: edgeButton.preferredHeight + Theme.size.edgeButtonBottomGap + Theme.space.l
        model: root.columns > 1 ? Math.ceil(root.cellCount / root.columns) : root.model
        delegate: root.columns > 1 ? gridDelegate : rowDelegate
    }

    // ---- the header: over the list, scrolls with the rows ----
    Item {
        id: headerItem
        width: root.width
        // the natural place: 13 % under the top at rest, then up with the content
        y: Theme.margin.launcherTop - (view.contentY - root.topPosition)
        readonly property real rawHeight: headerBox.height
        readonly property var ev: root.layout[0] || Edge.UNPLACED

        Item {
            id: headerBox
            width: parent.width
            // where the layout draws it, from the natural place
            y: headerItem.ev.unplaced ? 0 : headerItem.ev.y - headerItem.y
            height: titleTop + headerLabel.height + (emptyLabel.visible ? emptyLabel.height + emptyLabel.topPad + emptyLabel.bottomPad : 0) + titleBottom
            readonly property real titleTop: Theme.dp(4)
            // 12 dp to the first row
            readonly property real titleBottom: Theme.space.l
            opacity: headerItem.ev.contentAlpha
            visible: headerItem.ev.shown
            transform: Scale {
                origin.x: headerBox.width / 2
                origin.y: 0
                xScale: headerItem.ev.scale
                yScale: headerItem.ev.scale
            }

            Label {
                id: headerLabel
                text: root.headerText
                x: Theme.margin.titleSide
                y: headerBox.titleTop
                width: parent.width - 2 * Theme.margin.titleSide
                // lines of the line box, whatever the font's own metrics
                height: Math.max(1, lineCount) * lineHeight
                role: "titleLarge"
                // the launcher's own header style: 0.2 sp tracking, the widest cut (SysUI fcc.bh-bm)
                font.letterSpacing: Theme.sp(0.2)
                font.variableAxes: ({ "wdth": 110, "ROND": 100, "opsz": 18 })
                color: Theme.color.onSurface
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            // an empty Recents: bodyMedium in onSurfaceVariant, 11.45 % of the width at each side,
            // 5.24 % of the height above and 16 dp below (hca.E)
            Label {
                id: emptyLabel
                readonly property real topPad: Theme.dp(Math.ceil(0.0524 * Theme.screenHeightDp))
                readonly property real bottomPad: Theme.dp(16)
                visible: root.emptyText !== "" && view.count === 0
                x: 0.1145 * headerBox.width
                y: headerBox.titleTop + headerLabel.height + topPad
                width: headerBox.width - 2 * x
                text: root.emptyText
                role: "bodyMedium"
                color: Theme.color.onSurfaceVariant
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
        }
    }

    // ---- the list's rows ----
    Component {
        id: rowDelegate
        Item {
            id: slot
            readonly property var object: model.object
            readonly property var ev: root.layout[index + 1] || Edge.UNPLACED
            width: view.width
            height: root.rowHeight

            WearRow {
                id: wrow
                x: root.sidePadding
                // where the layout draws it, from the natural place
                y: slot.ev.unplaced ? 0 : slot.ev.y - (slot.y - view.contentY)
                width: slot.width - 2 * root.sidePadding
                visible: slot.ev.shown
                title: slot.object ? slot.object.title + localeManager.changesObserver : ""
                iconId: slot.object ? slot.object.iconId : ""
                discColor: slot.object ? root.colorOf(slot.object.filePath) : Theme.color.primary
                status: slot.object ? root.statusOf(slot.object) : ""
                containerAlpha: slot.ev.containerAlpha
                contentAlpha: slot.ev.contentAlpha
                fakePressed: root.fakePressed && index === 0
                enabled: !view.dragging
                transform: Scale {
                    origin.x: wrow.width / 2
                    origin.y: 0
                    xScale: slot.ev.scale
                    yScale: slot.ev.scale
                }
                onActivated: root.activated(slot.object, wrow.disc)
                onLongPressed: root.longPressed(slot.object)
            }
        }
    }

    // ---- the grid's rows of three ----
    Component {
        id: gridDelegate
        Item {
            id: slot
            readonly property int first: index * root.columns
            readonly property int n: Math.min(root.columns, root.cellCount - first)
            readonly property var ev: root.layout[index + 1] || Edge.UNPLACED
            width: view.width
            height: root.cellSize

            Repeater {
                model: slot.n
                WearCell {
                    id: wcell
                    readonly property var object: root.cellItem(slot.first + index)
                    // left to right, as drawn
                    readonly property int visualIndex: Theme.rtl ? slot.n - 1 - index : index
                    readonly property real rowWidth: slot.n * width + (slot.n - 1) * root.cellGap
                    x: (slot.width - rowWidth) / 2 + visualIndex * (width + root.cellGap)
                       + Edge.columnShift(visualIndex, slot.n, width, slot.ev.scale)
                    y: (slot.ev.unplaced ? 0 : slot.ev.y - (slot.y - view.contentY))
                       + Edge.columnLift(visualIndex, slot.n, width, slot.ev.sideOffset)
                    visible: slot.ev.shown
                    title: object ? object.title + localeManager.changesObserver : ""
                    iconId: object ? object.iconId : ""
                    discColor: object ? root.colorOf(object.filePath) : Theme.color.primary
                    contentAlpha: slot.ev.contentAlpha
                    fakePressed: root.fakePressed && slot.first + index === 0
                    enabled: !view.dragging
                    transform: Scale {
                        origin.x: wcell.width / 2
                        origin.y: 0
                        xScale: slot.ev.scale
                        yScale: slot.ev.scale
                    }
                    onActivated: root.activated(object, wcell.disc)
                    onLongPressed: root.longPressed(object)
                }
            }
        }
    }

    // ---- the end of the list ----
    EdgeButton {
        id: edgeButton
        // a list that fits the screen does not scroll: its button shows in full
        flickable: view.contentHeight + view.topMargin + view.bottomMargin > view.height ? view : null
        preferredHeight: Theme.size.edgeButtonMedium
        // "All apps": up to 2 lines and no icon (the control's own label);
        // "Grid view" and "List view": the label (shrinking to 10 sp), then a 24 dp icon
        text: root.edgeIcon === "" ? root.edgeText : ""
        visible: root.edgeText !== "" && shownHeight > 0.5
        onClicked: root.edgeClicked()

        Row {
            id: edgeRow
            visible: root.edgeIcon !== ""
            anchors.centerIn: parent
            spacing: Theme.space.s
            opacity: 1 - edgeButton.shape.fade
            layoutDirection: Theme.layoutDirection

            Label {
                id: edgeLabel
                anchors.verticalCenter: parent.verticalCenter
                text: root.edgeText
                role: "labelMedium"
                color: edgeButton.contentColor
                maximumLineCount: 1
                // shrinks to 10 sp when the button is narrow
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Theme.sp(10)
                width: Math.min(implicitWidth, Math.max(0, 2 * edgeButton.shape.contentHalfWidth - Theme.dp(24) - Theme.space.s))
            }
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.size.iconSmall
                height: width
                name: root.edgeIcon
                color: edgeButton.contentColor
            }
        }
    }
}
