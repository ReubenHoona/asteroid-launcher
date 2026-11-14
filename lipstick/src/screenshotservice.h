/***************************************************************************
**
** Copyright (C) 2013 Jolla Ltd.
** Contact: Robin Burchell <robin.burchell@jollamobile.com>
**
** This file is part of lipstick.
**
** This library is free software; you can redistribute it and/or
** modify it under the terms of the GNU Lesser General Public
** License version 2.1 as published by the Free Software Foundation
** and appearing in the file LICENSE.LGPL included in the packaging
** of this file.
**
****************************************************************************/
#ifndef SCREENSHOTSERVICE_H
#define SCREENSHOTSERVICE_H

#include <QImage>
#include <QObject>
#include <QTimer>

class ScreenshotService : public QObject
{
    Q_OBJECT
public:
    explicit ScreenshotService(QObject *parent = 0);

    /* The screen now, as a screenshot (the chord of mce, KeyRouter): saved
     * under Pictures/Screenshots as wear_screenshot_<time>.png, cut to the
     * round screen on a round watch; captured() tells the overlay (the flash,
     * the preview, the thud) and the display is kept on for 3 s (mce). */
    Q_INVOKABLE void capture();

public slots:
    /* An explicit path saves the whole window there as ever (btsyncd); none
     * is the same as capture(). */
    void saveScreenshot(const QString &path);

signals:
    // the capture is on disk at `path` (a PNG)
    void captured(const QString &path);

private:
    QImage grabCompositor() const;
    void saveDefault(const QImage &grab);
    void holdDisplay();

    bool m_round;
    QTimer m_hold;
};

#endif // SCREENSHOTSERVICE_H
