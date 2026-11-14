/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The hub's always-on layout under the wrist flip (W3-launcher-wrist, src/eoshubflip.h): the scene transform
 * the digit items may have, the panel position of a turned sprite (the plan's (384 - x - w, 384 - y - h)) and
 * the turned glyph cells. Qt Gui only.
 */

#include "eoshubflip.h"

#include <QTransform>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static QPointF unit(const QTransform &t) { return t.map(QPointF(1, 1)) - t.map(QPointF(0, 0)); }

static void sceneTurn()
{
    CHECK(EosHub::sceneTurn(unit(QTransform())) == 1);
    QTransform move;
    move.translate(40.25, -7);
    CHECK(EosHub::sceneTurn(unit(move)) == 1);
    // the compositor root turned about the display centre
    QTransform turn;
    turn.translate(192, 192);
    turn.rotate(180);
    turn.translate(-192, -192);
    CHECK(EosHub::sceneTurn(unit(turn)) == -1);
    QTransform turnAndMove = turn;
    turnAndMove.translate(13, 5);
    CHECK(EosHub::sceneTurn(unit(turnAndMove)) == -1);
    // anything else cannot be drawn by the hub: refused (the "is rotated or scaled" reason)
    QTransform r90;
    r90.rotate(90);
    CHECK(EosHub::sceneTurn(unit(r90)) == 0);
    QTransform r5;
    r5.rotate(5);
    CHECK(EosHub::sceneTurn(unit(r5)) == 0);
    QTransform scaled;
    scaled.scale(0.8, 0.8);
    CHECK(EosHub::sceneTurn(unit(scaled)) == 0);
    QTransform turnedAndScaled = turn;
    turnedAndScaled.scale(1.1, 1.1);
    CHECK(EosHub::sceneTurn(unit(turnedAndScaled)) == 0);
    QTransform mirror;
    mirror.scale(-1, 1);
    CHECK(EosHub::sceneTurn(unit(mirror)) == 0);
}

// a sprite's panel rectangle upright and under the turn, for items at content position c
static void mirrorProperty()
{
    QTransform turn;
    turn.translate(192, 192);
    turn.rotate(180);
    turn.translate(-192, -192);
    const QRect inks[] = { QRect(-3, -41, 36, 52), QRect(2, -30, 17, 31), QRect(-1, -60, 70, 80), QRect(0, 0, 5, 7) };
    const qreal xs[] = { 0, 10, 74, 96.3, 120.75, 200.5 - 0.25, 311.1, 300 };
    const qreal ys[] = { 0, 33, 152, 98.6, 170.5 + 0.25, 250.9, 340 };
    const qreal pens[] = { 0, 0.25, 31.5, 63.0, 63.75 };
    const qreal bases[] = { 59.0, 59.4, 60.6, 100.0 };
    int n = 0;
    for (const QRect &ink : inks)
        for (qreal cx : xs)
            for (qreal cy : ys)
                for (qreal penX : pens)
                    for (qreal baseY : bases) {
                        const QPointF contentItem(cx, cy);
                        // upright: the item's scene origin is its content position
                        const QPoint up = EosHub::spriteTopLeft(EosHub::glyphOrigin(contentItem, penX, baseY, false),
                                                                ink, false);
                        // turned: the scene origin of the item's local (0, 0) is its turned content position
                        const QPointF sceneItem = turn.map(contentItem);
                        const QPoint tu = EosHub::spriteTopLeft(EosHub::glyphOrigin(sceneItem, penX, baseY, true),
                                                                ink, true);
                        // the turned rectangle is the point mirror of the upright one (the plan's formula),
                        // unless the item's position sits exactly half way between two pixels (the scene
                        // graph's floor(v + 0.5) then rounds the other way for the mirrored vertex)
                        const bool tieX = std::fabs(cx - std::floor(cx) - 0.5) < 1e-9;
                        const bool tieY = std::fabs(cy - std::floor(cy) - 0.5) < 1e-9;
                        if (!tieX)
                            CHECK(tu.x() == 384 - up.x() - ink.width());
                        if (!tieY)
                            CHECK(tu.y() == 384 - up.y() - ink.height());
                        n++;
                    }
    CHECK(n > 1000);
    // one worked case: face digit at (74, 152), pen 31.5, baseline 59.4, ink (-3, -41, 36, 52)
    const QRect ink(-3, -41, 36, 52);
    const QPoint up = EosHub::spriteTopLeft(EosHub::glyphOrigin(QPointF(74, 152), 31.5, 59.4, false), ink, false);
    CHECK(up == QPoint(74 + 31 - 3, 152 + 59 - 41));
    const QPoint tu = EosHub::spriteTopLeft(EosHub::glyphOrigin(QPointF(310, 232), 31.5, 59.4, true), ink, true);
    CHECK(tu == QPoint(384 - up.x() - 36, 384 - up.y() - 52));
    CHECK(tu == QPoint(246, 162));
    // the turn twice is the identity: the sprite of an upright 180 degree face is back in place
    CHECK(QPoint(384 - tu.x() - 36, 384 - tu.y() - 52) == up);
}

static void cells()
{
    // two cells of 3 x 2, stride 6:  cell 0 = 1 2 3 / 4 5 6, cell 1 = 7 8 9 / 10 11 12
    QByteArray strip(12, 0);
    const char v[12] = { 1, 2, 3, 7, 8, 9, 4, 5, 6, 10, 11, 12 };
    memcpy(strip.data(), v, 12);
    EosHub::turnCells180(&strip, 3, 2, 2);
    const char want[12] = { 6, 5, 4, 12, 11, 10, 3, 2, 1, 9, 8, 7 };
    CHECK(memcmp(strip.constData(), want, 12) == 0);
    // twice is the original
    EosHub::turnCells180(&strip, 3, 2, 2);
    CHECK(memcmp(strip.constData(), v, 12) == 0);
    // a blank cell stays blank, an odd height has a middle row that only reverses
    QByteArray odd(3 * 2 * 3, 0);
    for (int y = 0; y < 3; y++)
        for (int x = 0; x < 3; x++)
            odd[y * 6 + x] = char(1 + y * 3 + x);       // cell 0 = 1..9, cell 1 blank
    EosHub::turnCells180(&odd, 3, 2, 3);
    for (int i = 0; i < 9; i++)
        CHECK(odd[(i / 3) * 6 + i % 3] == char(9 - i));
    for (int y = 0; y < 3; y++)
        for (int x = 0; x < 3; x++)
            CHECK(odd[y * 6 + 3 + x] == 0);
    // a big cell, as the faces' digits (48 x 80): a pixel (x, y) goes to (47 - x, 79 - y)
    const int cw = 48, ch = 80, cc = 5;
    QByteArray big(cw * cc * ch, 0);
    for (int c = 0; c < cc; c++)
        for (int y = 0; y < ch; y++)
            for (int x = 0; x < cw; x++)
                big[y * cw * cc + c * cw + x] = char((x * 7 + y * 13 + c * 29) & 0xff);
    const QByteArray orig = big;
    EosHub::turnCells180(&big, cw, cc, ch);
    bool ok = true;
    for (int c = 0; c < cc && ok; c++)
        for (int y = 0; y < ch && ok; y++)
            for (int x = 0; x < cw; x++)
                if (big[(ch - 1 - y) * cw * cc + c * cw + (cw - 1 - x)] != orig[y * cw * cc + c * cw + x]) {
                    ok = false;
                    break;
                }
    CHECK(ok);
}

int main()
{
    sceneTurn();
    mirrorProperty();
    cells();
    if (failures)
        fprintf(stderr, "tst_hubflip: %d of %d checks failed\n", failures, checks);
    else
        fprintf(stderr, "tst_hubflip: all %d checks passed\n", checks);
    return failures ? 1 : 0;
}
