/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef HUBOFFLOAD_H
#define HUBOFFLOAD_H

#include <QObject>
#include <QString>

class QQuickItem;

/*
 * The always-on display layout for the sensor hub, as stock Wear OS sends a
 * watch face's offload layout: the hub then draws the time itself while the
 * AP sleeps (no AP wake per minute). Stock only offloads watch faces that
 * provide a layout; here a face takes part by naming its time Text items
 * objectName "eosHubHour24" (two digits, 24 h, leading zero) and
 * "eosHubMinute" (two digits). The layout is: the ambient screen as the AP
 * draws it with those items hidden (the background, grabbed from the
 * compositor window), plus the digits drawn by the hub from a glyph atlas of
 * the items' own font, colour and opacity, bound to the hub's hour and
 * minute (the stock HAL's time.hour24.digitN / time.min.digitN
 * expressions). It is rebuilt only when something in it changes (face,
 * date, item geometry) and is valid until the next local midnight (the date
 * on the background): lipstick then wakes the AP once to rebuild it, as
 * stock schedules an AP update at the layout's minutes_valid.
 */
class HubOffload : public QObject
{
    Q_OBJECT
public:
    explicit HubOffload(QObject *parent = nullptr);

    // Call while the ambient face is on screen (after an ambient update has
    // drawn it). Returns true when the hub has a layout for it.
    Q_INVOKABLE bool update(QQuickItem *face, bool use12h, const QString &faceSource);
    Q_INVOKABLE void clear();

private:
    bool build(QQuickItem *face, QQuickItem *hour, QQuickItem *minute, QString *why);

    QString m_key;
    bool m_loaded = false;
};

#endif // HUBOFFLOAD_H
