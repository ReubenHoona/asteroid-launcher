
// This file is part of lipstick, a QML desktop library
//
// This library is free software; you can redistribute it and/or
// modify it under the terms of the GNU Lesser General Public
// License version 2.1 as published by the Free Software Foundation
// and appearing in the file LICENSE.LGPL included in the packaging
// of this file.
//
// This code is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Lesser General Public License for more details.
//
// Copyright (c) 2012, Robin Burchell <robin+nemo@viroteck.net>

#ifndef LIPSTICKSETTINGS_H
#define LIPSTICKSETTINGS_H

#include <QObject>
#include <QMetaType>

class ScreenLock;

class LipstickSettings : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool lockscreenVisible READ lockscreenVisible WRITE setLockscreenVisible NOTIFY lockscreenVisibleChanged)
    // eos: 0 no call, 1 a call ringing, 2 a call in progress (the call view sets it)
    Q_PROPERTY(int callState READ callState WRITE setCallState NOTIFY callStateChanged)

public:
    explicit LipstickSettings();
    static LipstickSettings *instance();

    void setScreenLock(ScreenLock *screenLock);
    bool lockscreenVisible() const;
    void setLockscreenVisible(bool lockscreenVisible);

    Q_INVOKABLE void lockScreen(bool immediate);

    int callState() const { return m_callState; }
    void setCallState(int state) { if (m_callState != state) { m_callState = state; emit callStateChanged(); } }

signals:
    void lockscreenVisibleChanged();
    void callStateChanged();

private:
    //! Logic for locking and unlocking the screen
    ScreenLock *screenLock;
    int m_callState = 0;
};

Q_DECLARE_METATYPE(LipstickSettings *)

#endif // LIPSTICKSETTINGS_H

