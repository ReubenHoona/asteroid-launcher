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
#include "lipstickcompositor.h"
#include "screenshotservice.h"
#include "eosscreenshot.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDateTime>
#include <QDebug>
#include <QGuiApplication>
#include <QImage>
#include <QScreen>
#include <QSettings>
#include <QStandardPaths>
#include <QTransform>
#include <private/qquickwindow_p.h>

// the display stays on for 3000 ms of a screenshot (stock WearScreenshotService)
static const int kDisplayHoldMs = 3000;

ScreenshotService::ScreenshotService(QObject *parent) :
    QObject(parent)
{
    // a round watch's screenshot is a circle (machine.conf, as DeviceSpecs.hasRoundScreen)
    QSettings machine(QStringLiteral("/etc/asteroid/machine.conf"), QSettings::IniFormat);
    m_round = machine.value(QStringLiteral("Display/ROUND"), false).toBool();

    m_hold.setSingleShot(true);
    m_hold.setInterval(kDisplayHoldMs);
    connect(&m_hold, &QTimer::timeout, this, [] {
        QDBusConnection::systemBus().asyncCall(QDBusMessage::createMethodCall(
            QStringLiteral("com.nokia.mce"), QStringLiteral("/com/nokia/mce/request"),
            QStringLiteral("com.nokia.mce.request"), QStringLiteral("req_display_cancel_blanking_pause")));
    });
}

QImage ScreenshotService::grabCompositor() const
{
    LipstickCompositor *compositor = LipstickCompositor::instance();
    if (!compositor)
        return QImage();
    QImage grab(compositor->quickWindow()->grabWindow());

    int rotation(QGuiApplication::primaryScreen()->angleBetween(Qt::PrimaryOrientation, compositor->topmostWindowOrientation()));
    if (rotation != 0) {
        QTransform xform;
        xform.rotate(rotation);
        grab = grab.transformed(xform, Qt::SmoothTransformation);
    }
    return grab;
}

// mce keeps the display on for 3 s: one pause, renewed by a capture within it
void ScreenshotService::holdDisplay()
{
    if (!m_hold.isActive())
        QDBusConnection::systemBus().asyncCall(QDBusMessage::createMethodCall(
            QStringLiteral("com.nokia.mce"), QStringLiteral("/com/nokia/mce/request"),
            QStringLiteral("com.nokia.mce.request"), QStringLiteral("req_display_blanking_pause")));
    m_hold.start();
}

void ScreenshotService::saveDefault(const QImage &grab)
{
    if (grab.isNull())
        return;
    const QImage shot = m_round ? EosShot::roundMask(grab) : grab;
    const QString pictures = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    const QString path = EosShot::savePath(pictures, QDateTime::currentDateTime());
    if (!shot.save(path, "PNG", 100)) {
        qWarning() << "ScreenshotService: cannot save" << path;
        return;
    }
    holdDisplay();
    emit captured(path);
}

void ScreenshotService::capture()
{
    saveDefault(grabCompositor());
}

void ScreenshotService::saveScreenshot(const QString &path)
{
    // an explicit path (btsyncd) is unchanged: the whole window, square, no feedback
    if (!path.isEmpty()) {
        const QImage grab = grabCompositor();
        if (!grab.isNull())
            grab.save(path, 0, 100);
        return;
    }
    capture();
}
