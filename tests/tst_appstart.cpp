/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The app start trace (lipstick/src/utilities/eosappstart.h): on with
 * EOS_APPSTART_TRACE in the environment (read at the first use), one info
 * line "<stage> <what> mono=<s>.<us>" in the category eos.appstart, stamped
 * with CLOCK_MONOTONIC between the times before and after the call; off by
 * default (no rule, no variable: nothing is logged and enabled() is false);
 * on again with the rule eos.appstart.info=true. Qt Core only.
 */
#include "eosappstart.h"

#include <QByteArray>
#include <QList>
#include <QString>
#include <QStringList>
#include <cstdio>
#include <time.h>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

struct Line {
    QtMsgType type;
    QByteArray category;
    QString message;
};
static QList<Line> lines;

static void handler(QtMsgType type, const QMessageLogContext &context, const QString &message)
{
    lines.append({ type, QByteArray(context.category ? context.category : ""), message });
}

static qint64 monoUs()
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return qint64(ts.tv_sec) * 1000000 + ts.tv_nsec / 1000;
}

// the stamp of "... mono=<s>.<us>" in µs, -1 when there is none
static qint64 stampOf(const QString &message)
{
    const int at = message.lastIndexOf(QStringLiteral(" mono="));
    if (at < 0)
        return -1;
    const QStringList parts = message.mid(at + 6).split(QLatin1Char('.'));
    if (parts.size() != 2 || parts[1].size() != 6)
        return -1;
    bool ok1 = false, ok2 = false;
    const qint64 s = parts[0].toLongLong(&ok1);
    const qint64 us = parts[1].toLongLong(&ok2);
    return ok1 && ok2 ? s * 1000000 + us : -1;
}

int main()
{
    qputenv("EOS_APPSTART_TRACE", "1");
    qInstallMessageHandler(handler);

    // on from the environment
    CHECK(EosAppStart::enabled());
    const qint64 before = monoUs();
    EosAppStart::trace("launch", QStringLiteral("asteroid-settings.desktop"));
    const qint64 after = monoUs();
    CHECK(lines.size() == 1);
    if (lines.size() == 1) {
        CHECK(lines[0].type == QtInfoMsg);
        CHECK(lines[0].category == "eos.appstart");
        CHECK(lines[0].message.startsWith(QStringLiteral("launch asteroid-settings.desktop mono=")));
        const qint64 t = stampOf(lines[0].message);
        CHECK(t >= before && t <= after);
    }

    // no "what": the stage and the stamp
    lines.clear();
    EosAppStart::trace("frame swapped");
    CHECK(lines.size() == 1 && lines[0].message.startsWith(QStringLiteral("frame swapped mono=")) && stampOf(lines[0].message) > 0);

    // the category's default without the variable (the rules applied again): off, nothing logged
    QLoggingCategory::setFilterRules(QString());
    lines.clear();
    CHECK(!EosAppStart::enabled());
    EosAppStart::trace("launch", QStringLiteral("x"));
    CHECK(lines.isEmpty());

    // the logging rule turns it on
    QLoggingCategory::setFilterRules(QStringLiteral("eos.appstart.info=true"));
    CHECK(EosAppStart::enabled());
    EosAppStart::trace("surface mapped", QStringLiteral("window 3 pid 1234"));
    CHECK(lines.size() == 1 && lines[0].message.startsWith(QStringLiteral("surface mapped window 3 pid 1234 mono=")));

    // and off
    QLoggingCategory::setFilterRules(QStringLiteral("eos.appstart.info=false"));
    lines.clear();
    CHECK(!EosAppStart::enabled());
    EosAppStart::trace("launch", QStringLiteral("x"));
    CHECK(lines.isEmpty());

    qInstallMessageHandler(nullptr);
    printf("tst_appstart: %d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}
