/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.controls
import org.asteroid.utils
import "a11y.js" as A11y

/*
 * Magnification (W3-launcher-a11y-security, accessibility-lock-security-15):
 * stock Settings > Accessibility > Magnification. Switched on in Settings,
 * a triple tap with one finger zooms the whole scene (home screen and every
 * window: the compositor root item) in around the tap point to the chosen
 * size (1.5 to 3.0 x, default 2.0 x); another triple tap zooms out; with it
 * magnified one finger moves around the screen
 * (config_enable_a11y_magnification_single_panning); a 4 dp border marks it;
 * 'Vibrate on edge' plays a click when the pan reaches the screen edge.
 *
 * dconf: /org/asteroidos/a11y/magnification (b, off), -scale (d, 2.0),
 * -edge-haptic (b, off).
 *
 * compositor.qml puts `transforms` on its root item: Scale(s) then
 * Translate(t) in window coordinates, so the scene point p shows at
 * p * s + t and touches arrive in scene coordinates as Qt does for a
 * transformed item. The scene is a transform, not a texture: nothing is
 * drawn twice. Nothing runs while it is off: the touch observer is not
 * installed (TouchObserver) and no handler is enabled.
 *
 * Taps come from TouchObserver (the stock multi-tap rules, 300 ms + 25 ms
 * between taps). The pan is a DragHandler of this item, enabled only while
 * magnified: it takes the drag from the content below, as stock does.
 */
Item {
    id: mag
    objectName: "magnifier"
    anchors.fill: parent

    // the touch observer of the launcher (a test double in tests)
    property QtObject observer: typeof touchObserver !== "undefined" ? touchObserver : null

    ConfigurationValue {
        id: enabledSetting
        key: A11y.KEY_MAGNIFICATION
        defaultValue: false
    }
    ConfigurationValue {
        id: scaleSetting
        key: A11y.KEY_MAGNIFICATION_SCALE
        defaultValue: A11y.DEFAULT_SCALE
    }
    ConfigurationValue {
        id: edgeSetting
        key: A11y.KEY_MAGNIFICATION_EDGE
        defaultValue: false
    }

    readonly property bool enabledByUser: enabledSetting.value === true || enabledSetting.value === "true"
    readonly property real chosenScale: A11y.validScale(scaleSetting.value)
    readonly property bool edgeHaptic: edgeSetting.value === true || edgeSetting.value === "true"

    // zoomed in now
    property bool magnified: false
    // the factor in force (1 when not magnified)
    readonly property real zoom: magnified ? chosenScale : 1.0
    // the scene offset in window pixels
    property real tx: 0
    property real ty: 0
    readonly property alias scaleTransform: sc
    readonly property alias translateTransform: tr
    readonly property list<QtObject> transforms: [sc, tr]

    Scale {
        id: sc
        xScale: mag.zoom
        yScale: mag.zoom
    }
    Translate {
        id: tr
        x: mag.tx
        y: mag.ty
    }

    // the screen is width x height in window pixels (this item fills the scene root)
    function zoomIn(x, y) {
        if (!enabledByUser)
            return
        tx = A11y.zoomAt(x, chosenScale, width)
        ty = A11y.zoomAt(y, chosenScale, height)
        magnified = true
    }

    function zoomOut() {
        magnified = false
        tx = 0
        ty = 0
    }

    function toggle(x, y) {
        if (magnified)
            zoomOut()
        else
            zoomIn(x, y)
    }

    // a finger moved by (dx, dy) window pixels
    function panBy(dx, dy) {
        if (!magnified)
            return
        var px = A11y.pan(tx, dx, zoom, width)
        var py = A11y.pan(ty, dy, zoom, height)
        tx = px.t
        ty = py.t
        if ((px.hit || py.hit) && edgeHaptic)
            Haptics.limit()
    }

    // the size chosen in Settings while magnified: the view stays inside the screen
    onChosenScaleChanged: {
        if (magnified) {
            tx = A11y.clampPan(tx, chosenScale, width)
            ty = A11y.clampPan(ty, chosenScale, height)
        }
    }
    onEnabledByUserChanged: if (!enabledByUser) zoomOut()

    Binding {
        target: mag.observer
        property: "tripleTap"
        value: mag.enabledByUser
        when: mag.observer !== null
    }
    Binding {
        target: mag.observer
        property: "density"
        value: Theme.dp(1)
        when: mag.observer !== null
    }
    Connections {
        target: mag.observer
        ignoreUnknownSignals: true
        function onMultiTap(fingers, taps, x, y) {
            if (fingers === 1 && taps === 3)
                mag.toggle(x, y)
        }
    }

    // the finger moves the screen while magnified
    DragHandler {
        id: drag
        target: null
        enabled: mag.magnified
        property real lastX: 0
        property real lastY: 0
        onActiveChanged: {
            lastX = 0
            lastY = 0
        }
        onTranslationChanged: {
            var dx = translation.x - lastX
            var dy = translation.y - lastY
            lastX = translation.x
            lastY = translation.y
            mag.panBy(dx, dy)
        }
    }

    /* the border: 4 dp in window pixels whatever the zoom is (the scene is scaled with this
     * item, so the border is drawn at the inverse scale from the window corner) */
    Rectangle {
        id: border
        objectName: "magnifierBorder"
        visible: mag.magnified
        readonly property real inverse: 1 / mag.zoom
        x: -mag.tx * inverse
        y: -mag.ty * inverse
        width: mag.width * inverse
        height: mag.height * inverse
        radius: DeviceSpecs.hasRoundScreen ? width / 2 : 0
        color: "transparent"
        border.width: Theme.dp(A11y.BORDER_DP) * inverse
        border.color: Theme.color.primary
        z: 1000
    }
}
