/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef TOUCHOBSERVER_H
#define TOUCHOBSERVER_H

#include "eostouch.h"

#include <QElapsedTimer>
#include <QObject>
#include <QPointF>
#include <QTimer>

/*
 * Sees every touch of the launcher's windows without taking any
 * (W3-launcher-a11y-security: gaps accessibility-lock-security-15 and -21):
 * an application event filter, like qml-asteroid's RotaryInput, that feeds
 * EosTouch::TapSequence and tells QML about the sequences the accessibility
 * features asked for. Context property `touchObserver`.
 *
 *   tripleTap       true: a one-finger triple tap emits multiTap(1, 3, x, y) at
 *                   the third finger up (the magnification; the gap between taps is
 *                   300 ms + 25, config_screen_magnification_multi_tap_adjustment)
 *   twoFingerTaps   true: two fingers tapping once or twice emit multiTap(2, 1 or 2,
 *                   x, y) 300 ms after the last tap (the vibration watch)
 * With both false the filter is not installed: no event reaches this class
 * and no timer exists. The only timer is one single shot, armed while a
 * sequence is open (a few hundred ms after a tap), never polling.
 * x and y are scene (window) coordinates. `density` is Theme's px per dp.
 */
class TouchObserver : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool tripleTap READ tripleTap WRITE setTripleTap NOTIFY wantedChanged)
    Q_PROPERTY(bool twoFingerTaps READ twoFingerTaps WRITE setTwoFingerTaps NOTIFY wantedChanged)
    Q_PROPERTY(double density READ density WRITE setDensity NOTIFY wantedChanged)

public:
    explicit TouchObserver(QObject *parent = nullptr);

    bool tripleTap() const { return m_triple; }
    bool twoFingerTaps() const { return m_two; }
    double density() const { return m_density; }
    void setTripleTap(bool on);
    void setTwoFingerTaps(bool on);
    void setDensity(double dp);

    // for the tests: the same as a touch event's points, timestamps in ms
    void feed(int type, int id, const QPointF &p, qint64 t);
    enum Phase { Down, Move, Up, Cancel };

signals:
    void wantedChanged();
    // `fingers` fingers tapped `taps` times, at (x, y)
    void multiTap(int fingers, int taps, double x, double y);

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private slots:
    void timeout();

private:
    void update();
    void armTimer(qint64 now);
    void sequenceStep(qint64 now);

    bool m_triple = false;
    bool m_two = false;
    bool m_installed = false;
    double m_density = 1.0;
    EosTouch::TapSequence m_seq;
    QTimer m_timer;
    QElapsedTimer m_clock;
};

#endif // TOUCHOBSERVER_H
