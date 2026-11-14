/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import "a11y.js" as A11y

/*
 * Colour correction and Grayscale (W3-launcher-a11y-security,
 * accessibility-lock-security-16): stock Settings > Accessibility > Colour
 * correction: 'Use color correction' and one of Red-green / Green weak,
 * deuteranomaly (default), Red-green / Red weak, protanomaly, Blue-yellow /
 * Tritanomaly, Grayscale. dconf /org/asteroidos/a11y/color-correction (b, off)
 * and -mode (s: deuteranomaly, protanomaly, tritanomaly, grayscale).
 *
 * `coefficients` is the 3 x 3 matrix (row-major) of the mode; NightLight.qml
 * draws the compositor scene through it, after Bedtime's own filter, with the
 * shader pass it already has (the pass exists only while a filter is on;
 * nothing is drawn through it otherwise). The audit asks for the display
 * controller's colour matrix (DRM CTM) instead; the launcher cannot reach the
 * CRTC property from its Wayland compositor on this stack without the KMS
 * device's file descriptor, so the matrix is the same and the way of applying
 * it is the shader pass. The always-on screen the sensor hub draws is not
 * corrected (the Settings page says so).
 */
QtObject {
    id: cc

    property QtObject enabledSetting: ConfigurationValue {
        key: A11y.KEY_COLOR_CORRECTION
        defaultValue: false
    }
    property QtObject modeSetting: ConfigurationValue {
        key: A11y.KEY_COLOR_CORRECTION_MODE
        defaultValue: A11y.DEFAULT_MODE
    }

    readonly property bool active: enabledSetting.value === true || enabledSetting.value === "true"
    readonly property string mode: A11y.validMode(String(modeSetting.value))
    readonly property var coefficients: active ? A11y.correctionMatrix(mode) : A11y.IDENTITY
}
