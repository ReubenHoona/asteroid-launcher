/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

// eos-lockd: the screen lock's credential store as a root helper (see lockhelper.h).
//   EOS_LOCK_FILE   the file (default /var/lib/eos-lock/lock.json)
//   EOS_LOCKD_BUS   "session": the session bus (tests); default the system bus
//   EOS_LOCKD_NAME  the bus name (tests)

#include "lockhelper.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    const QByteArray file = qgetenv("EOS_LOCK_FILE");
    const QString path = file.isEmpty() ? QStringLiteral("/var/lib/eos-lock/lock.json") : QString::fromLocal8Bit(file);
    // the directory is the helper's alone
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile::setPermissions(QFileInfo(path).absolutePath(), QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
    const bool session = qgetenv("EOS_LOCKD_BUS") == "session";
    const QByteArray name = qgetenv("EOS_LOCKD_NAME");
    LockHelper helper(path, session ? QDBusConnection::sessionBus() : QDBusConnection::systemBus(),
                      name.isEmpty() ? QStringLiteral("org.asteroidos.LockHelper") : QString::fromLatin1(name));
    if (!helper.registered())
        return 1;
    QObject::connect(&helper, &LockHelper::idle, &app, &QCoreApplication::quit);
    return app.exec();
}
