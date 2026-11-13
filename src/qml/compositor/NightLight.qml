/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick

/*
 * Bedtime's colour filter (modes-dnd-09): Night light at 2596 K by default,
 * or Grayscale, as Settings > Bedtime > Customize > Display options chooses
 * (dconf /org/asteroidos/modes/bedtime/display-filter; the modes engine,
 * modes.h, turns the choice and Bedtime into displayFilter and the colour
 * matrix, modescore.cpp filterMatrix). The compositor draws its whole scene
 * through the filter while it is on, the way Android's ColorDisplayService
 * puts a colour transform on the display: a shader over the scene's layer
 * (shaders/colorfilter.frag). No DRM colour matrix (CTM) is used; where the
 * kernel offers one it would do the same without the extra pass.
 *
 * compositor.qml: layer.enabled: nightLight.active; layer.effect: nightLight.effect
 * The layer exists only while the filter is on: the extra render pass costs
 * nothing the rest of the time (battery).
 */
QtObject {
    id: nightLight

    readonly property bool modesReady: typeof modes !== "undefined" && modes !== null
    // "", "nightlight" or "grayscale"
    readonly property string filter: modesReady ? modes.displayFilter : ""
    readonly property bool active: filter !== ""
    // the 3x3 colour matrix, row-major (identity with no filter)
    readonly property var coefficients: modesReady && modes.filterMatrix && modes.filterMatrix.length === 9
                                        ? modes.filterMatrix : [1, 0, 0, 0, 1, 0, 0, 0, 1]
    readonly property matrix4x4 colorMatrix: Qt.matrix4x4(
        coefficients[0], coefficients[1], coefficients[2], 0,
        coefficients[3], coefficients[4], coefficients[5], 0,
        coefficients[6], coefficients[7], coefficients[8], 0,
        0, 0, 0, 1)

    readonly property Component effect: Component {
        ShaderEffect {
            property matrix4x4 colorMatrix: nightLight.colorMatrix
            fragmentShader: "qrc:/shaders/colorfilter.frag.qsb"
        }
    }
}
