/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef HEALTHLOG_H
#define HEALTHLOG_H

#include <QDate>
#include <QDateTime>
#include <QFileSystemWatcher>
#include <QObject>
#include <QPointF>
#include <QTimer>
#include <QVariantList>

/*
 * Today's records of one asteroid-sensorlogd sensor, for the tiles: the
 * latest value and when it was taken, and the day in buckets for a small
 * graph. sensorlogd writes one "epoch:value" line per record to
 * <loggerRootPath>/<sensor>/<yyyy-MM-dd>.log (default ~/.asteroid-sensorlogd).
 *
 * The file is read in a worker thread when the item becomes active, when
 * sensorlogd writes to it (2 s after the last write) and when the day
 * changes; nothing is read or watched while it is inactive. The results come
 * back on the user interface thread in one "changed" signal.
 *
 *   heartrateMonitor: value = bpm; buckets = the average of each bucket,
 *                     lows/highs = its lowest and highest reading; resting
 *                     = today's resting heart rate. As asteroid-health's
 *                     HealthStats.js (heartRateDay), so the tile and the app
 *                     agree: the readings of today (local midnight to
 *                     midnight) between 25 and 250 bpm (0 is off the wrist)
 *   stepCounter:      value = steps so far today (the log is cumulative);
 *                     buckets = the steps taken in each bucket
 */
class HealthLog : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString sensor READ sensor WRITE setSensor NOTIFY sensorChanged)
    Q_PROPERTY(int buckets READ buckets WRITE setBuckets NOTIFY bucketsChanged)
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(bool hasData READ hasData NOTIFY changed)
    Q_PROPERTY(int lastValue READ lastValue NOTIFY changed)
    Q_PROPERTY(QDateTime lastTime READ lastTime NOTIFY changed)
    Q_PROPERTY(int minValue READ minValue NOTIFY changed)
    Q_PROPERTY(int maxValue READ maxValue NOTIFY changed)
    Q_PROPERTY(QVariantList values READ values NOTIFY changed)
    Q_PROPERTY(QVariantList lows READ lows NOTIFY changed)
    Q_PROPERTY(QVariantList highs READ highs NOTIFY changed)
    Q_PROPERTY(int restingValue READ restingValue NOTIFY changed)

public:
    explicit HealthLog(QObject *parent = nullptr);

    QString sensor() const { return m_sensor; }
    void setSensor(const QString &sensor);
    int buckets() const { return m_buckets; }
    void setBuckets(int buckets);
    bool active() const { return m_active; }
    void setActive(bool active);

    bool hasData() const { return m_lastTime.isValid(); }
    int lastValue() const { return m_lastValue; }
    QDateTime lastTime() const { return m_lastTime; }
    int minValue() const { return m_min; }
    int maxValue() const { return m_max; }
    QVariantList values() const { return m_values; }
    QVariantList lows() const { return m_lows; }
    QVariantList highs() const { return m_highs; }
    int restingValue() const { return m_resting; }

    Q_INVOKABLE void reload();

    /* The directory of a sensor's logs */
    static QString sensorDir(const QString &sensor);

    /* The resting heart rate of readings (x: epoch, y: bpm), as
     * asteroid-health's HealthStats.js restingRate(): the lowest average
     * held for 30 minutes over at least 3 readings; -1 if none */
    static int restingRate(QList<QPointF> points);

signals:
    void sensorChanged();
    void bucketsChanged();
    void activeChanged();
    void changed();

private:
    struct Result {
        bool ok = false;
        int last = 0;
        QDateTime lastTime;
        int min = 0;
        int max = 0;
        QVariantList values;
        QVariantList lows;
        QVariantList highs;
        int resting = -1;
    };
    static Result read(const QString &path, const QString &sensor, int buckets, QDate day);
    void apply(const Result &r, quint64 generation);
    void watch();

    QString m_sensor;
    int m_buckets = 24;
    bool m_active = false;
    int m_lastValue = 0;
    QDateTime m_lastTime;
    int m_min = 0;
    int m_max = 0;
    QVariantList m_values;
    QVariantList m_lows;
    QVariantList m_highs;
    int m_resting = -1;
    QDate m_day;
    quint64 m_generation = 0;
    QFileSystemWatcher *m_watcher = nullptr;
    QTimer m_debounce;
    QTimer m_midnight;
};

#endif // HEALTHLOG_H
