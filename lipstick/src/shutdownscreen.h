/***************************************************************************
**
** Copyright (C) 2010 Nokia Corporation and/or its subsidiary(-ies).
** Copyright (C) 2012 Jolla Ltd.
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
#ifndef SHUTDOWNSCREEN_H
#define SHUTDOWNSCREEN_H

#include <QObject>
#include <QVariantMap>
#include <QDBusUnixFileDescriptor>

class ShutdownScreen : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool windowVisible READ windowVisible WRITE setWindowVisible NOTIFY windowVisibleChanged)
    //! The shutdown is a restart ("Restarting..." and not "Bye")
    Q_PROPERTY(bool restart READ restart NOTIFY restartChanged)

public:
    explicit ShutdownScreen(QObject *parent = 0);

    //! Returns whether the shutdown screen overlay should be shown.
    bool windowVisible() const;

    //! Sets whether the shutdown screen overlay should be shown.
    void setWindowVisible(bool visible);

    //! Whether the system comes back up (logind's type: reboot, kexec, soft-reboot)
    bool restart() const { return m_restart; }

signals:
    //! Sent when the visibility of the overlay has changed.
    void windowVisibleChanged();

    //! Sent when the kind of the shutdown is known
    void restartChanged();

private slots:
    //! systemd-logind is about to shut the system down: show the shutdown screen
    void handlePrepareForShutdown(bool start);

    //! logind 257: the same, with the type of the shutdown in the metadata
    void handlePrepareForShutdownWithMetadata(bool start, const QVariantMap &metadata);

private:
    //! Show the shutdown screen overlay
    void showShutdownScreen();

    //! Take a logind delay inhibitor so the screen can be drawn before poweroff
    void takeShutdownInhibitor();

    //! Release the logind delay inhibitor, letting the shutdown proceed
    void releaseShutdownInhibitor();

    //! Whether the shutdown screen overlay should be shown
    bool m_visible = false;

    //! Whether it is a restart
    bool m_restart = false;

    //! Delay inhibitor lock held on org.freedesktop.login1 (empty = none)
    QDBusUnixFileDescriptor m_inhibitFd;

#ifdef UNIT_TEST
    friend class Ut_ShutdownScreen;
#endif
};

#endif // SHUTDOWNSCREEN_H
