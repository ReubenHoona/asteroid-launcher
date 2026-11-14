/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <time.h>

#include <QCoreApplication>
#include <QDebug>
#include <QFile>
#include <QProcess>
#include <MDConfItem>
#include <QDateTime>
#include <mdesktopentry.h>

#include "appwatcher.h"

static AppWatcher *s_instance = nullptr;

AppWatcher::AppWatcher(QObject *parent) : QObject(parent)
{
    if (!s_instance)
        s_instance = this;
}

AppWatcher *AppWatcher::instance()
{
    if (!s_instance)
        new AppWatcher(QCoreApplication::instance());
    return s_instance;
}

qint64 AppWatcher::bootTimeMs()
{
    struct timespec ts;
    if (clock_gettime(CLOCK_BOOTTIME, &ts) != 0)
        return 0;
    return qint64(ts.tv_sec) * 1000 + ts.tv_nsec / 1000000;
}

bool AppWatcher::launch(const QString &program, const QStringList &args, const QString &key,
                        const QString &title)
{
    QProcess *proc = new QProcess(this);
    proc->setProgram(program);
    proc->setArguments(args);
    // as startDetached did: nothing to read, no pipe to fill and stall the app, its own session
    proc->setStandardInputFile(QProcess::nullDevice());
    proc->setStandardOutputFile(QProcess::nullDevice());
    proc->setStandardErrorFile(QProcess::nullDevice());
    proc->setUnixProcessParameters(QProcess::UnixProcessFlag::CreateNewSession);

    // the pid is read below, once the process is up; the lambda reads it from the object it is
    // sent from (a finished process has none)
    proc->setProperty("eosPid", qint64(0));
    connect(proc, &QProcess::finished, this,
            [this, proc, key, title](int code, QProcess::ExitStatus status) {
        processEnded(key, title, proc->property("eosPid").toLongLong(), code,
                     status == QProcess::CrashExit, bootTimeMs());
        proc->deleteLater();
    });
    proc->start();
    if (!proc->waitForStarted(1000)) {
        qWarning() << "AppWatcher: cannot start" << program << proc->errorString();
        delete proc;
        return false;
    }
    proc->setProperty("eosPid", qint64(proc->processId()));
    return true;
}

void AppWatcher::noteDeliberate(qint64 pid)
{
    if (pid > 1)
        mDeliberate.insert(pid);
}

void AppWatcher::processEnded(const QString &key, const QString &title, qint64 pid, int code,
                              bool crashExit, qint64 nowMs)
{
    const bool deliberate = mDeliberate.remove(pid);
    if (!EosCrash::isCrash(crashExit, code, deliberate))
        return;
    const EosCrash::Verdict v = mTracker.record(key.toStdString(), nowMs);
    qWarning() << "AppWatcher:" << key << "crashed, signal" << code
               << (v.repeating ? "(repeating)" : "(first)");
    emit appCrashed(key, v.repeating);
    if (v.showDialog)
        emit repeatedCrash(key, title.isEmpty() ? titleFor(key) : title);
}

bool AppWatcher::openSettings(const QString &route)
{
    if (route.isEmpty())
        return false;
    MDConfItem request(QStringLiteral("/org/asteroidos/settings/ui/open"));
    request.set(route + QLatin1Char('@') + QString::number(QDateTime::currentMSecsSinceEpoch()));
    return launch(QStringLiteral("asteroid-settings"), QStringList(), QStringLiteral("asteroid-settings"));
}

QString AppWatcher::titleFor(const QString &key) const
{
    if (key.isEmpty())
        return QString();
    const QString dir = qEnvironmentVariable("EOS_APPLICATIONS_DIR", QStringLiteral("/usr/share/applications"));
    const QString path = dir + QLatin1Char('/') + key + QStringLiteral(".desktop");
    if (!QFile::exists(path))
        return QString();
    MDesktopEntry entry(path);
    return entry.isValid() ? entry.name() : QString();
}
