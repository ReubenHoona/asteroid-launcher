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

/* sensorlogd writes a record, then maybe another right after: read once
 * things are quiet */
static const int DEBOUNCE_MS = 2000;

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

HealthLog::Result HealthLog::read(const QString &path, const QString &sensor, int buckets, QDate day)
{
    Result r;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return r;
    const bool cumulative = sensor == QLatin1String("stepCounter");
    const qint64 dayStart = QDateTime(day, QTime(0, 0)).toSecsSinceEpoch();
    const qint64 bucketSecs = qMax<qint64>(1, 86400 / buckets);
    QVector<qint64> sum(buckets, 0);
    QVector<int> count(buckets, 0);
    QVector<int> top(buckets, -1);
    qint64 lastEpoch = -1;
    const QList<QByteArray> lines = file.readAll().split('\n');
    for (const QByteArray &line : lines) {
        const int colon = line.indexOf(':');
        if (colon <= 0)
            continue;
        bool ok1 = false, ok2 = false;
        const qint64 epoch = line.left(colon).trimmed().toLongLong(&ok1);
        const int value = line.mid(colon + 1).trimmed().toInt(&ok2);
        if (!ok1 || !ok2 || value < 0)
            continue;
        if (!cumulative && value == 0)
            continue;   /* no reading (off the wrist) */
        const int b = int(qBound(qint64(0), (epoch - dayStart) / bucketSecs, qint64(buckets - 1)));
        sum[b] += value;
        count[b]++;
        top[b] = qMax(top[b], value);
        if (epoch >= lastEpoch) {
            lastEpoch = epoch;
            r.last = value;
        }
        if (!r.ok) {
            r.min = r.max = value;
            r.ok = true;
        } else {
            r.min = qMin(r.min, value);
            r.max = qMax(r.max, value);
        }
    }
    if (!r.ok)
        return r;
    r.lastTime = QDateTime::fromSecsSinceEpoch(lastEpoch);
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
    if (lastTime == m_lastTime && r.last == m_lastValue && r.values == m_values)
        return;   /* nothing new: nothing on screen changes */
    m_lastValue = r.ok ? r.last : 0;
    m_lastTime = r.ok ? r.lastTime : QDateTime();
    m_min = r.min;
    m_max = r.max;
    m_values = r.values;
    emit changed();
}
