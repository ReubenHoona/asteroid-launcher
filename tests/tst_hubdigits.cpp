/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

// The digits the hub's atlases draw and when a layout expires (src/eoshubdigits.h)

#include "eoshubdigits.h"

#include <QDate>
#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static QDateTime at(int d, int h, int m = 0) { return QDateTime(QDate(2026, 11, d), QTime(h, m)); }

int main()
{
    using namespace EosHub;
    const QChar ascii = QLatin1Char('0');
    const QChar arabicIndic(0x0660);
    const QChar devanagari(0x0966);

    // ---- the locale's zero ----
    CHECK(zeroOfLocale(QStringLiteral("0")) == ascii);
    CHECK(zeroOfLocale(QString(arabicIndic)) == arabicIndic);
    CHECK(zeroOfLocale(QString()) == ascii);
    CHECK(zeroOfLocale(QString::fromUcs4(U"\U0001D7CE")) == ascii);   // supplementary plane: ASCII

    // ---- the digits written in a set ----
    CHECK(localized(QStringLiteral("0123456789"), ascii) == QStringLiteral("0123456789"));
    CHECK(localized(QStringLiteral("09:45"), arabicIndic) == QString(QChar(0x0660)) + QChar(0x0669) + QLatin1Char(':')
                                                              + QChar(0x0664) + QChar(0x0665));
    CHECK(localized(QStringLiteral("7"), devanagari) == QString(QChar(0x096D)));
    CHECK(localized(QString(), arabicIndic).isEmpty());

    // ---- which set the face's texts are in ----
    CHECK(digitSet("09", "09", "41", "41", ascii) == ascii);
    CHECK(digitSet("09", "09", "41", "41", arabicIndic) == ascii);             // ASCII text in an Arabic locale: ASCII atlas
    CHECK(digitSet(localized("09", arabicIndic), "09", localized("41", arabicIndic), "41", arabicIndic) == arabicIndic);
    CHECK(digitSet(localized("9", devanagari), "9", localized("05", devanagari), "05", devanagari) == devanagari);
    // a mix of the sets, another number, or locale digits in an ASCII locale: not drawn by the hub
    CHECK(digitSet(localized("09", arabicIndic), "09", "41", "41", arabicIndic).isNull());
    CHECK(digitSet("10", "09", "41", "41", ascii).isNull());
    CHECK(digitSet(localized("09", arabicIndic), "09", localized("41", arabicIndic), "41", ascii).isNull());

    // ---- when the background expires ----
    // a face (date in the background): the next midnight; 12 h also the next noon
    CHECK(validUntil(at(14, 9, 30), false, false, true) == at(15, 0));
    CHECK(validUntil(at(14, 9, 30), true, false, true) == at(14, 12));
    CHECK(validUntil(at(14, 13, 5), true, false, true) == at(15, 0));
    // 12 h with the hour moving other items: the next change of the digit count
    CHECK(validUntil(at(14, 9, 30), true, true, true) == at(14, 10));
    CHECK(validUntil(at(14, 11, 30), true, true, true) == at(14, 12));
    CHECK(validUntil(at(14, 12, 30), true, true, true) == at(14, 13));
    CHECK(validUntil(at(14, 13, 30), true, true, true) == at(14, 22));
    CHECK(validUntil(at(14, 23, 30), true, true, true) == at(15, 0));
    CHECK(validUntil(at(14, 0, 30), true, true, true) == at(14, 1));
    // an overlay (Ambient Lite, the media layout) has no date: it never expires in 24 h,
    // and in 12 h only a moving hour limits it (no AP wake at midnight or noon)
    CHECK(!validUntil(at(14, 9, 30), false, false, false).isValid());
    CHECK(!validUntil(at(14, 9, 30), false, true, false).isValid());
    CHECK(!validUntil(at(14, 9, 30), true, false, false).isValid());
    CHECK(validUntil(at(14, 9, 30), true, true, false) == at(14, 10));
    CHECK(validUntil(at(14, 12, 59), true, true, false) == at(14, 13));
    CHECK(validUntil(at(14, 13, 0), true, true, false) == at(14, 22));
    CHECK(validUntil(at(14, 22, 0), true, true, false) == at(15, 1));
    CHECK(validUntil(at(14, 23, 59), true, true, false) == at(15, 1));
    CHECK(validUntil(at(14, 0, 0), true, true, false) == at(14, 1));

    printf("tst_hubdigits: %d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}
