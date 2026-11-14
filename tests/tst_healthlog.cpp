/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

/*
 * The window mode of HealthLog (src/healthlog.h, W3-launcher-tiles-content-b, gap tiles-individual-20): the
 * Daily heart rate tile's last 2 hours in 40 means of 3 minutes (stock aapt.java:27-32). The static summary on
 * two files (the window reaches into yesterday), then the object on a private home directory: it reads the
 * window, arms no timer in window mode, and today's mode is as it was. Core only (cmake -DLAUNCHER_TESTS=ON).
 */

#include "healthlog.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QTemporaryDir>
#include <QTimer>
#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)
#define CHECK_EQ(a, b) do { checks++; const qint64 x_ = (a), y_ = (b); if (x_ != y_) { fprintf(stderr, "FAIL %s:%d: %s == %s (got %lld want %lld)\n", __FILE__, __LINE__, #a, #b, (long long) x_, (long long) y_); failures++; } } while (0)

static void write(const QString &path, const QStringList &lines)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return;
    f.write(lines.join(QLatin1Char('\n')).toUtf8());
    f.write("\n");
}

static void summaryTests(const QString &dir)
{
    const qint64 end = 1800000000;            /* a fixed time */
    const qint64 start = end - 7200;
    /* 3 minutes = 180 s per bucket: bucket b covers start + 180 b .. start + 180 (b + 1) */
    const QString old = dir + "/old.log";
    const QString cur = dir + "/cur.log";
    write(old, { QString("%1:90").arg(start - 10),            /* before the window: ignored */
                 QString("%1:60").arg(start + 5),             /* bucket 0 */
                 QString("%1:70").arg(start + 100) });        /* bucket 0 */
    write(cur, { QString("%1:100").arg(start + 180),          /* bucket 1: exactly on the edge */
                 QString("%1:0").arg(start + 200),            /* off the wrist: ignored */
                 QString("%1:251").arg(start + 210),          /* impossible: ignored */
                 QString("%1:24").arg(start + 215),           /* impossible: ignored */
                 "garbage",
                 QString("%1:130").arg(start + 7000),         /* bucket 38 */
                 QString("%1:140").arg(start + 7010),         /* bucket 38 */
                 QString("%1:120").arg(end),                  /* the end itself: the last bucket, the latest reading */
                 QString("%1:80").arg(end + 1) });            /* after the end: ignored */
    const QVariantMap m = HealthLog::summarizeWindow({ old, cur }, end, 120, 40);
    CHECK(m["ok"].toBool());
    CHECK_EQ(m["start"].toLongLong(), start);
    CHECK_EQ(m["end"].toLongLong(), end);
    const QVariantList v = m["values"].toList();
    CHECK_EQ(v.size(), 40);
    CHECK_EQ(v[0].toInt(), 65);                               /* mean of 60 and 70 */
    CHECK_EQ(v[1].toInt(), 100);
    CHECK_EQ(v[2].toInt(), 0);                                /* an empty part is 0 */
    CHECK_EQ(v[38].toInt(), 135);
    CHECK_EQ(v[39].toInt(), 120);
    CHECK_EQ(m["lows"].toList()[0].toInt(), 60);
    CHECK_EQ(m["highs"].toList()[0].toInt(), 70);
    CHECK_EQ(m["lows"].toList()[38].toInt(), 130);
    CHECK_EQ(m["highs"].toList()[38].toInt(), 140);
    CHECK_EQ(m["min"].toInt(), 65);                           /* lowest and highest of the means */
    CHECK_EQ(m["max"].toInt(), 135);
    CHECK_EQ(m["last"].toInt(), 120);
    CHECK_EQ(m["lastTime"].toLongLong(), end);

    /* nothing in the window: not ok, the window still there for the caption */
    const QVariantMap e = HealthLog::summarizeWindow({ old }, end + 100000, 120, 40);
    CHECK(!e["ok"].toBool());
    CHECK_EQ(e["end"].toLongLong(), end + 100000);
    CHECK_EQ(e["lastTime"].toLongLong(), -1);
    /* a missing file is as no readings */
    CHECK(!HealthLog::summarizeWindow({ dir + "/none.log" }, end, 120, 40)["ok"].toBool());
    /* 3 minute parts need 40 of them in 2 hours; another count is as asked */
    CHECK_EQ(HealthLog::summarizeWindow({ old, cur }, end, 120, 8)["values"].toList().size(), 8);
    /* one reading: min = max = last */
    write(dir + "/one.log", { QString("%1:77").arg(end - 50) });
    const QVariantMap o = HealthLog::summarizeWindow({ dir + "/one.log" }, end, 120, 40);
    CHECK_EQ(o["min"].toInt(), 77);
    CHECK_EQ(o["max"].toInt(), 77);
    CHECK_EQ(o["values"].toList()[39].toInt(), 77);
    /* the means are rounded as the app rounds: 60.5 -> 61 */
    write(dir + "/round.log", { QString("%1:60").arg(end - 7000), QString("%1:61").arg(end - 6990) });
    CHECK_EQ(HealthLog::summarizeWindow({ dir + "/round.log" }, end, 120, 40)["values"].toList()[1].toInt(), 61);
}

static bool waitChanged(HealthLog &log, int ms)
{
    bool got = false;
    QObject::connect(&log, &HealthLog::changed, [&got]() { got = true; });
    QElapsedTimer t;
    t.start();
    while (!got && t.elapsed() < ms)
        QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
    return got;
}

static void objectTests(const QString &home)
{
    const QDateTime now = QDateTime::currentDateTime();
    if (now.time().msecsSinceStartOfDay() < (3 * 3600 + 120) * 1000) {
        /* the readings below are placed up to 3 hours back inside today's file */
        puts("object tests skipped: less than 3 hours after midnight");
        return;
    }
    const QString dir = home + "/.asteroid-sensorlogd/heartrateMonitor/";
    const qint64 t = now.toSecsSinceEpoch();
    QStringList lines;
    /* a reading 10 minutes ago, one 50 minutes ago, one 3 hours ago (outside the window) */
    lines << QString("%1:72").arg(t - 600) << QString("%1:95").arg(t - 3000) << QString("%1:50").arg(t - 3 * 3600);
    write(dir + now.date().toString("yyyy-MM-dd") + ".log", lines);

    HealthLog log;
    log.setSensor("heartrateMonitor");
    log.setBuckets(40);
    log.setWindowMinutes(120);
    CHECK_EQ(log.windowMinutes(), 120);
    CHECK(!log.timersArmed());                                /* inactive: nothing armed */
    log.setActive(true);
    CHECK(waitChanged(log, 5000));
    CHECK(log.hasData());
    CHECK_EQ(log.lastValue(), 72);
    CHECK_EQ(log.minValue(), 72);
    CHECK_EQ(log.maxValue(), 95);
    CHECK_EQ(log.values().size(), 40);
    CHECK_EQ(log.restingValue(), -1);
    CHECK(log.windowStart().isValid() && log.windowEnd().isValid());
    CHECK_EQ(log.windowStart().secsTo(log.windowEnd()), 7200);
    CHECK(qAbs(log.windowEnd().toSecsSinceEpoch() - QDateTime::currentSecsSinceEpoch()) < 10);
    /* no timer of its own in window mode (the midnight one is today's mode) */
    CHECK(!log.timersArmed());
    log.setActive(false);
    CHECK(!log.timersArmed());

    /* the day's mode again: today's readings, the 3 hour old one counts, the midnight timer is armed */
    log.setWindowMinutes(0);
    log.setBuckets(24);
    log.setActive(true);
    CHECK(waitChanged(log, 5000));
    CHECK_EQ(log.minValue(), 50);
    CHECK_EQ(log.maxValue(), 95);
    CHECK(log.timersArmed());
    log.setActive(false);
}

int main(int argc, char **argv)
{
    QTemporaryDir tmp;
    CHECK(tmp.isValid());
    /* HealthLog finds the logs under the home directory (sensorlogd's default) */
    qputenv("HOME", tmp.path().toUtf8());
    qputenv("XDG_CONFIG_HOME", (tmp.path() + "/cfg").toUtf8());
    QCoreApplication app(argc, argv);
    summaryTests(tmp.path());
    objectTests(tmp.path());
    printf("%d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}
