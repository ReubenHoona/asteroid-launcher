/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

// The credential store and the lock service (src/eoslock.h, src/lockservice.*):
//   dbus-run-session -- ./tst_lock

#include "lockhelper.h"
#include "lockservice.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusConnectionInterface>
#include <QDBusReply>
#include <QEventLoop>
#include <QProcess>
#include <QTimer>
#include <QTemporaryDir>
#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

using namespace EosLock;

static qint64 now = 1000000000000LL;
static qint64 clk() { return now; }

static void spin(int ms)
{
    QEventLoop loop;
    QTimer::singleShot(ms, &loop, &QEventLoop::quit);
    loop.exec();
}

static bool waitForService(const QString &name, bool registered)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    for (int i = 0; i < 100; ++i) {
        if (bus.interface()->isServiceRegistered(name) == registered)
            return true;
        spin(50);
    }
    return false;
}

int main(int argc, char **argv)
{
    // the helper (eos-lockd) as a second process of this test: tst_lock --helper FILE
    if (argc > 2 && QByteArray(argv[1]) == "--helper") {
        QCoreApplication helperApp(argc, argv);
        LockHelper helper(QString::fromLocal8Bit(argv[2]), QDBusConnection::sessionBus(),
                          QStringLiteral("org.asteroidos.LockHelperTest"), 120000);
        return helper.registered() ? helperApp.exec() : 1;
    }
    QCoreApplication app(argc, argv);

    // ---- PBKDF2-HMAC-SHA256 against the published vectors (RFC 7914 section 11) ----
    CHECK(pbkdf2("password", "salt", 1).toHex() == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b");
    CHECK(pbkdf2("password", "salt", 2).toHex() == "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43");
    CHECK(pbkdf2("password", "salt", 4096).toHex() == "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a");

    // ---- the credentials' shapes (stock: exactly 4 digits, at least 4 dots) ----
    CHECK(validPin("0000") && validPin("9876"));
    CHECK(!validPin("123") && !validPin("12345") && !validPin("12a4") && !validPin(""));
    CHECK(validPattern("0125") && validPattern("012345678"));
    CHECK(!validPattern("012") && !validPattern("0121") && !validPattern("01239") && !validPattern("0123456789"));
    CHECK(!validPattern("01a4"));

    // ---- the wait table ----
    for (int n = 0; n <= 4; ++n) CHECK(waitAfterFailures(n) == 0);
    CHECK(waitAfterFailures(5) == 30000);
    for (int n = 6; n <= 9; ++n) CHECK(waitAfterFailures(n) == 0);
    for (int n = 10; n <= 29; ++n) CHECK(waitAfterFailures(n) == 30000);
    for (int n = 30; n <= 39; ++n) CHECK(waitAfterFailures(n) == 60000);
    CHECK(waitAfterFailures(40) == 120000 && waitAfterFailures(49) == 120000);
    CHECK(waitAfterFailures(50) == 240000);
    CHECK(waitAfterFailures(1000) == MAX_WAIT_MS);

    QTemporaryDir dir;
    CHECK(dir.isValid());
    const QString path = dir.path() + QStringLiteral("/eos-lock/lock.json");

    // ---- the store ----
    {
        Store s(path, clk);
        CHECK(s.kind() == None && !s.secured());
        CHECK(s.check("1234") == NotSet);
        CHECK(s.set(Pin, QString(), "12") == Invalid);
        CHECK(s.set(Pattern, QString(), "012") == Invalid);
        CHECK(s.set(Pin, QString(), "1234") == Ok);
        CHECK(s.kind() == Pin && s.secured());
        CHECK(QFile::exists(path));
        CHECK((QFile::permissions(path) & (QFile::ReadGroup | QFile::WriteGroup | QFile::ReadOther | QFile::WriteOther)) == 0);
        QFile f(path);
        CHECK(f.open(QIODevice::ReadOnly));
        const QByteArray raw = f.readAll();
        CHECK(!raw.contains("1234"));
        f.close();
        // changing needs the old one
        CHECK(s.set(Pin, "0000", "4321") == Wrong);
        CHECK(s.failures() == 1);
        CHECK(s.set(Pin, "1234", "4321") == Ok);
        CHECK(s.check("1234") == Wrong);
        CHECK(s.check("4321") == Ok);
        CHECK(s.failures() == 0);
        // a pattern with the PIN's digits is not the PIN
        CHECK(s.set(Pattern, "4321", "0124") == Ok);
        CHECK(s.kind() == Pattern);
        CHECK(s.check("4321") == Wrong);
        CHECK(s.check("0124") == Ok);
        CHECK(s.check("0142") == Wrong);       // the order counts
        CHECK(s.check("012") == Wrong);        // a short try is a wrong try
        CHECK(s.failures() == 2);
        CHECK(s.check("0124") == Ok && s.failures() == 0);
        CHECK(s.set(Pin, "0124", "1111") == Ok);
    }
    // saved: a new store reads it
    {
        Store s(path, clk);
        CHECK(s.kind() == Pin);
        CHECK(s.check("1111") == Ok);
        // failures 1 to 4: no wait; the fifth waits 30 s
        for (int i = 1; i <= 4; ++i) {
            CHECK(s.check("0000") == Wrong);
            CHECK(s.remainingMs() == 0);
        }
        CHECK(s.check("0000") == Wrong);
        CHECK(s.failures() == 5);
        CHECK(s.remainingMs() == 30000);
    }
    // the failures and the wait survive a restart; a right PIN inside the wait is refused, not counted
    {
        Store s(path, clk);
        CHECK(s.failures() == 5);
        CHECK(s.remainingMs() == 30000);
        CHECK(s.check("1111") == Throttled);
        CHECK(s.check("0000") == Throttled);
        CHECK(s.failures() == 5);
        now += 12000;
        CHECK(s.remainingMs() == 18000);
        now += 18000;
        CHECK(s.remainingMs() == 0);
        // clock put back: the full wait
        now -= 40000;
        CHECK(s.remainingMs() == 30000);
        now += 40000;
        CHECK(s.check("1111") == Ok);
        CHECK(s.failures() == 0 && s.remainingMs() == 0);
        // 6 to 9: no wait
        for (int i = 1; i <= 4; ++i)
            s.check("0000");
        now += 31000;
        s.check("0000");            // the fifth: wait
        CHECK(s.remainingMs() == 30000);
        now += 31000;
        for (int i = 6; i <= 9; ++i) {
            s.check("0000");
            CHECK(s.failures() == i && s.remainingMs() == 0);
        }
        s.check("0000");            // the tenth: 30 s again
        CHECK(s.failures() == 10 && s.remainingMs() == 30000);
        now += 31000;
        CHECK(s.clear("0000") == Wrong);
        CHECK(s.failures() == 11 && s.remainingMs() == 30000);
        now += 31000;
        CHECK(s.clear("1111") == Ok);
        CHECK(s.kind() == None);
        CHECK(s.clear(QString()) == Ok);
    }
    {
        Store s(path, clk);
        CHECK(s.kind() == None);
    }

    // ---- the service, on the private bus ----
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        fprintf(stderr, "no session bus (run under dbus-run-session)\n");
        return 2;
    }
    const QString p2 = dir.path() + QStringLiteral("/svc/lock.json");
    {
        LockService none(nullptr, bus, p2, clk);
        CHECK(!none.locked() && !none.secured() && none.kindName() == "none");
        none.lock();
        CHECK(!none.locked());                 // nothing to lock with
        CHECK(none.setPin(QString(), "2468") == Ok);
        CHECK(none.secured() && !none.locked());   // set while unlocked: stays unlocked
        QDBusInterface iface(bus.baseService(), "/org/asteroidos/launcher/lock", "org.asteroidos.launcher.Lock", bus);
        CHECK(iface.isValid());
        QDBusReply<QString> st = iface.call("State");
        CHECK(st.isValid() && st.value() == "pin");
        QDBusReply<int> v = iface.call("Verify", "2468");
        CHECK(v.isValid() && v.value() == Ok);
        v = iface.call("Verify", "1357");
        CHECK(v.isValid() && v.value() == Wrong);
        QDBusReply<int> bad = iface.call("SetPin", "0000", "9999");
        CHECK(bad.isValid() && bad.value() == Wrong);
        QDBusReply<int> good = iface.call("SetPin", "2468", "1357");
        CHECK(good.isValid() && good.value() == Ok);
        QDBusReply<int> pat = iface.call("SetPattern", "1357", "0124");
        CHECK(pat.isValid() && pat.value() == Ok);
        st = iface.call("State");
        CHECK(st.value() == "pattern");
        QDBusReply<int> back = iface.call("SetPin", "0124", "1357");
        CHECK(back.value() == Ok);
        iface.call("Lock");
        QDBusReply<bool> lk = iface.call("Locked");
        CHECK(lk.isValid() && lk.value() == true);
        QDBusReply<qlonglong> rem = iface.call("Remaining");
        CHECK(rem.isValid() && rem.value() == 0);
        CHECK(none.locked() && !none.bootLocked());
    }
    // a start with a credential set: locked, the boot lock screen's case
    {
        LockService svc(nullptr, bus, p2, clk);
        CHECK(svc.locked() && svc.bootLocked() && svc.secured());
        int lockedCount = 0, unlockedCount = 0, triesCount = 0;
        QObject::connect(&svc, &LockService::lockedChanged, [&] { lockedCount++; });
        QObject::connect(&svc, &LockService::unlocked, [&] { unlockedCount++; });
        QObject::connect(&svc, &LockService::attempted, [&](int) { triesCount++; });
        CHECK(svc.tryUnlock("1111") == Wrong);
        CHECK(svc.locked() && svc.failures() == 1);
        CHECK(triesCount == 1);
        CHECK(svc.tryUnlock("1357") == Ok);
        CHECK(!svc.locked() && !svc.bootLocked());
        CHECK(lockedCount == 1 && unlockedCount == 1);
        svc.lock();
        CHECK(svc.locked() && !svc.bootLocked());
        for (int i = 0; i < 5; ++i)
            svc.tryUnlock("0000");
        CHECK(svc.remainingMs() == 30000);
        CHECK(svc.tryUnlock("1357") == Throttled);
        CHECK(svc.locked());
        now += 30001;
        CHECK(svc.tryUnlock("1357") == Ok);
        CHECK(svc.clear("1357") == Ok);
        CHECK(!svc.secured() && !svc.locked());
    }

    // ---- the root helper: the credential lives in another process ----
    {
        const QString p3 = dir.path() + QStringLiteral("/helper/lock.json");
        const QString svcName = QStringLiteral("org.asteroidos.LockHelperTest");
        QProcess helper;
        helper.setProgram(QCoreApplication::applicationFilePath());
        helper.setArguments({ QStringLiteral("--helper"), p3 });
        helper.start();
        CHECK(waitForService(svcName, true));
        {
            auto *hb = new HelperBackend(bus, svcName);
            CHECK(hb->reachable());
            CHECK(hb->kind() == None);
            LockService svc(nullptr, bus, QString(), nullptr, hb);
            CHECK(!svc.secured() && !svc.locked());
            CHECK(svc.setPin(QString(), "2468") == Ok);
            CHECK(svc.secured() && svc.kindName() == "pin" && !svc.locked());
            // the hash is in the helper's file, not in this process; the PIN is nowhere in it
            CHECK(QFile::exists(p3));
            CHECK((QFile::permissions(p3) & (QFile::ReadGroup | QFile::WriteGroup | QFile::ReadOther | QFile::WriteOther)) == 0);
            QFile f(p3);
            CHECK(f.open(QIODevice::ReadOnly) && !f.readAll().contains("2468"));
            f.close();
            CHECK(svc.setPin("0000", "1357") == Wrong);
            CHECK(svc.failures() == 1);
            CHECK(svc.verify("2468") == Ok && svc.failures() == 0);
            svc.lock();
            CHECK(svc.locked());
            CHECK(svc.tryUnlock("1111") == Wrong);
            for (int i = 0; i < 4; ++i)
                svc.tryUnlock("1111");
            CHECK(svc.failures() == 5);
            const double rem = svc.remainingMs();
            CHECK(rem > 28000 && rem <= 30000);
            CHECK(svc.tryUnlock("2468") == Throttled);
            CHECK(svc.locked());
        }
        // the helper restarts (an idle exit, a crash, a power cut): the count and the wait are still there
        helper.terminate();
        helper.waitForFinished(5000);
        CHECK(waitForService(svcName, false));
        helper.start();
        CHECK(waitForService(svcName, true));
        {
            auto *hb = new HelperBackend(bus, svcName);
            CHECK(hb->kind() == Pin);
            CHECK(hb->failures() == 5);
            CHECK(hb->remainingMs() > 25000);
            CHECK(hb->check("2468") == Throttled);
            // a service that is not there: nothing is secured, nothing can be set
            auto *none = new HelperBackend(bus, QStringLiteral("org.asteroidos.LockHelperMissing"));
            CHECK(!none->reachable());
            LockService off(nullptr, bus, QString(), nullptr, none);
            CHECK(!off.secured());
            CHECK(off.setPin(QString(), "2468") == Invalid);
            CHECK(!off.secured());
            delete hb;
        }
        helper.terminate();
        helper.waitForFinished(5000);
    }

    printf("tst_lock: %d checks, %d failures\n", checks, failures);
    return failures ? 1 : 0;
}
