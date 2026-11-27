/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSAPPSTART_H
#define EOSAPPSTART_H

#include <QLoggingCategory>
#include <QString>

#include <time.h>

/*
 * The app start trace, for measuring a launch stage by stage: with
 * EOS_APPSTART_TRACE set in the launcher's environment (or the logging rule
 * eos.appstart.info=true), one journal line per stage,
 *
 *   eos.appstart: <stage> <what> mono=<s>.<us>
 *
 * stamped with CLOCK_MONOTONIC when the stage is reached: the clock of
 * journalctl -o short-monotonic, of the kernel's trace events and of the
 * invoker's and the booster's own "eos-appstart:" lines (mapplauncherd
 * 0006), which the variable turns on too, since the invoker gets the
 * launcher's environment. The stages are in LauncherItem, AppWatcher,
 * LipstickCompositor and, through LipstickCompositor::appStartTrace,
 * WindowTransitions.qml. Off (the default), a trace point is one test of
 * the category.
 */
namespace EosAppStart {

inline QLoggingCategory &category()
{
    static QLoggingCategory c("eos.appstart", QtWarningMsg);
    static const bool fromEnvironment = [] {
        if (qEnvironmentVariableIsSet("EOS_APPSTART_TRACE"))
            c.setEnabled(QtInfoMsg, true);
        return true;
    }();
    Q_UNUSED(fromEnvironment)
    return c;
}

inline bool enabled()
{
    return category().isInfoEnabled();
}

// Any thread
inline void trace(const char *stage, const QString &what = QString())
{
    QLoggingCategory &c = category();
    if (!c.isInfoEnabled())
        return;
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    if (what.isEmpty())
        qCInfo(c, "%s mono=%ld.%06ld", stage, long(ts.tv_sec), long(ts.tv_nsec / 1000));
    else
        qCInfo(c, "%s %s mono=%ld.%06ld", stage, qUtf8Printable(what), long(ts.tv_sec), long(ts.tv_nsec / 1000));
}

} // namespace EosAppStart

#endif // EOSAPPSTART_H
