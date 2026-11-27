/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * R5 C-04: the nearest catalogue for a region the image has none for (lipstick/src/eoscatalogues.h), on a folder of
 * invented catalogue names: the phone's de-AT reads the de_DE catalogue, Portuguese of a region without its own the
 * main region's, a language with a catalogue of its own or without any gets none from here. Qt Core only.
 */

#include "eoscatalogues.h"

#include <QCoreApplication>
#include <QFile>
#include <QTemporaryDir>
#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)
#define CHECK_STR(a, b) do { checks++; const QString x_ = (a), y_ = (b); if (x_ != y_) { fprintf(stderr, "FAIL %s:%d: %s == %s (got '%s' want '%s')\n", __FILE__, __LINE__, #a, #b, qPrintable(x_), qPrintable(y_)); failures++; } } while (0)

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QTemporaryDir dir;
    CHECK(dir.isValid());
    const QStringList files = { QStringLiteral("tst-app.en.qm"), QStringLiteral("tst-app.en_GB.qm"),
                                QStringLiteral("tst-app.de_CH.qm"), QStringLiteral("tst-app.de_DE.qm"),
                                QStringLiteral("tst-app.fr.qm"), QStringLiteral("tst-app.pt_BR.qm"),
                                QStringLiteral("tst-app.pt_PT.qm"), QStringLiteral("tst-app.nl_BE.qm"),
                                QStringLiteral("tst-app.nl_NL.qm"), QStringLiteral("other.sv_FI.qm") };
    for (const QString &f : files) {
        QFile q(dir.filePath(f));
        CHECK(q.open(QIODevice::WriteOnly));
    }
    const QString name = QStringLiteral("tst-app");
    auto nearest = [&](const char *locale) {
        return EosCatalogues::nearest(name, dir.path(), QLocale(QString::fromLatin1(locale)));
    };

    // a region without a catalogue: the language's main region first
    CHECK_STR(nearest("de_AT"), dir.filePath(QStringLiteral("tst-app.de_DE.qm")));
    CHECK_STR(nearest("de_LU"), dir.filePath(QStringLiteral("tst-app.de_DE.qm")));
    CHECK_STR(nearest("pt_AO"), dir.filePath(QStringLiteral("tst-app.") + QLocale(QStringLiteral("pt")).name()
                                             + QStringLiteral(".qm")));
    CHECK_STR(nearest("nl_SR"), dir.filePath(QStringLiteral("tst-app.nl_NL.qm")));
    // only regions that are not the main one: the first by name
    CHECK_STR(EosCatalogues::nearest(QStringLiteral("other"), dir.path(), QLocale(QStringLiteral("sv_SE"))),
              dir.filePath(QStringLiteral("other.sv_FI.qm")));

    // a language-only catalogue is QTranslator's own find (fr_CA -> fr), not this one's
    CHECK_STR(nearest("fr_CA"), QString());
    // a language the image has no catalogue for: none (the text stays English)
    CHECK_STR(nearest("sw_KE"), QString());
    CHECK_STR(nearest("C"), QString());
    CHECK_STR(EosCatalogues::nearest(name, dir.filePath(QStringLiteral("missing")), QLocale(QStringLiteral("de_AT"))),
              QString());

    printf("tst_catalogues: %d checks, %d failures\n", checks, failures);
    return failures ? 1 : 0;
}
