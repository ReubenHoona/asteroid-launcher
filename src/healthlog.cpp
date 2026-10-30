/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "healthlog.h"

#include <QDir>
#include <QFile>
#include <QPointer>
#include <QSettings>
#include <QStandardPaths>
#include <QThreadPool>

#include <algorithm>
#include <cmath>

/* sensorlogd writes a record, then maybe another right after: read once
 * things are quiet */
static const int DEBOUNCE_MS = 2000;

/* A logged heart rate outside these is no reading, and the resting heart
 * rate: the lowest average held this long over at least this many readings
 * (as asteroid-health's HealthStats.js) */
static const double HR_MIN_VALID = 25;
static const double HR_MAX_VALID = 250;
static const qint64 RESTING_WINDOW = 1800;
static const int RESTING_MIN_READINGS = 3;

HealthLog::HealthLog(QObject *parent) : QObject(parent)
{
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(DEBOUNCE_MS);
    connect(&m_debounce, &QTimer::timeout, this, &HealthLog::reload);
    m_midnight.setSingleShot(true);
    connect(&m_midnight, &QTimer::timeout, this, &HealthLog::reload);
}

QString HealthLog::sensorDir(const QString &sensor)
{
    /* the same setting and default as sensorlogd's common.cpp */
    QSettings settings(QStringLiteral("asteroid"), QStringLiteral("sensorlogd"));
    const QString root = settings.value(QStringLiteral("loggerRootPath"),
                                        QStandardPaths::writableLocation(QStandardPaths::HomeLocation)
                                        + QStringLiteral("/.asteroid-sensorlogd/")).toString();
    return root + sensor + QLatin1Char('/');
}

void HealthLog::setSensor(const QString &sensor)
{
    if (sensor == m_sensor)
        return;
    m_sensor = sensor;
    emit sensorChanged();
    watch();
    reload();
}

void HealthLog::setBuckets(int buckets)
{
    buckets = qBound(1, buckets, 288);
    if (buckets == m_buckets)
        return;
    m_buckets = buckets;
    emit bucketsChanged();
    reload();
}

void HealthLog::setActive(bool active)
{
    if (active == m_active)
        return;
    m_active = active;
    emit activeChanged();
    watch();
    if (active)
        reload();
    else
        m_debounce.stop();
}

void HealthLog::watch()
{
    delete m_watcher;
    m_watcher = nullptr;
    if (!m_active || m_sensor.isEmpty())
        return;
    m_watcher = new QFileSystemWatcher(this);
    const QString dir = sensorDir(m_sensor);
    if (QDir(dir).exists())
        m_watcher->addPath(dir);
    const QString today = dir + QDate::currentDate().toString(QStringLiteral("yyyy-MM-dd")) + QStringLiteral(".log");
    if (QFile::exists(today))
        m_watcher->addPath(today);
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, &m_debounce, qOverload<>(&QTimer::start));
    connect(m_watcher, &QFileSystemWatcher::fileChanged, &m_debounce, qOverload<>(&QTimer::start));
}

void HealthLog::reload()
{
    if (!m_active || m_sensor.isEmpty())
        return;
    const QDate day = QDate::currentDate();
    if (day != m_day) {
        m_day = day;
        watch();   /* the new day's file */
    }
    /* again just after midnight: the day's graph starts over */
    const QDateTime now = QDateTime::currentDateTime();
    m_midnight.start(int(qBound(qint64(1000), now.msecsTo(QDateTime(day.addDays(1), QTime(0, 0, 5))), qint64(86400000))));

    const QString path = sensorDir(m_sensor) + day.toString(QStringLiteral("yyyy-MM-dd")) + QStringLiteral(".log");
    const QString sensor = m_sensor;
    const int buckets = m_buckets;
    const quint64 generation = ++m_generation;
    QPointer<HealthLog> self(this);
    QThreadPool::globalInstance()->start([self, path, sensor, buckets, day, generation]() {
        const Result r = read(path, sensor, buckets, day);
        if (!self)
            return;
        QMetaObject::invokeMethod(self, [self, r, generation]() {
            if (self)
                self->apply(r, generation);
        }, Qt::QueuedConnection);
    });
}

int HealthLog::restingRate(QList<QPointF> points)
{
    std::stable_sort(points.begin(), points.end(),
                     [](const QPointF &a, const QPointF &b) { return a.x() < b.x(); });
    double best = INFINITY;
    double sum = 0;
    qsizetype j = 0;
    for (qsizetype i = 0; i < points.size(); i++) {
        if (j < i) {
            j = i;
            sum = 0;
        }
        while (j < points.size() && points[j].x() < points[i].x() + RESTING_WINDOW) {
            sum += points[j].y();
            j++;
        }
        const qsizetype count = j - i;
        if (count >= RESTING_MIN_READINGS)
            best = qMin(best, sum / count);
        sum -= points[i].y();
    }
    return std::isfinite(best) ? int(std::floor(best + 0.5)) : -1;
}

HealthLog::Result HealthLog::read(const QString &path, const QString &sensor, int buckets, QDate day)
{
    Result r;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return r;
    const bool cumulative = sensor == QLatin1String("stepCounter");
    /* a local day: 23 or 25 hours on a daylight saving change */
    const qint64 dayStart = QDateTime(day, QTime(0, 0)).toSecsSinceEpoch();
    const qint64 dayEnd = QDateTime(day.addDays(1), QTime(0, 0)).toSecsSinceEpoch();
    const qint64 daySecs = qMax<qint64>(1, dayEnd - dayStart);
    QVector<double> sum(buckets, 0);
    QVector<int> count(buckets, 0);
    QVector<int> top(buckets, -1);
    QVector<double> low(buckets, 0);
    QVector<double> high(buckets, 0);
    QList<QPointF> readings;
    double minValue = 0, maxValue = 0, lastValue = 0;
    qint64 lastEpoch = -1;
    const QList<QByteArray> lines = file.readAll().split('\n');
    for (const QByteArray &line : lines) {
        const int colon = line.indexOf(':');
        if (colon <= 0)
            continue;
        bool ok1 = false, ok2 = false;
        const qint64 epoch = line.left(colon).trimmed().toLongLong(&ok1);
        /* integers and decimals, as sensorlogd's readDayRecords() */
        const double value = line.mid(colon + 1).trimmed().toDouble(&ok2);
        if (!ok1 || !ok2 || !std::isfinite(value) || value < 0)
            continue;
        if (!cumulative) {
            if (value < HR_MIN_VALID || value > HR_MAX_VALID)
                continue;   /* no reading (0: off the wrist) */
            if (epoch < dayStart || epoch >= dayEnd)
                continue;   /* not today's */
            readings << QPointF(epoch, value);
        }
        /* the part of the day it falls in (records just past midnight, such
         * as a day's last step total, count in the last) */
        const int b = int(qBound(qint64(0), (epoch - dayStart) * buckets / daySecs, qint64(buckets - 1)));
        low[b] = count[b] > 0 ? qMin(low[b], value) : value;
        high[b] = count[b] > 0 ? qMax(high[b], value) : value;
        sum[b] += value;
        count[b]++;
        top[b] = qMax(top[b], int(value));
        if (epoch >= lastEpoch) {
            lastEpoch = epoch;
            lastValue = value;
        }
        if (!r.ok) {
            minValue = maxValue = value;
            r.ok = true;
        } else {
            minValue = qMin(minValue, value);
            maxValue = qMax(maxValue, value);
        }
    }
    if (!r.ok)
        return r;
    /* rounded as the app rounds (Math.round) */
    const auto round = [](double v) { return int(std::floor(v + 0.5)); };
    r.last = round(lastValue);
    r.min = round(minValue);
    r.max = round(maxValue);
    r.lastTime = QDateTime::fromSecsSinceEpoch(lastEpoch);
    if (!cumulative)
        r.resting = restingRate(readings);
    int previous = 0;
    for (int b = 0; b < buckets; b++) {
        if (cumulative) {
            /* steps taken in the bucket: its highest total minus the one
             * before it (the counter only goes up during the day) */
            const int now = top[b] >= 0 ? top[b] : previous;
            r.values << qMax(0, now - previous);
            previous = qMax(previous, now);
        } else {
            r.values << (count[b] > 0 ? int(sum[b] / count[b]) : 0);
            r.lows << (count[b] > 0 ? round(low[b]) : 0);
            r.highs << (count[b] > 0 ? round(high[b]) : 0);
        }
    }
    if (cumulative) {
        r.min = 0;
        r.max = 0;
        for (const QVariant &v : std::as_const(r.values))
            r.max = qMax(r.max, v.toInt());
    }
    return r;
}

void HealthLog::apply(const Result &r, quint64 generation)
{
    if (generation != m_generation)
        return;   /* a newer read is on its way */
    const QDateTime lastTime = r.ok ? r.lastTime : QDateTime();
    if (lastTime == m_lastTime && r.last == m_lastValue && r.values == m_values
            && r.lows == m_lows && r.highs == m_highs && r.resting == m_resting)
        return;   /* nothing new: nothing on screen changes */
    m_lastValue = r.ok ? r.last : 0;
    m_lastTime = r.ok ? r.lastTime : QDateTime();
    m_min = r.min;
    m_max = r.max;
    m_values = r.values;
    m_lows = r.lows;
    m_highs = r.highs;
    m_resting = r.ok ? r.resting : -1;
    emit changed();
}
