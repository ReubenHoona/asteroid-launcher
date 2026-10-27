/*
 * FirstRun (src/firstrun.cpp): the first-run wizard's helpers: the display kept on during it, the
 * time zone nearest to a GPS position (tzdata's zone1970.tab), the local date and time in a zone,
 * and the GPS satellite count read from the GeoClue hybris provider.
 *
 * The real class with an in-memory MDConfItem (tests/stubs) and fakes of mce and the GeoClue
 * provider on a private bus. The time-zone checks hold no place names or coordinates: they take
 * every zone of the system's own table and expect its reference position to give that zone back
 * (or a zone at the same position), including the zones nearest the antimeridian approached from
 * the other side.
 */

#include <QDBusArgument>
#include <QDBusMetaType>
#include <QFile>
#include <QRegularExpression>
#include <QSignalSpy>
#include <QTimeZone>
#include <QtTest>

#include <MDConfItem>

#include "fakeservice.h"
#include "firstrun.h"
#include "mce.h"

#include <cmath>

namespace {

struct Satellite
{
    int prn = 0;
    int elevation = 0;
    int azimuth = 0;
    int snr = 0;
};

QDBusArgument &operator<<(QDBusArgument &arg, const Satellite &s)
{
    arg.beginStructure();
    arg << s.prn << s.elevation << s.azimuth << s.snr;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, Satellite &s)
{
    arg.beginStructure();
    arg >> s.prn >> s.elevation >> s.azimuth >> s.snr;
    arg.endStructure();
    return arg;
}

struct Zone
{
    QString name;
    double latitude;
    double longitude;
};

// The test's own reading of ISO 6709 (+DDMM[SS] / +DDDMM[SS]), independent of the unit's
double iso6709(const QString &v, int degreeDigits)
{
    const double sign = v.startsWith(QLatin1Char('-')) ? -1 : 1;
    const double deg = v.mid(1, degreeDigits).toDouble();
    const double min = v.mid(1 + degreeDigits, 2).toDouble();
    const double sec = v.size() > 3 + degreeDigits ? v.mid(3 + degreeDigits, 2).toDouble() : 0;
    return sign * (deg + min / 60 + sec / 3600);
}

QList<Zone> zoneTable()
{
    QList<Zone> zones;
    QFile file(QStringLiteral("/usr/share/zoneinfo/zone1970.tab"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return zones;
    static const QRegularExpression coords(QStringLiteral("^([+-]\\d{4,6})([+-]\\d{5,7})$"));
    while (!file.atEnd()) {
        const QString line = QString::fromUtf8(file.readLine()).trimmed();
        if (line.startsWith(QLatin1Char('#')) || line.isEmpty())
            continue;
        const QStringList f = line.split(QLatin1Char('\t'));
        const QRegularExpressionMatch m = coords.match(f.value(1));
        if (f.size() < 3 || !m.hasMatch())
            continue;
        zones << Zone { f.at(2), iso6709(m.captured(1), 2), iso6709(m.captured(2), 3) };
    }
    return zones;
}

QString geoclueIntrospection()
{
    return QStringLiteral(
        "<interface name=\"org.freedesktop.Geoclue.Satellite\">"
        "<method name=\"GetSatellite\"><arg type=\"i\" direction=\"out\"/><arg type=\"i\" direction=\"out\"/>"
        "<arg type=\"i\" direction=\"out\"/><arg type=\"ai\" direction=\"out\"/><arg type=\"a(iiii)\" direction=\"out\"/>"
        "</method></interface>");
}

}

Q_DECLARE_METATYPE(Satellite)

class TestFirstRun : public QObject
{
    Q_OBJECT

private:
    FakeServiceHost *host = nullptr;
    FakeService *mce = nullptr;
    FakeObject *mceObj = nullptr;
    FakeService *geoclue = nullptr;
    FakeObject *geoclueObj = nullptr;

private slots:
    void initTestCase()
    {
        qDBusRegisterMetaType<Satellite>();
        qDBusRegisterMetaType<QList<Satellite>>();
        QVERIFY(TestBus::start());
        host = new FakeServiceHost;
        mce = new FakeService(*host, QStringLiteral("com.nokia.mce"), QStringLiteral("fake-mce"));
        mceObj = new FakeObject(mceIntrospection());
        mce->add(QStringLiteral("/com/nokia/mce/request"), mceObj);
        QVERIFY(mce->registerName());
        geoclue = new FakeService(*host, QStringLiteral("org.freedesktop.Geoclue.Providers.Hybris"),
                                  QStringLiteral("fake-geoclue"));
        geoclueObj = new FakeObject(geoclueIntrospection());
        geoclue->add(QStringLiteral("/org/freedesktop/Geoclue/Providers/Hybris"), geoclueObj);
        QVERIFY(geoclue->registerName());
    }

    void cleanupTestCase()
    {
        delete geoclue;
        delete mce;
        delete host;
        TestBus::stop();
    }

    void init()
    {
        mceObj->clear();
        geoclueObj->clear();
    }

    void firstRunKeepsDisplayOnUntilDone()
    {
        MDConfItem(QStringLiteral("/org/asteroidos/launcher/firstRunDone")).unset();
        FirstRun firstRun;
        QVERIFY(firstRun.isFirstRun());

        firstRun.startFirstRun();
        QTRY_COMPARE(mceRequests(mceObj), QStringList({
            QStringLiteral("set_config /system/osso/dsm/display/inhibit_blank_mode 3"),
            QStringLiteral("req_tklock_mode_change unlocked"),
            QStringLiteral("set_config /system/osso/dsm/locks/tklock_blank_disable 1") }));

        mceObj->clear();
        firstRun.stopFirstRun();
        QTRY_COMPARE(mceRequests(mceObj), QStringList({
            QStringLiteral("set_config /system/osso/dsm/display/inhibit_blank_mode 0"),
            QStringLiteral("req_tklock_mode_change locked"),
            QStringLiteral("set_config /system/osso/dsm/locks/tklock_blank_disable 0") }));
        QVERIFY(!firstRun.isFirstRun());
        QVERIFY(!FirstRun().isFirstRun()); // stored
    }

    void timezoneOfEveryReferencePosition()
    {
        const QList<Zone> zones = zoneTable();
        QVERIFY2(zones.size() > 100, "tzdata's zone1970.tab is needed");
        FirstRun firstRun;
        int checked = 0;
        for (const Zone &zone : zones) {
            const QString found = firstRun.timezoneForPosition(zone.latitude, zone.longitude);
            if (found != zone.name) {
                // another zone at the very same reference position comes first in the table
                bool samePosition = false;
                for (const Zone &other : zones) {
                    if (other.name == found && std::abs(other.latitude - zone.latitude) < 1e-9
                            && std::abs(other.longitude - zone.longitude) < 1e-9)
                        samePosition = true;
                }
                QVERIFY2(samePosition, qPrintable(QStringLiteral("zone %1 of %2").arg(checked).arg(zones.size())));
            }
            ++checked;
        }
        QCOMPARE(checked, zones.size());
    }

    // seconds in the coordinates: the position a few arc seconds off the reference still finds it
    void timezoneNearReferencePositions()
    {
        const QList<Zone> zones = zoneTable();
        FirstRun firstRun;
        int checked = 0;
        for (const Zone &zone : zones) {
            // the nearest other zone must be farther than the offset for the check to be meaningful
            double nearestOther = 1e9;
            for (const Zone &other : zones) {
                if (other.name != zone.name)
                    nearestOther = std::min(nearestOther, std::hypot(other.latitude - zone.latitude,
                                                                     other.longitude - zone.longitude));
            }
            if (nearestOther < 0.5 || std::abs(zone.latitude) > 80)
                continue;
            QCOMPARE(firstRun.timezoneForPosition(zone.latitude + 0.01, zone.longitude - 0.01), zone.name);
            ++checked;
        }
        QVERIFY(checked > 100);
    }

    // the great-circle distance wraps at +-180 degrees: the easternmost and westernmost zones' own
    // positions written past the antimeridian (longitude -+ 360) still find them
    void timezoneAcrossTheAntimeridian()
    {
        const QList<Zone> zones = zoneTable();
        FirstRun firstRun;
        Zone east { QString(), 0, -1000 };
        Zone west { QString(), 0, 1000 };
        for (const Zone &z : zones) {
            if (z.longitude > east.longitude)
                east = z;
            if (z.longitude < west.longitude)
                west = z;
        }
        QVERIFY(!east.name.isEmpty() && !west.name.isEmpty());
        QVERIFY(east.longitude > 170 && west.longitude < -170);
        QCOMPARE(firstRun.timezoneForPosition(east.latitude, east.longitude - 360), east.name);
        QCOMPARE(firstRun.timezoneForPosition(west.latitude, west.longitude + 360), west.name);
    }

    void localDateTimeInZones()
    {
        FirstRun firstRun;
        QCOMPARE(firstRun.localDateTime(QStringLiteral("UTC"), 0),
                 QVariantMap({ { QStringLiteral("year"), 1970 }, { QStringLiteral("month"), 1 },
                               { QStringLiteral("day"), 1 }, { QStringLiteral("hour"), 0 },
                               { QStringLiteral("minute"), 0 } }));
        QVERIFY(firstRun.localDateTime(QStringLiteral("Not/AZone"), 0).isEmpty());

        // every zone of the table, a summer and a winter instant: its own UTC offset applied
        const qint64 instants[] = { 1767225600 /* 2026-01-01 00:00 UTC */, 1782864000 /* 2026-07-01 */ };
        int checked = 0;
        for (const Zone &zone : zoneTable()) {
            const QTimeZone tz(zone.name.toUtf8());
            if (!tz.isValid())
                continue;
            for (qint64 t : instants) {
                const QDateTime utc = QDateTime::fromSecsSinceEpoch(t, QTimeZone::UTC);
                const QDateTime expected = utc.addSecs(tz.offsetFromUtc(utc));
                const QVariantMap local = firstRun.localDateTime(zone.name, t);
                QCOMPARE(local.value(QStringLiteral("year")).toInt(), expected.date().year());
                QCOMPARE(local.value(QStringLiteral("month")).toInt(), expected.date().month());
                QCOMPARE(local.value(QStringLiteral("day")).toInt(), expected.date().day());
                QCOMPARE(local.value(QStringLiteral("hour")).toInt(), expected.time().hour());
                QCOMPARE(local.value(QStringLiteral("minute")).toInt(), expected.time().minute());
            }
            ++checked;
        }
        QVERIFY(checked > 100);
    }

    void countsSatellitesHeard()
    {
        geoclueObj->respond(QStringLiteral("GetSatellite"), [](const QDBusMessage &call) {
            const QList<Satellite> sats { { 3, 40, 120, 31 }, { 7, 10, 200, 0 }, { 12, 60, 80, 18 }, { 19, 5, 300, 0 },
                                          { 24, 30, 10, 22 } };
            return call.createReply(QVariantList { 1000, 2, 5, QVariant::fromValue(QList<int> { 3, 12 }),
                                                   QVariant::fromValue(sats) });
        });
        FirstRun firstRun;
        QSignalSpy spy(&firstRun, &FirstRun::gpsSatellitesChanged);
        firstRun.requestGpsSatellites();
        QTRY_COMPARE(spy.count(), 1);
        QCOMPARE(spy.first(), QVariantList({ 2, 3 })); // used 2, heard (snr > 0) 3
        const RecordedCall call = geoclueObj->callsTo(QStringLiteral("GetSatellite")).value(0);
        QCOMPARE(call.interface, QStringLiteral("org.freedesktop.Geoclue.Satellite"));
    }

    void noSatellitesWithoutAnAnswer_data()
    {
        QTest::addColumn<int>("kind");
        QTest::newRow("error") << 0;
        QTest::newRow("too few values") << 1;
    }

    void noSatellitesWithoutAnAnswer()
    {
        QFETCH(int, kind);
        geoclueObj->respond(QStringLiteral("GetSatellite"), [kind](const QDBusMessage &call) {
            if (kind == 0)
                return call.createErrorReply(QStringLiteral("org.freedesktop.Geoclue.Error.NotAvailable"), QStringLiteral("off"));
            return call.createReply(QVariantList { 1000, 2 });
        });
        FirstRun firstRun;
        QSignalSpy spy(&firstRun, &FirstRun::gpsSatellitesChanged);
        firstRun.requestGpsSatellites();
        QTRY_COMPARE(geoclueObj->callsTo(QStringLiteral("GetSatellite")).size(), 1);
        QTest::qWait(100);
        QCOMPARE(spy.count(), 0);
    }
};

QTEST_GUILESS_MAIN(TestFirstRun)
#include "tst_firstrun.moc"
