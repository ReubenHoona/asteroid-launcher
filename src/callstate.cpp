/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "callstate.h"

#include <MDConfItem>

#include <QDebug>

CallStateService::CallStateService(QObject *parent, const QDBusConnection &bus, const QString &activeKey) :
    QObject(parent)
{
    if (!activeKey.isEmpty()) {
        mActive = new MDConfItem(activeKey, this);
        // no call at start: whatever an earlier launcher left behind
        mActive->set(false);
    }
    QDBusConnection b = bus;
    if (!b.registerObject(QLatin1String(Path), this,
                          QDBusConnection::ExportScriptableSlots | QDBusConnection::ExportScriptableSignals))
        qWarning() << "CallStateService: cannot register" << Path;
}

void CallStateService::setState(int state)
{
    if (state < 0 || state > 2)
        state = 0;
    if (state == mState)
        return;
    const bool wasActive = mState > 0;
    mState = state;
    if (mActive && wasActive != (mState > 0))
        mActive->set(mState > 0);
    emit changed();
    emit CallStateChanged(mState);
}
