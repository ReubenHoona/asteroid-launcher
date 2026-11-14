/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSWRIST_H
#define EOSWRIST_H

#include <QPointF>
#include <QString>
#include <QVariant>

/*
 * The wrist and crown setting as Wear OS has it (W3-launcher-wrist). Stock
 * keeps one number, Settings.Global wear_wrist_orientation_mode 0..3, default 0
 * (WristOrientationFragment.java:52-68):
 *
 *   mode  wrist  crown  display
 *    0    left   right  normal (the default)
 *    1    left   left   rotated 180
 *    2    right  right  normal
 *    3    right  left   rotated 180
 *
 * Here it is the dconf key below, written by Settings (and the first run).
 * Only the pure rules are in this header (Qt Core only, tests/tst_wrist.cpp):
 * which modes turn the picture, which are the right wrist, and the one sign
 * the touch code needs to follow the turned picture.
 */
namespace EosWrist {

inline const QString &key()
{
    static const QString k = QStringLiteral("/org/asteroidos/settings/wrist-orientation-mode");
    return k;
}

// What an unreadable or out of range stored value means: stock's default 0
inline int normalize(const QVariant &v)
{
    bool ok = false;
    const int m = v.isValid() ? v.toInt(&ok) : 0;
    return ok && m >= 0 && m <= 3 ? m : 0;
}

// the crown is on the left: stock freezeRotation(ROTATION_180) (WristOrientationObserver.java:85-91)
inline bool crownLeft(int mode) { return mode == 1 || mode == 3; }
// everything the framework draws is turned by 180 degrees: exactly the crown-left modes
inline bool flipped(int mode) { return crownLeft(mode); }
inline int rotation(int mode) { return flipped(mode) ? 180 : 0; }
// the watch is worn on the right wrist (the one-handed gesture indicator mirrors there,
// dialer fmb.java:15-23, czw.java:120-129)
inline bool rightWrist(int mode) { return mode == 2 || mode == 3; }
// the factor of the gesture pointer's X offset: negated on the right wrist
inline int gestureXSign(int mode) { return rightWrist(mode) ? -1 : 1; }

// The crown's scroll after the flip: stock's RotaryEncoderInputMapper::sync() negates the scroll when
// the viewport is ROTATION_180, so the content still moves the way the crown turns relative to the user
inline int wheelDelta(int delta, bool flip) { return flip ? -delta : delta; }

/* Which way the screen's x axis points in an item's logical (untouched by the flip) space: +1 normally,
 * -1 under the 180 degree root rotation. Give it the scene displacement of one item unit along x
 * (mapToScene(1,0) - mapToScene(0,0)); the item's own scale or move do not change the sign, so a swipe
 * that moves the window itself (the back swipe) is still followed in screen pixels (wrist-orientation-07). */
inline int axisSign(const QPointF &unitX) { return unitX.x() < 0 ? -1 : 1; }

} // namespace EosWrist

#endif // EOSWRIST_H
