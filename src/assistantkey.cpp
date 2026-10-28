/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "assistantkey.h"

#include <QDBusConnection>
#include <QDebug>

static const char MCE_SIGNAL_PATH[] = "/com/nokia/mce/signal";
static const char MCE_SIGNAL_IF[] = "com.nokia.mce.signal";
static const char MCE_POWER_BUTTON_TRIGGER[] = "power_button_trigger";
static const char SIDE_KEY_LONG[] = "side-key-long";
static const char SIDE_KEY[] = "side-key";

AssistantKey::AssistantKey(QObject *parent) : QObject(parent)
{
    /* any sender: mce broadcasts it */
    mAvailable = QDBusConnection::systemBus().connect(QString(), QLatin1String(MCE_SIGNAL_PATH),
                                                      QLatin1String(MCE_SIGNAL_IF),
                                                      QLatin1String(MCE_POWER_BUTTON_TRIGGER),
                                                      this, SLOT(onTrigger(QString)));
    if (!mAvailable)
        qWarning() << "AssistantKey: cannot listen to mce for the side button";
    // the launcher's own session bus name is lipstick's
    QDBusConnection::sessionBus().registerObject(QStringLiteral("/org/asteroidos/launcher/assistant"), this,
                                                 QDBusConnection::ExportScriptableSlots);
}

void AssistantKey::onTrigger(const QString &action)
{
    if (action == QLatin1String(SIDE_KEY_LONG)) {
        qInfo() << "AssistantKey: side button held";
        emit longPressed();
    } else if (action == QLatin1String(SIDE_KEY)) {
        emit pressed();
    }
}

void AssistantKey::Open()
{
    emit openRequested(QString());
}

void AssistantKey::Ask(const QString &text)
{
    emit openRequested(text);
}
