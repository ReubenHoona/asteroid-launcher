/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSHUBDIGITS_H
#define EOSHUBDIGITS_H

#include <QChar>
#include <QDateTime>
#include <QString>
#include <QTime>

/*
 * The digits the sensor hub's glyph atlases draw (locale-formats-10).
 * Stock Wear OS sends the offload service's LocaleConfig (the locale's digits
 * as UTF-32) so the hub draws locale digits. Here the rule is one for the face,
 * its time texts and the hub: the hub draws the digits the face's own time
 * texts show, ASCII or the locale's, and the atlas is rendered from that digit
 * set. A face whose time text is in neither is not offloaded (the AP draws it),
 * a reason logged, never a silent fallback. Only a contiguous digit set in the
 * basic plane is supported (every decimal digit set of the Unicode locales
 * but the few in the supplementary planes, which stay ASCII).
 * Also when a layout's background expires (validUntil). Plain Qt Core, host
 * tested by tests/tst_hubdigits.cpp.
 */
namespace EosHub {

// The locale's zero digit as QLocale::zeroDigit() gives it (a one-character
// string; a surrogate pair or an empty string is not supported: ASCII)
inline QChar zeroOfLocale(const QString &zeroDigit)
{
    if (zeroDigit.size() != 1 || zeroDigit.at(0).isSurrogate())
        return QLatin1Char('0');
    // the whole set must stay in one run of ten
    return zeroDigit.at(0);
}

// ASCII digits written in the digit set that starts at `zero`
inline QString localized(const QString &ascii, QChar zero)
{
    if (zero == QLatin1Char('0'))
        return ascii;
    QString out;
    out.reserve(ascii.size());
    for (QChar c : ascii)
        out += (c >= QLatin1Char('0') && c <= QLatin1Char('9')) ? QChar(zero.unicode() + (c.unicode() - '0')) : c;
    return out;
}

// Which digit set the face's hour and minute texts are written in: ASCII
// ('0'), the locale's, or a null QChar when they are what the hub would not
// draw (another number, a mix of the sets)
inline QChar digitSet(const QString &hourShown, const QString &hourAscii, const QString &minuteShown,
                      const QString &minuteAscii, QChar localeZero)
{
    if (hourShown == hourAscii && minuteShown == minuteAscii)
        return QLatin1Char('0');
    if (localeZero != QLatin1Char('0') && hourShown == localized(hourAscii, localeZero)
        && minuteShown == localized(minuteAscii, localeZero))
        return localeZero;
    return QChar();
}


// When the background (date, AM/PM, items placed after the hour) changes.
// dated: the background shows the date or AM/PM; an overlay (Ambient Lite,
// the media layout) has neither, so only a moving hour limits it: an invalid
// QDateTime means it never expires (lipstick then arms no AP wakeup for it).
inline QDateTime validUntil(const QDateTime &now, bool use12h, bool hourWidthMoves, bool dated)
{
    QDateTime until;
    if (dated) {
        until = QDateTime(now.date().addDays(1), QTime(0, 0));
        const QDateTime noon(now.date(), QTime(12, 0));
        if (use12h && now < noon)
            until = noon;
    }
    if (use12h && hourWidthMoves) {
        // the hour goes 9 -> 10 and 12 -> 1 (the next day's 1:00 also, for an overlay)
        const QDateTime limit = until.isValid() ? until : QDateTime(now.date().addDays(1), QTime(1, 0));
        for (int h : { 1, 10, 13, 22 }) {
            const QDateTime t(now.date(), QTime(h, 0));
            if (t > now && t < limit && (!until.isValid() || t < until))
                until = t;
        }
        if (!until.isValid())
            until = limit;
    }
    return until;
}

} // namespace EosHub

#endif // EOSHUBDIGITS_H
