/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSLOCK_H
#define EOSLOCK_H

#include <QByteArray>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMessageAuthenticationCode>
#include <QRandomGenerator>
#include <QSaveFile>
#include <QString>
#include <QtGlobal>

#include <functional>

/*
 * The screen lock's credential store (W3-launcher-a11y-security,
 * accessibility-lock-security-03, -05, -08): plain Qt Core, no bus, so that
 * tests/tst_lock.cpp covers every rule.
 *
 * Stock CP3A keeps a PIN (exactly 4 digits) or a pattern (3 x 3 dots, at
 * least 4) in the framework's Gatekeeper; the default is "None". Ours is a
 * salted PBKDF2-HMAC-SHA256 of the credential in a JSON file (default
 * /var/lib/eos-lock/lock.json, mode 0600, the launcher's own user: the
 * credential never leaves this process except through the lock service's
 * calls). The failure counter is saved BEFORE the answer of a check is
 * given, so a restart or a power cut does not give a free attempt.
 *
 * Throttle (inferred AOSP software Gatekeeper, as the audit says): 30 s
 * after failure 5, 30 s after failure 10 and after each of 11 to 29, from
 * failure 30 on 30 s doubled for every further 10 failures (60 s for 30 to
 * 39, 120 s for 40 to 49, ...), at most 24 h. The deadline is a wall clock
 * time; a clock set back before the last failure counts as the full wait.
 */
namespace EosLock {

enum Kind { None = 0, Pin = 1, Pattern = 2 };

// verify() and check() answers
enum Result { Ok = 0, Wrong = 1, Throttled = 2, NotSet = 3, Invalid = 4 };

constexpr int PIN_LENGTH = 4;
constexpr int PATTERN_MIN_DOTS = 4;
constexpr int PATTERN_DOTS = 9;
constexpr int ITERATIONS = 10000;
constexpr qint64 MAX_WAIT_MS = 24LL * 3600 * 1000;

inline QString kindName(int k)
{
    return k == Pin ? QStringLiteral("pin") : k == Pattern ? QStringLiteral("pattern") : QStringLiteral("none");
}

inline int kindFromName(const QString &n)
{
    return n == QLatin1String("pin") ? Pin : n == QLatin1String("pattern") ? Pattern : None;
}

// exactly four digits
inline bool validPin(const QString &s)
{
    if (s.size() != PIN_LENGTH)
        return false;
    for (const QChar c : s)
        if (c < QLatin1Char('0') || c > QLatin1Char('9'))
            return false;
    return true;
}

// the dots in the order they were drawn, "0".."8" (row-major from the top left): at least 4, none twice
inline bool validPattern(const QString &s)
{
    if (s.size() < PATTERN_MIN_DOTS || s.size() > PATTERN_DOTS)
        return false;
    int seen = 0;
    for (const QChar c : s) {
        if (c < QLatin1Char('0') || c > QLatin1Char('8'))
            return false;
        const int bit = 1 << (c.unicode() - '0');
        if (seen & bit)
            return false;
        seen |= bit;
    }
    return true;
}

// How long the wait after failure number n is, ms (0 = none)
inline qint64 waitAfterFailures(int n)
{
    if (n < 5)
        return 0;
    if (n >= 30) {
        const int doublings = (n - 20) / 10;
        qint64 ms = 30000;
        for (int i = 0; i < doublings && ms < MAX_WAIT_MS; ++i)
            ms *= 2;
        return qMin(ms, MAX_WAIT_MS);
    }
    if (n == 5 || n >= 10)
        return 30000;
    return 0;
}

/* PBKDF2-HMAC-SHA256 (RFC 8018), one 32 byte block */
inline QByteArray pbkdf2(const QByteArray &password, const QByteArray &salt, int iterations)
{
    QByteArray first = salt;
    first.append(char(0)).append(char(0)).append(char(0)).append(char(1));
    QByteArray u = QMessageAuthenticationCode::hash(first, password, QCryptographicHash::Sha256);
    QByteArray t = u;
    for (int i = 1; i < iterations; ++i) {
        u = QMessageAuthenticationCode::hash(u, password, QCryptographicHash::Sha256);
        for (int j = 0; j < t.size(); ++j)
            t[j] = char(t[j] ^ u[j]);
    }
    return t;
}

// a comparison that takes as long for every input
inline bool sameBytes(const QByteArray &a, const QByteArray &b)
{
    if (a.size() != b.size())
        return false;
    unsigned char d = 0;
    for (int i = 0; i < a.size(); ++i)
        d |= static_cast<unsigned char>(a[i] ^ b[i]);
    return d == 0;
}

class Store
{
public:
    explicit Store(const QString &path = QString(), std::function<qint64()> clock = nullptr)
        : mPath(path), mClock(clock ? clock : [] { return QDateTime::currentMSecsSinceEpoch(); })
    {
        load();
    }

    int kind() const { return mKind; }
    bool secured() const { return mKind != None; }
    int failures() const { return mFailures; }
    QString path() const { return mPath; }
    // when the wait ends (ms since the epoch), 0 = no wait
    qint64 waitUntil() const { return mUntil; }

    /* Milliseconds still to wait before the next try, 0 = none. A clock put
     * back to before the last failure is the full wait. */
    qint64 remainingMs() const
    {
        if (mUntil <= 0)
            return 0;
        const qint64 now = mClock();
        if (now < mLastFailure)
            return waitAfterFailures(mFailures);
        return qMax<qint64>(0, qMin(mUntil - now, waitAfterFailures(mFailures)));
    }

    /* Check a credential. Counts a failure (and saves it first) when wrong, and
     * answers Wrong for it even when it starts a wait (remainingMs() > 0);
     * a check during a wait answers Throttled and is neither counted nor compared. */
    Result check(const QString &secret)
    {
        if (!secured())
            return NotSet;
        // a try during the wait is neither counted nor compared
        if (remainingMs() > 0)
            return Throttled;
        // a malformed try is a wrong one: a pattern of 3 dots is no way round the counter
        if (!(mKind == Pin ? validPin(secret) : validPattern(secret)))
            return fail();
        if (sameBytes(digest(mKind, secret, mSalt, mIter), mHash)) {
            if (mFailures != 0 || mUntil != 0) {
                mFailures = 0;
                mUntil = 0;
                mLastFailure = 0;
                save();
            }
            return Ok;
        }
        return fail();
    }

    /* Set a credential. A credential in force has to be confirmed first. */
    Result set(int kind, const QString &old, const QString &secret)
    {
        if (kind != Pin && kind != Pattern)
            return Invalid;
        if (!(kind == Pin ? validPin(secret) : validPattern(secret)))
            return Invalid;
        if (secured()) {
            const Result r = check(old);
            if (r != Ok)
                return r;
        }
        mKind = kind;
        mSalt.resize(16);
        QRandomGenerator::system()->fillRange(reinterpret_cast<quint32 *>(mSalt.data()), mSalt.size() / 4);
        mIter = ITERATIONS;
        mHash = digest(kind, secret, mSalt, mIter);
        mFailures = 0;
        mUntil = 0;
        mLastFailure = 0;
        return save() ? Ok : Invalid;
    }

    /* "None": the credential in force confirms it. */
    Result clear(const QString &old)
    {
        if (!secured())
            return Ok;
        const Result r = check(old);
        if (r != Ok)
            return r;
        mKind = None;
        mSalt.clear();
        mHash.clear();
        mFailures = 0;
        mUntil = 0;
        mLastFailure = 0;
        return save() ? Ok : Invalid;
    }

private:
    static QByteArray digest(int kind, const QString &secret, const QByteArray &salt, int iterations)
    {
        return pbkdf2(kindName(kind).toUtf8() + ':' + secret.toUtf8(), salt, iterations);
    }

    Result fail()
    {
        mFailures++;
        mLastFailure = mClock();
        const qint64 wait = waitAfterFailures(mFailures);
        mUntil = wait > 0 ? mLastFailure + wait : 0;
        save();
        // (the caller reads remainingMs(): the try that brings a wait is wrong, and the wait starts)
        return Wrong;
    }

    void load()
    {
        if (mPath.isEmpty())
            return;
        QFile f(mPath);
        if (!f.open(QIODevice::ReadOnly))
            return;
        const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
        const int k = kindFromName(o.value(QStringLiteral("kind")).toString());
        const QByteArray salt = QByteArray::fromBase64(o.value(QStringLiteral("salt")).toString().toLatin1());
        const QByteArray hash = QByteArray::fromBase64(o.value(QStringLiteral("hash")).toString().toLatin1());
        if (k == None || salt.isEmpty() || hash.size() != 32)
            return;
        mKind = k;
        mSalt = salt;
        mHash = hash;
        mIter = o.value(QStringLiteral("iter")).toInt(ITERATIONS);
        mFailures = o.value(QStringLiteral("failures")).toInt();
        mUntil = qint64(o.value(QStringLiteral("until")).toDouble());
        mLastFailure = qint64(o.value(QStringLiteral("last")).toDouble());
    }

    bool save()
    {
        if (mPath.isEmpty())
            return true;
        QDir().mkpath(QFileInfo(mPath).absolutePath());
        QSaveFile f(mPath);
        if (!f.open(QIODevice::WriteOnly))
            return false;
        QJsonObject o;
        o.insert(QStringLiteral("kind"), kindName(mKind));
        o.insert(QStringLiteral("salt"), QString::fromLatin1(mSalt.toBase64()));
        o.insert(QStringLiteral("hash"), QString::fromLatin1(mHash.toBase64()));
        o.insert(QStringLiteral("iter"), mIter);
        o.insert(QStringLiteral("failures"), mFailures);
        o.insert(QStringLiteral("until"), double(mUntil));
        o.insert(QStringLiteral("last"), double(mLastFailure));
        f.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
        f.write(QJsonDocument(o).toJson(QJsonDocument::Compact));
        return f.commit();
    }

    QString mPath;
    std::function<qint64()> mClock;
    int mKind = None;
    QByteArray mSalt;
    QByteArray mHash;
    int mIter = ITERATIONS;
    int mFailures = 0;
    qint64 mUntil = 0;
    qint64 mLastFailure = 0;
};

} // namespace EosLock

#endif // EOSLOCK_H
