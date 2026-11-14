/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSHUBFLIP_H
#define EOSHUBFLIP_H

#include <QByteArray>
#include <QPoint>
#include <QPointF>
#include <QRect>
#include <cmath>

/*
 * The hub's always-on layout under the wrist flip (W3-launcher-wrist, wrist-orientation-08).
 *
 * With the crown on the left the compositor's root is turned 180 degrees about the display
 * centre, so the window grab that is the layout's background is already the picture as the
 * panel shows it (turned). Stock wraps its layout in a RotationGroup (constant 180 degrees,
 * pivot (192, 192): HalResourceStore.java:251-258, HalTypeConverterV3.java:312-330); here the
 * layout stays in panel coordinates and needs no new hub op: each digit sprite is what the
 * scene graph draws for a Text item under a 180 degree turn, the glyph bitmap turned in itself,
 * at the panel position of the turned quad. Plain Qt Core, host tested by tests/tst_hubflip.cpp.
 */
namespace EosHub {

/* Whether an item's scene transform is the identity (+1: upright), or a 180 degree turn (-1).
 * unit: mapToScene(1, 1) - mapToScene(0, 0) of the Text item. Any other transform (a rotation by
 * another angle, a scale, a mirror) is neither: 0, and the face is not offloaded. */
inline int sceneTurn(const QPointF &unit)
{
    if (std::fabs(unit.x() - 1) < 1e-6 && std::fabs(unit.y() - 1) < 1e-6)
        return 1;
    if (std::fabs(unit.x() + 1) < 1e-6 && std::fabs(unit.y() + 1) < 1e-6)
        return -1;
    return 0;
}

/* The pixel a glyph's origin has in the panel, as the scene graph snaps it (Qt 6.11
 * QSGTextMaskMaterial::populate + textmask.vert: each vertex floor(v + 0.5) in the scene; the
 * pen x floored and the baseline y rounded inside the item).
 *   item: the scene position of the item's local (0, 0). Upright it is the item's top-left; under
 *         the 180 degree turn it is the item's bottom-right corner on the panel.
 *   penX, baseY: the glyph's pen and baseline in the item.
 * Upright: the origin is where the glyph's origin is. Turned: the origin of the *turned* glyph
 * frame, the panel point the upright glyph's origin maps to; the turned quad then runs from
 * origin - (ink.right() + 1, ink.bottom() + 1) (spriteTopLeft). */
inline QPoint glyphOrigin(const QPointF &item, qreal penX, qreal baseY, bool turned)
{
    const int ix = int(std::floor(item.x() + 0.5)), iy = int(std::floor(item.y() + 0.5));
    const int gx = int(std::floor(penX)), gy = int(std::lround(baseY));
    return turned ? QPoint(ix - gx, iy - gy) : QPoint(ix + gx, iy + gy);
}

/* The panel position of a sprite's top-left pixel. ink: the cell's rectangle relative to the
 * upright glyph origin. Turned: the cell is the upright cell turned in itself (turnCells180),
 * so it occupies the point mirror of the ink rectangle: (384 - x - w, 384 - y - h) of the
 * plan, with the pivot folded into `origin`. */
inline QPoint spriteTopLeft(const QPoint &origin, const QRect &ink, bool turned)
{
    return turned ? origin - QPoint(ink.right() + 1, ink.bottom() + 1) : origin + ink.topLeft();
}

/* A row of A8 cells (`cells` cells of cw x ch pixels, row stride cw * cells) with every cell
 * turned by 180 degrees in itself: the bitmap of a glyph the scene graph draws under a 180 degree
 * turn. The blank cell (all zero) is unchanged. */
inline void turnCells180(QByteArray *strip, int cw, int cells, int ch)
{
    const int stride = cw * cells;
    const QByteArray in = *strip;
    char *out = strip->data();
    for (int c = 0; c < cells; c++)
        for (int y = 0; y < ch; y++)
            for (int x = 0; x < cw; x++)
                out[(ch - 1 - y) * stride + c * cw + (cw - 1 - x)] = in[y * stride + c * cw + x];
}

} // namespace EosHub

#endif // EOSHUBFLIP_H
