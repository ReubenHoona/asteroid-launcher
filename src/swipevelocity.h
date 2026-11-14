/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */
#ifndef SWIPEVELOCITY_H
#define SWIPEVELOCITY_H

/* The finger's speed in px/s for a swipe (W2-launcher-trays), plain C++ so
 * it is unit tested (tests/tst_swipevelocity.cpp). GestureFilterArea feeds
 * it every position of the followed touch point with the event's own
 * timestamp (ms) and reads it when the finger lifts.
 *
 * As Android's VelocityTracker (what the stock tray's fling decision reads,
 * computeCurrentVelocity(1000)): only the newest samples count, at most the
 * last 100 ms (HORIZON_MS), and the walk back from the newest sample ends
 * at a gap of more than 40 ms between two samples (ASSUME_POINTER_STOPPED_TIME:
 * a finger that rested and then lifted has no speed). The speed is the slope
 * of the least squares line through the positions of the window. Fewer than
 * two samples, or a window with no time in it, is 0.
 *
 * Android's strategy is a quadratic fit (LSQ2) or an impulse sum; the line
 * is the same for a steady swipe and within a few percent for a swipe that
 * speeds up or slows down over 100 ms, which the 1000 px/s fling threshold
 * of the trays does not resolve. */
class SwipeVelocity
{
public:
    static const long long HORIZON_MS = 100;
    static const long long STOPPED_MS = 40;
    static const int MAX_SAMPLES = 24;

    void reset() { m_count = 0; }

    /* a position at time t (ms); a second sample with the same time
     * replaces the first (the same event seen by more than one filter) */
    void add(long long t, double x, double y)
    {
        if (m_count > 0 && m_t[m_count - 1] == t) {
            m_x[m_count - 1] = x;
            m_y[m_count - 1] = y;
            return;
        }
        if (m_count == MAX_SAMPLES) {
            for (int i = 1; i < MAX_SAMPLES; ++i) {
                m_t[i - 1] = m_t[i]; m_x[i - 1] = m_x[i]; m_y[i - 1] = m_y[i];
            }
            --m_count;
        }
        m_t[m_count] = t; m_x[m_count] = x; m_y[m_count] = y;
        ++m_count;
    }

    int count() const { return m_count; }
    long long lastTime() const { return m_count ? m_t[m_count - 1] : 0; }

    double vx() const { return slope(m_x); }
    double vy() const { return slope(m_y); }

private:
    /* index of the oldest sample of the window */
    int windowStart() const
    {
        int first = m_count - 1;
        const long long newest = m_t[m_count - 1];
        while (first > 0) {
            if (newest - m_t[first - 1] > HORIZON_MS)
                break;
            if (m_t[first] - m_t[first - 1] > STOPPED_MS)
                break;
            --first;
        }
        return first;
    }

    double slope(const double *p) const
    {
        if (m_count < 2)
            return 0;
        const int first = windowStart();
        const int n = m_count - first;
        if (n < 2)
            return 0;
        /* times in seconds from the first sample of the window */
        double st = 0, sp = 0, stt = 0, stp = 0;
        for (int i = first; i < m_count; ++i) {
            const double t = (m_t[i] - m_t[first]) / 1000.0;
            st += t; sp += p[i]; stt += t * t; stp += t * p[i];
        }
        const double den = n * stt - st * st;
        if (den <= 0)
            return 0;
        return (n * stp - st * sp) / den;
    }

    long long m_t[MAX_SAMPLES];
    double m_x[MAX_SAMPLES];
    double m_y[MAX_SAMPLES];
    int m_count = 0;
};

#endif // SWIPEVELOCITY_H
