/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSSCREENSHOT_H
#define EOSSCREENSHOT_H

#include <QDateTime>
#include <QDir>
#include <QImage>
#include <QPainter>
#include <QPainterPath>
#include <QString>

/*
 * The file a screenshot is (system-dialogs-misc-09), as stock's
 * WearScreenshotService / WearScreenshotHelper: the display masked to a
 * circle with transparent corners, a PNG named "wear_screenshot" and the
 * time, in Pictures/Screenshots. Qt Gui only (tests/tst_screenshot.cpp).
 */
namespace EosShot {

// wear_screenshot_20261114-093015.png
inline QString fileName(const QDateTime &when)
{
    return QStringLiteral("wear_screenshot_") + when.toString(QStringLiteral("yyyyMMdd-HHmmss"))
           + QStringLiteral(".png");
}

// <Pictures>/Screenshots
inline QString directory(const QString &pictures)
{
    return pictures + QStringLiteral("/Screenshots");
}

/* The capture cut to the round screen: the circle that fits the shorter
 * side, centred; everything outside is cleared to transparent
 * (CompositionMode_Clear). */
inline QImage roundMask(const QImage &in)
{
    QImage out = in.convertToFormat(QImage::Format_ARGB32_Premultiplied);
    const qreal side = qMin(out.width(), out.height());
    QPainterPath outside;
    outside.addRect(QRectF(0, 0, out.width(), out.height()));
    QPainterPath disc;
    disc.addEllipse(QRectF((out.width() - side) / 2, (out.height() - side) / 2, side, side));
    outside = outside.subtracted(disc);
    QPainter p(&out);
    p.setRenderHint(QPainter::Antialiasing);
    p.setCompositionMode(QPainter::CompositionMode_Clear);
    p.fillPath(outside, Qt::transparent);
    p.end();
    return out;
}

/* The path to save at: `pictures` is the Pictures location. Makes the folder. */
inline QString savePath(const QString &pictures, const QDateTime &when)
{
    const QString dir = directory(pictures);
    QDir().mkpath(dir);
    return dir + QLatin1Char('/') + fileName(when);
}

} // namespace EosShot

#endif // EOSSCREENSHOT_H
