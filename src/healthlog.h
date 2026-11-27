/*
 * Copyright (C) 2026 eos
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

#include <functional>

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
 *
 * windowMinutes > 0 (heartrateMonitor only; W3-launcher-tiles-content-b, the
 * Daily heart rate tile): the readings of the last windowMinutes up to the
 * moment of the read instead of today, in `buckets` equal parts (stock:
 * 2 h in 3 minute means, aapt.java:27-32). values = the mean of each part
 * (0: none), lows / highs its lowest and highest reading, minValue /
 * maxValue the lowest and highest of the means (stock labels the chart with
 * those), lastValue / lastTime the latest reading in the window, resting =
 * -1. windowStart / windowEnd are the ends of the window (the caption). The
 * window is as old as the last read: nothing runs to slide it, the tile
 * reads again when it comes on screen and when the log changes. The window
 * may reach into yesterday's file.
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
    Q_PROPERTY(int windowMinutes READ windowMinutes WRITE setWindowMinutes NOTIFY windowMinutesChanged)
    Q_PROPERTY(QDateTime windowStart READ windowStart NOTIFY changed)
    Q_PROPERTY(QDateTime windowEnd READ windowEnd NOTIFY changed)

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
    int windowMinutes() const { return m_windowMinutes; }
    void setWindowMinutes(int minutes);
    QDateTime windowStart() const { return m_windowStart; }
    QDateTime windowEnd() const { return m_windowEnd; }

    Q_INVOKABLE void reload();

    /* Whether a timer of its own is armed (the 2 s debounce or the one for
     * just after midnight): never while inactive (tests) */
    bool timersArmed() const { return m_debounce.isActive() || m_midnight.isActive(); }

    /* The directory of a sensor's logs */
    static QString sensorDir(const QString &sensor);

    /* The wall clock the day and the window are read from (tests set a
     * fixed one; default QDateTime::currentDateTime) */
    void setClock(std::function<QDateTime()> clock) { m_clock = std::move(clock); }

    /* The resting heart rate of readings (x: epoch, y: bpm), as
     * asteroid-health's HealthStats.js restingRate(): the lowest average
     * held for 30 minutes over at least 3 readings; -1 if none */
    static int restingRate(QList<QPointF> points);

    /* The window summary of the log files `paths` (older first) as a map for
     * the host test: ok, last, lastTime (epoch), min, max, values, lows,
     * highs, start, end (epochs). */
    static QVariantMap summarizeWindow(const QStringList &paths, qint64 endEpoch, int minutes, int buckets);

signals:
    void sensorChanged();
    void bucketsChanged();
    void windowMinutesChanged();
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
        QDateTime windowStart;
        QDateTime windowEnd;
    };
    static Result read(const QString &path, const QString &sensor, int buckets, QDate day);
    static Result readWindow(const QStringList &paths, qint64 endEpoch, int minutes, int buckets);
    void apply(const Result &r, quint64 generation);
    void watch();
    QDateTime clockNow() const { return m_clock ? m_clock() : QDateTime::currentDateTime(); }

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
    int m_windowMinutes = 0;
    QDateTime m_windowStart;
    QDateTime m_windowEnd;
    QDate m_day;
    quint64 m_generation = 0;
    QFileSystemWatcher *m_watcher = nullptr;
    QTimer m_debounce;
    QTimer m_midnight;
    std::function<QDateTime()> m_clock;
};

#endif // HEALTHLOG_H
