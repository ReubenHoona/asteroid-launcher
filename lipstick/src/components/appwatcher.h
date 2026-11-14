/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef APPWATCHER_H
#define APPWATCHER_H

#include <QObject>
#include <QSet>
#include <QString>
#include <QStringList>

#include "eosappcrash.h"

/*
 * The apps the launcher started, and how they ended (system-dialogs-misc-02):
 * every launch path (LauncherItem::launchApplication for the app list, the
 * tiles and the notifications' open actions, AppLauncher::launchApp for the
 * named programs) runs through launch(), which owns a QProcess per start in
 * place of QProcess::startDetached, whose exit status was lost. The process
 * object's finished signal is the only thing watched: no timer, no polling.
 *
 * A process that ended in a crash (EosCrash::isCrash: a signal of its own
 * bug, not an exit code, not a kill the launcher did itself) is counted by
 * program; appCrashed() tells each, and repeatedCrash() the second one
 * within 120 s of the first, once per 120 s, which is the "<app> keeps
 * stopping" dialog (compositor/AppErrors.qml). The child inherits the
 * launcher's output and input, so no pipe can fill and stall it; it is
 * parented to the watcher and deleted when it ends. Exposed to QML as the
 * context property `appWatcher`.
 */
class AppWatcher : public QObject
{
    Q_OBJECT

public:
    explicit AppWatcher(QObject *parent = nullptr);

    static AppWatcher *instance();

    /* Start `program` with `args`. `key` names it (the desktop file's name
     * without ".desktop", else the program's), `title` is what the dialog
     * calls it ("" to look it up when needed). True if the process started. */
    bool launch(const QString &program, const QStringList &args, const QString &key,
                const QString &title = QString());

    /* The launcher is about to end this process itself (an unresponsive app):
     * its death is no crash. */
    void noteDeliberate(qint64 pid);

    /* Open Settings at a route of its deep links ("app_storage", "app_info", ...): the request
     * key the launcher and Settings share (/org/asteroidos/settings/ui/open = "<route>@<ms>"),
     * then Settings is started or raised. */
    Q_INVOKABLE bool openSettings(const QString &route);

    /* The name of an app for a dialog: its desktop entry's name (localised),
     * "" if there is none. */
    Q_INVOKABLE QString titleFor(const QString &key) const;

    /* CLOCK_BOOTTIME in ms: what the tracker's times are */
    static qint64 bootTimeMs();

    /* The end of a process: the part of finished() that needs no QProcess, for
     * the tests. */
    void processEnded(const QString &key, const QString &title, qint64 pid, int code, bool crashExit,
                      qint64 nowMs);

signals:
    // a program crashed; repeating: its previous crash was less than 120 s ago
    void appCrashed(const QString &key, bool repeating);
    // show "<title> keeps stopping"
    void repeatedCrash(const QString &key, const QString &title);

private:
    EosCrash::CrashTracker mTracker;
    QSet<qint64> mDeliberate;
};

#endif // APPWATCHER_H
