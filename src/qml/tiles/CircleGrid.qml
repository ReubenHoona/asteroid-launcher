/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * The circle buttons of the Wear OS 6 Clock and Contacts tiles (the emulator's
 * Timer tile S13 and its Favorite contacts preview S14-d): cells of 52 dp,
 * 8 dp apart both ways; five as a row of two over a row of three, four as two
 * over two, three or fewer in one row; each row centred, the rows together
 * centred in the grid. Filling an expressive tile's body (y 52-275 at 384 px),
 * five cells are centred at (132, 104), (252, 104), (72, 224), (192, 224) and
 * (312, 224). At most five are shown.
 *
 * The delegate is a TileCard, its own click target: the grid gives it the
 * cell's size and place, and the card's stadium radius (half its side) makes
 * it a circle. N61-26
 */
Item {
    id: grid
    objectName: "circleGrid"

    property alias model: cells.model
    property alias delegate: cells.delegate
    // the side of a cell and the gap between two, px
    property real cell: Theme.dp(52)
    property real gap: Theme.dp(8)
    readonly property alias count: cells.count
    // the cells in each row, from the top
    readonly property var rowCounts: count >= 5 ? [2, 3] : count === 4 ? [2, 2] : count > 0 ? [count] : []
    readonly property real blockHeight: rowCounts.length > 0 ? rowCounts.length * cell + (rowCounts.length - 1) * gap : 0

    // the row and column of cell i, and the cells in its row
    function place(i) {
        var left = i
        for (var r = 0; r < rowCounts.length; r++) {
            if (left < rowCounts[r])
                return { row: r, col: left, n: rowCounts[r] }
            left -= rowCounts[r]
        }
        return { row: -1, col: 0, n: 0 }
    }
    function cellX(i) {
        var p = place(i)
        return (width - (p.n * cell + (p.n - 1) * gap)) / 2 + p.col * (cell + gap)
    }
    function cellY(i) {
        var p = place(i)
        return (height - blockHeight) / 2 + p.row * (cell + gap)
    }
    function itemAt(i) {
        return cells.itemAt(i)
    }

    Repeater {
        id: cells
        onItemAdded: (index, item) => {
            item.width = Qt.binding(function () { return grid.cell })
            item.height = Qt.binding(function () { return grid.cell })
            item.x = Qt.binding(function () { return grid.cellX(index) })
            item.y = Qt.binding(function () { return grid.cellY(index) })
            item.visible = Qt.binding(function () { return grid.place(index).row >= 0 })
        }
    }
}
