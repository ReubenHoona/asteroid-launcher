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
 *   - a spacer (topSpacer), then the header (titleLarge, 18 sp on a 20 sp
 *     line, weight 500, 0.2 sp tracking, onSurface, centred, up to 2 lines,
 *     4 dp above and 31 px below). Wear OS 6 has the list and Recents higher
 *     than CP3A's 13 % (61 dp): with a 20 px spacer the first row's top is at
 *     y 99 and the header, shrunk and packed against it by the edge
 *     transformation, has its cap top at y 45-46; the grid has a 51 px
 *     spacer (header cap top y 72, first row of discs at y 130) (emulator
 *     S04, S04-b, S04-c, S05; N61-32);
 *   - rows (columns: 1): 52 dp pills 172 dp wide (5.2 % side padding), 4 dp
 *     apart (app-launcher-04); or a grid (columns: 3) of 48 dp icons 6 dp
 *     apart in rows of three (app-launcher-16);
 *   - the end: a Medium (70 dp) edge button 12 dp under the last row
 *     ("Grid view", "List view", "All apps"; app-launcher-15), the label
 *     over the view's glyph (N61-33);
 *   - every row, the header and the grid rows take the launcher's edge
 *     transformation, packed (WearEdge.js layout, app-launcher-07); the
 *     header always the list's (LIST), as Wear OS 6 draws the grid's;
 *   - no TimeText (app-launcher-21).
 *
 * The base is the shared ScalingList (stock fling, stretch at the ends and
 * the crown with its tick haptics). The rows keep their natural place in it,
 * so it scrolls evenly and its end is where the edge button expects it; what
 * is drawn where is the layout property, computed again as the list moves.
 *
 * Content: model (rows: its "object" role holds a LauncherItem) or, for the
 * grid, cells (an object with itemCount and get(i)). The rows' colours come
 * from colorOf(filePath), glyphOf(filePath) and ownIconOf(filePath) (the
 * .desktop file's X-Asteroid-Center-Color, X-Eos-Glyph-Color and
 * X-Eos-Own-Icon, AppLauncherBackground), their status line from
 * statusOf(object).
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
    property var glyphOf: function (path) { return "white" }
    property var ownIconOf: function (path) { return false }
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
    /* Above the header (N61-32, emulator S04, S04-b): 5.2 % of the height for
     * the list and Recents (20 px), 13.3 % for the grid (51 px); whole pixels,
     * so the text is not drawn between two */
    readonly property real topSpacer: Math.round(Theme.dp((columns > 1 ? 0.133 : 0.052) * Theme.screenHeightDp))
    /* Under the header to the first row: 31 px. Shrunk by the edge
     * transformation and packed against the first row it leaves the gap of
     * the emulator (header cap top y 46 over the list, 72 over the grid) */
    readonly property real headerBottom: Theme.dp(15.5)
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
     * The intro slide (app-launcher-08): each time the list opens, the content
     * slides up 0.2 of the height (77 px) in 400 ms, CubicBezier(0, 0, 0, 1)
     * (stock hdu.java:578-590, launcher_scroll_to_top_anim_duration_ms,
     * ListLauncherIntroAnimationJank), so the top spacer goes from 0.252 to
     * 0.052 of the height for the list and Recents, 0.333 to 0.133 for the
     * grid (N61-32: the same slide, ending at the Wear OS 6 spacer).
     * Called by AppDrawer.open(), not by openNow() (back from an app). With Reduce
     * animations on it is not shown. introShift is added to where the layout
     * draws the header and the rows.
     */
    property real introShift: 0
    function intro() {
        introAnim.stop()
        if (Motion.animationScale === 0) {
            introShift = 0
            return
        }
        introShift = height * 0.2
        introAnim.restart()
    }
    NumberAnimation {
        id: introAnim
        target: root
        property: "introShift"
        to: 0
        duration: 400
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0, 0, 0, 1, 1, 1]
    }

    /*
     * Where the header and the rows are drawn (WearEdge.js layout): item 0 is the
     * header, item i + 1 the row i. Computed again with every move of the list,
     * from the natural places only.
     */
    readonly property var layout: {
        var n = view.count
        var vh = view.height
        var tops = [headerItem.y + root.introShift], hs = [headerItem.rawHeight], gaps = [0]
        for (var i = 0; i < n; i++) {
            tops.push(view.originY + i * root.pitch - view.contentY + root.introShift)
            hs.push(root.itemHeight)
            gaps.push(root.itemGap)
        }
        return Edge.layout(root.spec, tops, hs, gaps, vh, Motion.reduceMotion, Edge.LIST)
    }

    ScalingList {
        id: view
        anchors.fill: parent
        clip: true
        cacheBuffer: height
        spacing: root.itemGap
        // the spacer, then the header (4 dp, its line, headerBottom): the first row's top at y 99 (grid 130)
        topMargin: root.topSpacer + headerItem.rawHeight
        // the edge button 70 dp high, 3 dp above the edge, and 12 dp between it and the last row
        bottomMargin: edgeButton.preferredHeight + Theme.size.edgeButtonBottomGap + Theme.space.l
        model: root.columns > 1 ? Math.ceil(root.cellCount / root.columns) : root.model
        delegate: root.columns > 1 ? gridDelegate : rowDelegate
    }

    // ---- the header: over the list, scrolls with the rows ----
    Item {
        id: headerItem
        width: root.width
        // the natural place: the spacer under the top at rest, then up with the content
        y: root.topSpacer - (view.contentY - root.topPosition)
        readonly property real rawHeight: headerBox.height
        readonly property var ev: root.layout[0] || Edge.UNPLACED

        Item {
            id: headerBox
            width: parent.width
            // where the layout draws it, from the natural place
            y: headerItem.ev.unplaced ? 0 : headerItem.ev.y - headerItem.y
            height: titleTop + headerLabel.height + (emptyLabel.visible ? emptyLabel.height + emptyLabel.topPad + emptyLabel.bottomPad : 0) + titleBottom
            readonly property real titleTop: Theme.dp(4)
            // to the first row
            readonly property real titleBottom: root.headerBottom
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
                glyphColor: slot.object ? root.glyphOf(slot.object.filePath) : "white"
                ownIcon: slot.object ? root.ownIconOf(slot.object.filePath) : false
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
                    glyphColor: object ? root.glyphOf(object.filePath) : "white"
                    ownIcon: object ? root.ownIconOf(object.filePath) : false
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
        // "Grid view" and "List view": the label over the view's glyph
        text: root.edgeIcon === "" ? root.edgeText : ""
        visible: root.edgeText !== "" && shownHeight > 0.5
        onClicked: root.edgeClicked()

        /* Wear OS 6 (emulator S05-b, S05-c; N61-33): one line of labelMedium in
         * onPrimary, then the glyph centred in a 24 dp slot under it, the two
         * centred together in the button, 1.5 dp above its middle: at full size
         * the label's ink at y 269-291 and the glyph box's centre at y 325, as
         * the emulator's (the control's own label, "All apps", sits 3 px lower
         * than the emulator's: cap top y 297 against 294) */
        Column {
            id: edgeContent
            visible: root.edgeIcon !== ""
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -Theme.dp(1.5)
            opacity: 1 - edgeButton.shape.fade

            Label {
                id: edgeLabel
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.edgeText
                role: "labelMedium"
                color: edgeButton.contentColor
                horizontalAlignment: Text.AlignHCenter
                maximumLineCount: 1
                // shrinks to 10 sp when the button is narrow
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Theme.sp(10)
                width: Math.min(implicitWidth, Math.max(0, 2 * edgeButton.shape.contentHalfWidth))
            }
            Item {
                id: edgeGlyph
                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.size.iconSmall
                height: width

                // the emulator's "List view" glyph: three rounded bars 11, 18 and 11 dp wide,
                // 2.5 dp high, 5.25 dp apart (box 18 x 13 dp)
                Repeater {
                    model: root.edgeIcon === "eos-view-list" ? [11, 18, 11] : []
                    Rectangle {
                        required property int index
                        required property var modelData
                        width: Theme.dp(modelData)
                        height: Theme.dp(2.5)
                        radius: height / 2
                        x: (edgeGlyph.width - width) / 2
                        y: (edgeGlyph.height - Theme.dp(13)) / 2 + index * Theme.dp(5.25)
                        color: edgeButton.contentColor
                    }
                }
                // the emulator's "Grid view" glyph: 3 x 3 dots of 4 dp at a 6 dp pitch (box 16 x 16 dp)
                Repeater {
                    model: root.edgeIcon === "eos-view-grid" ? 9 : 0
                    Rectangle {
                        required property int index
                        width: Theme.dp(4)
                        height: width
                        radius: width / 2
                        x: (edgeGlyph.width - Theme.dp(16)) / 2 + (index % 3) * Theme.dp(6)
                        y: (edgeGlyph.height - Theme.dp(16)) / 2 + Math.floor(index / 3) * Theme.dp(6)
                        color: edgeButton.contentColor
                    }
                }
                // any other name: an icon of the set
                Icon {
                    visible: root.edgeIcon !== "eos-view-list" && root.edgeIcon !== "eos-view-grid"
                    anchors.fill: parent
                    name: visible ? root.edgeIcon : ""
                    color: edgeButton.contentColor
                }
            }
        }
    }
}
