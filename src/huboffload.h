/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef HUBOFFLOAD_H
#define HUBOFFLOAD_H

#include <QDateTime>
#include <QObject>
#include <QString>

class QQuickItem;

/*
 * The always-on display layout for the sensor hub, as stock Wear OS sends a
 * watch face's offload layout: the hub then draws the time itself while the
 * AP sleeps (no AP wake per minute). Stock only offloads watch faces that
 * provide a layout; here a face takes part by naming its time Text items
 * objectName "eosHubHour" (the hours as the face shows them: 24 h with a
 * leading zero, 12 h 1..12 without) and "eosHubMinute" (two digits). The
 * digits must be tabular (every digit one advance wide) and drawn with
 * NativeRendering, as the bundled digital faces do.
 *
 * The layout is: the ambient screen as the AP draws it with those items
 * hidden (the background, grabbed from the compositor window: the date, the
 * AM/PM text and everything else that is not the time), plus one glyph
 * sprite per digit drawn by the hub from atlases of the items' own font,
 * colour and opacity, bound to the hub's hour and minute (the stock HAL's
 * time.*.digitN expressions). Each digit lands on the pixel and sub-pixel
 * phase the Qt Quick scene graph gives it, so the picture does not move when
 * the hub takes over. In 12 h a one-digit hour is centred (or aligned) as the
 * face's Text item places it: the layout has both the one- and the two-digit
 * hour and the hub shows one or the other ("<" and "?:" in the glyph
 * expressions).
 *
 * The layout is rebuilt only when something in it changes (face, date, item
 * geometry) and is valid until the background changes: the next local
 * midnight (the date), in 12 h also the next noon (AM/PM), and the next
 * change of the hour's digit count when that moves other items (an AM/PM
 * text anchored to the hour). lipstick then wakes the AP once to rebuild it,
 * as stock schedules an AP update at the layout's minutes_valid.
 */
class HubOffload : public QObject
{
    Q_OBJECT
public:
    explicit HubOffload(QObject *parent = nullptr);

    // Call while the ambient face is on screen (after an ambient update has
    // drawn it), with the time the face shows. Returns true when the hub has
    // a layout for it.
    // moveMinutes: the burn-in protection moves the face at most this often
    // (0: never), at a display off (LipstickCompositor::setOffloadLayout)
    Q_INVOKABLE bool update(QQuickItem *face, bool use12h, const QString &faceSource,
                            const QDateTime &shown, int moveMinutes = 0);
    // No layout for the hub (the face is not to be offloaded now)
    Q_INVOKABLE void clear();
    // The face, or a setting it draws with, changed: whatever layout the
    // daemon holds is stale, drop it at once (stock: a watch face change
    // clears the offload layout), the next ambient update builds a new one
    Q_INVOKABLE void invalidate();

private:
    bool build(QQuickItem *face, QQuickItem *hour, QQuickItem *minute, bool use12h,
               const QDateTime &shown, QDateTime *until, QString *why);
    void drop(bool daemonHasLayout);

    QString m_key;
    QDateTime m_until;
    QString m_failedKey;
    bool m_loaded = false;
    int m_moveMinutes = 0;
};

#endif // HUBOFFLOAD_H
