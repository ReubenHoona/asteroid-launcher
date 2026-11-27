/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

/*
 * The World clock's time zones (A-13, src/worldzones.h):
 *  - codes made from invented city names (one, two, three words, accents, hyphens);
 *  - regions of invented ids in real areas (America split by the country, Antarctica and Arctic left out, UTC);
 *  - offsets with summer time on the generic zones of the tz database (no place names): the change at
 *    the end of March and of October, fixed-offset Etc zones, invalid ids;
 *  - the image's own zone.tab (the library root's /usr/share/zoneinfo): every region has zones, every
 *    zone is valid and has a code, each region's list is sorted by its offset then by city, UTC is the
 *    universal region, a missing tab file gives UTC only; the file is read once.
 * Qt Core only (cmake -DLAUNCHER_TESTS=ON), run under qemu-aarch64 with the image libraries.
 */

#include "worldzones.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QFile>
#include <QTemporaryDir>
#include <QTimeZone>
#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)
#define CHECK_EQ(a, b) do { checks++; const qint64 x_ = (a), y_ = (b); if (x_ != y_) { fprintf(stderr, "FAIL %s:%d: %s == %s (got %lld want %lld)\n", __FILE__, __LINE__, #a, #b, (long long) x_, (long long) y_); failures++; } } while (0)
#define CHECK_STR(a, b) do { checks++; const QString x_ = (a), y_ = (b); if (x_ != y_) { fprintf(stderr, "FAIL %s:%d: %s == %s (got '%s' want '%s')\n", __FILE__, __LINE__, #a, #b, qPrintable(x_), qPrintable(y_)); failures++; } } while (0)

static double utcMs(int y, int mo, int d, int h, int mi)
{
    return double(QDateTime(QDate(y, mo, d), QTime(h, mi), QTimeZone::UTC).toMSecsSinceEpoch());
}

static void codes()
{
    CHECK_STR(WorldZones::codeOf(QStringLiteral("Testville")), QStringLiteral("TES"));
    CHECK_STR(WorldZones::codeOf(QStringLiteral("Nova Testa")), QStringLiteral("NTE"));
    CHECK_STR(WorldZones::codeOf(QStringLiteral("Port of Testing")), QStringLiteral("POT"));
    CHECK_STR(WorldZones::codeOf(QStringLiteral("Big Test Lake City")), QStringLiteral("BTL"));
    CHECK_STR(WorldZones::codeOf(QString::fromUtf8("São Testo")), QStringLiteral("STE"));
    CHECK_STR(WorldZones::codeOf(QStringLiteral("Test-au-Ville")), QStringLiteral("TAV"));
    CHECK_STR(WorldZones::codeOf(QStringLiteral("Ab")), QStringLiteral("AB"));
    CHECK_STR(WorldZones::codeOf(QStringLiteral("Xa B")), QStringLiteral("XAB"));
    CHECK_STR(WorldZones::codeOf(QStringLiteral("UTC")), QStringLiteral("UTC"));
    CHECK_STR(WorldZones::codeOf(QString()), QString());
    CHECK_STR(WorldZones::cityOf(QStringLiteral("Area/Sub/Test_Town")), QStringLiteral("Test Town"));
    CHECK_STR(WorldZones::cityOf(QStringLiteral("Etc/UTC")), QStringLiteral("UTC"));
    WorldZones z;
    CHECK_STR(z.code(QStringLiteral("Area/Nova_Testa")), QStringLiteral("NTE"));
    CHECK_STR(z.city(QStringLiteral("Area/Nova_Testa")), QStringLiteral("Nova Testa"));
}

static void regions()
{
    CHECK_STR(WorldZones::regionOf(QStringLiteral("America/Testa"), QStringLiteral("BR")), QStringLiteral("southamerica"));
    CHECK_STR(WorldZones::regionOf(QStringLiteral("America/Testa"), QStringLiteral("AR")), QStringLiteral("southamerica"));
    CHECK_STR(WorldZones::regionOf(QStringLiteral("America/Testb"), QStringLiteral("US")), QStringLiteral("northamerica"));
    CHECK_STR(WorldZones::regionOf(QStringLiteral("America/Testb"), QStringLiteral("CR")), QStringLiteral("northamerica"));
    CHECK_STR(WorldZones::regionOf(QStringLiteral("Europe/Testc"), QStringLiteral("XX")), QStringLiteral("europe"));
    CHECK_STR(WorldZones::regionOf(QStringLiteral("Pacific/Testd"), QStringLiteral("XX")), QStringLiteral("pacific"));
    CHECK_STR(WorldZones::regionOf(QStringLiteral("Indian/Teste"), QStringLiteral("XX")), QStringLiteral("indian"));
    CHECK_STR(WorldZones::regionOf(QStringLiteral("Antarctica/Testf"), QStringLiteral("AQ")), QString());
    CHECK_STR(WorldZones::regionOf(QStringLiteral("Arctic/Testg"), QStringLiteral("SJ")), QString());
    CHECK_STR(WorldZones::regionOf(QStringLiteral("Etc/UTC"), QString()), QStringLiteral("universal"));
    CHECK_EQ(WorldZones::regionKeys().size(), 10);
}

static void offsets()
{
    WorldZones z;
    // the generic zones of the tz database: CET (the European rule), EST5EDT (the North American rule)
    CHECK_EQ(z.offsetMinutes(QStringLiteral("CET"), utcMs(2026, 1, 15, 12, 0)), 60);
    CHECK_EQ(z.offsetMinutes(QStringLiteral("CET"), utcMs(2026, 7, 15, 12, 0)), 120);
    // the change: the last Sunday of March at 01:00 UTC, and back on the last Sunday of October
    CHECK_EQ(z.offsetMinutes(QStringLiteral("CET"), utcMs(2026, 3, 29, 0, 59)), 60);
    CHECK_EQ(z.offsetMinutes(QStringLiteral("CET"), utcMs(2026, 3, 29, 1, 0)), 120);
    CHECK_EQ(z.offsetMinutes(QStringLiteral("CET"), utcMs(2026, 10, 25, 0, 59)), 120);
    CHECK_EQ(z.offsetMinutes(QStringLiteral("CET"), utcMs(2026, 10, 25, 1, 0)), 60);
    CHECK_EQ(z.offsetMinutes(QStringLiteral("EST5EDT"), utcMs(2026, 1, 15, 12, 0)), -300);
    CHECK_EQ(z.offsetMinutes(QStringLiteral("EST5EDT"), utcMs(2026, 7, 15, 12, 0)), -240);
    // fixed offsets (the Etc sign is the POSIX one: Etc/GMT-3 is UTC+3)
    CHECK_EQ(z.offsetMinutes(QStringLiteral("Etc/GMT-3"), utcMs(2026, 7, 15, 12, 0)), 180);
    CHECK_EQ(z.offsetMinutes(QStringLiteral("Etc/GMT+10"), utcMs(2026, 1, 15, 12, 0)), -600);
    CHECK_EQ(z.offsetMinutes(QStringLiteral("Etc/UTC"), utcMs(2026, 7, 15, 12, 0)), 0);
    // not zones
    CHECK_EQ(z.offsetMinutes(QStringLiteral("Nowhere/Nothing"), utcMs(2026, 1, 1, 0, 0)), WorldZones::NoZone);
    CHECK_EQ(z.offsetMinutes(QString(), utcMs(2026, 1, 1, 0, 0)), WorldZones::NoZone);
    CHECK_EQ(z.offsetMinutes(QStringLiteral("+0530"), utcMs(2026, 1, 1, 0, 0)), WorldZones::NoZone);
    CHECK(z.isZone(QStringLiteral("CET")));
    CHECK(!z.isZone(QStringLiteral("Nowhere/Nothing")));
}

static void imageTab()
{
    WorldZones z;
    CHECK(QFile::exists(z.tabFile()));
    const double at = utcMs(2026, 7, 15, 12, 0);
    const QStringList r = z.regions();
    // every region of stock's chooser that the tz database has (stock: 9; here also the Indian Ocean)
    CHECK_EQ(r.size(), 10);
    CHECK(r.contains(QStringLiteral("universal")));
    CHECK(r.contains(QStringLiteral("northamerica")) && r.contains(QStringLiteral("southamerica")));
    int total = 0, bad = 0, unsorted = 0, nocode = 0;
    for (const QString &k : r) {
        const QVariantList zs = z.zones(k, at);
        CHECK(!zs.isEmpty());
        total += zs.size();
        for (int i = 0; i < zs.size(); i++) {
            const QVariantMap m = zs.at(i).toMap();
            const QString id = m.value(QStringLiteral("id")).toString();
            if (z.offsetMinutes(id, at) != m.value(QStringLiteral("offset")).toInt() || z.regionOfZone(id) != k)
                bad++;
            if (m.value(QStringLiteral("code")).toString().size() < 2)
                nocode++;
            if (id.startsWith(QLatin1String("Antarctica/")) || id.startsWith(QLatin1String("Arctic/")))
                bad++;
            if (i > 0) {
                const QVariantMap p = zs.at(i - 1).toMap();
                const int a = p.value(QStringLiteral("offset")).toInt(), b = m.value(QStringLiteral("offset")).toInt();
                if (a > b || (a == b && p.value(QStringLiteral("city")).toString() > m.value(QStringLiteral("city")).toString()))
                    unsorted++;
            }
        }
    }
    CHECK(total > 300);
    CHECK_EQ(bad, 0);
    CHECK_EQ(unsorted, 0);
    CHECK_EQ(nocode, 0);
    const QVariantList u = z.zones(QStringLiteral("universal"), at);
    CHECK_EQ(u.size(), 1);
    CHECK_STR(u.value(0).toMap().value(QStringLiteral("id")).toString(), QStringLiteral("Etc/UTC"));
    CHECK_STR(u.value(0).toMap().value(QStringLiteral("code")).toString(), QStringLiteral("UTC"));
    // the list follows the moment: the summer offsets in July, the winter ones in January (a European zone)
    QString eu;
    for (const QVariant &v : z.zones(QStringLiteral("europe"), at))
        if (v.toMap().value(QStringLiteral("offset")).toInt() == 120) {
            eu = v.toMap().value(QStringLiteral("id")).toString();
            break;
        }
    CHECK(!eu.isEmpty());
    CHECK_EQ(z.offsetMinutes(eu, utcMs(2026, 1, 15, 12, 0)) < 120, 1);

    // a tab file of invented lines: zones the tz database does not have are left out; only UTC stays
    QTemporaryDir dir;
    const QString tab = dir.path() + QStringLiteral("/zone.tab");
    QFile f(tab);
    CHECK(f.open(QIODevice::WriteOnly));
    f.write("# a comment\nXX\t+0000+00000\tEurope/Testville\nYY\t-0000-00000\tAmerica/Nova_Testa\tcomment\nbad line\n");
    f.close();
    WorldZones t;
    t.setTabFile(tab);
    CHECK_EQ(t.regions().size(), 1);
    CHECK_STR(t.regions().value(0), QStringLiteral("universal"));
    // a missing file: UTC only
    WorldZones m;
    m.setTabFile(dir.path() + QStringLiteral("/none.tab"));
    CHECK_EQ(m.regions().size(), 1);
    CHECK_EQ(m.zones(QStringLiteral("europe"), at).size(), 0);
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    codes();
    regions();
    offsets();
    imageTab();
    printf("tst_worldzones: %d checks, %d failures\n", checks, failures);
    return failures ? 1 : 0;
}
