/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The wrist and crown setting (W3-launcher-wrist): the rules of lipstick/src/eoswrist.h, the launcher's
 * WristOrientation (the mode, the sensor hub call at the start / on a change / when the service appears) on a
 * private bus against a fake sensorfwd, and the crown's event filter on the compositor window.
 *   dbus-run-session -- ./tst_wrist
 */

#include "wristorientation.h"
#include <eoswrist.h>

#include <QCoreApplication>
#include <QDBusAbstractAdaptor>
#include <QDBusConnection>
#include <QEvent>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QEventLoop>
#include <QTimer>
#include <QTransform>
#include <QWheelEvent>
#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

/* ---- the fake sensorfwd: org.eos.UsfHub at /org/eos/usfhub ------------------------------------------ */

class HubAdaptor : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.eos.UsfHub")
public:
    explicit HubAdaptor(QObject *parent) : QDBusAbstractAdaptor(parent) {}
    QList<int> calls;
    int answer = 0;
public slots:
    int SetWristOrientation(int mode)
    {
        calls << mode;
        return mode < 0 || mode > 3 ? -22 : answer;
    }
};

static const char *kService = "org.eos.test.WristHub";

struct FakeHub {
    QObject object;
    HubAdaptor *adaptor = new HubAdaptor(&object);
    bool up = false;
    bool start()
    {
        QDBusConnection bus = QDBusConnection::sessionBus();
        if (!bus.registerObject(QStringLiteral("/org/eos/usfhub"), &object))
            return false;
        up = bus.registerService(QLatin1String(kService));
        return up;
    }
    void stop()
    {
        QDBusConnection::sessionBus().unregisterService(QLatin1String(kService));
        QDBusConnection::sessionBus().unregisterObject(QStringLiteral("/org/eos/usfhub"));
        up = false;
    }
};

// the event loop for ms milliseconds (Qt Core only, as the other tests of the launcher)
static void wait(int ms)
{
    QEventLoop loop;
    QTimer::singleShot(ms, &loop, &QEventLoop::quit);
    loop.exec();
}

// waits for the hub's call list to reach n
static bool waitCalls(FakeHub &hub, int n)
{
    for (int i = 0; i < 100 && hub.adaptor->calls.size() < n; i++)
        wait(20);
    return hub.adaptor->calls.size() >= n;
}

/* ---- a stand-in for the compositor's window ---------------------------------------------------------- */

class Target : public QObject
{
public:
    QList<QPoint> angle, pixel;
    int keys = 0;
    bool accept = true;
    bool event(QEvent *e) override
    {
        if (e->type() == QEvent::Wheel) {
            auto *w = static_cast<QWheelEvent *>(e);
            angle << w->angleDelta();
            pixel << w->pixelDelta();
            e->setAccepted(accept);
            return true;
        }
        if (e->type() == QEvent::KeyPress)
            keys++;
        return QObject::event(e);
    }
};

static void sendWheel(QObject *to, QPoint angleDelta, QPoint pixelDelta = QPoint())
{
    QWheelEvent e(QPointF(10, 20), QPointF(110, 120), pixelDelta, angleDelta, Qt::NoButton, Qt::NoModifier,
                  Qt::NoScrollPhase, false);
    QCoreApplication::sendEvent(to, &e);
}

/* ---- the tests --------------------------------------------------------------------------------------- */

static void rules()
{
    // stock's table (WristOrientationFragment.java:52-68): wrist, crown, display
    struct Row { int mode; bool crownLeft, right, flipped; int rot, gx; };
    const Row rows[] = {
        { 0, false, false, false, 0, 1 },
        { 1, true, false, true, 180, 1 },
        { 2, false, true, false, 0, -1 },
        { 3, true, true, true, 180, -1 },
    };
    for (const Row &r : rows) {
        CHECK(EosWrist::crownLeft(r.mode) == r.crownLeft);
        CHECK(EosWrist::rightWrist(r.mode) == r.right);
        CHECK(EosWrist::flipped(r.mode) == r.flipped);
        CHECK(EosWrist::rotation(r.mode) == r.rot);
        CHECK(EosWrist::gestureXSign(r.mode) == r.gx);
    }
    // the stored value: 0..3, anything else is the default 0
    CHECK(EosWrist::normalize(QVariant()) == 0);
    CHECK(EosWrist::normalize(QVariant(0)) == 0);
    CHECK(EosWrist::normalize(QVariant(1)) == 1);
    CHECK(EosWrist::normalize(QVariant(2)) == 2);
    CHECK(EosWrist::normalize(QVariant(3)) == 3);
    CHECK(EosWrist::normalize(QVariant(4)) == 0);
    CHECK(EosWrist::normalize(QVariant(-1)) == 0);
    CHECK(EosWrist::normalize(QVariant(QStringLiteral("junk"))) == 0);
    CHECK(EosWrist::normalize(QVariant(QStringLiteral("3"))) == 3);
    CHECK(EosWrist::normalize(QVariant(2.0)) == 2);
    CHECK(EosWrist::key() == QLatin1String("/org/asteroidos/settings/wrist-orientation-mode"));
    // the crown: negated only while flipped
    CHECK(EosWrist::wheelDelta(120, false) == 120);
    CHECK(EosWrist::wheelDelta(120, true) == -120);
    CHECK(EosWrist::wheelDelta(-15, true) == 15);
}

// the back swipe (wrist-orientation-07): the sign of the screen's x axis in the window's space
static void axisSign()
{
    QTransform upright;                                     // the window at its place
    CHECK(EosWrist::axisSign(upright.map(QPointF(1, 0)) - upright.map(QPointF(0, 0))) == 1);
    QTransform turn;                                        // the root turned 180 about (192, 192)
    turn.translate(192, 192);
    turn.rotate(180);
    turn.translate(-192, -192);
    CHECK(turn.map(QPointF(0, 0)) == QPointF(384, 384));
    CHECK(EosWrist::axisSign(turn.map(QPointF(1, 0)) - turn.map(QPointF(0, 0))) == -1);
    // the window's own scale (the open and close animation) and move do not change the sign
    QTransform scaled = turn;
    scaled.scale(0.8, 0.8);
    scaled.translate(40, 0);
    CHECK(EosWrist::axisSign(scaled.map(QPointF(1, 0)) - scaled.map(QPointF(0, 0))) == -1);
    QTransform scaledUp;
    scaledUp.translate(30, 10);
    scaledUp.scale(0.5, 0.5);
    CHECK(EosWrist::axisSign(scaledUp.map(QPointF(1, 0)) - scaledUp.map(QPointF(0, 0))) == 1);
    // a finger going from the user's left to right: +x upright, -x in panel pixels when turned; the
    // sign makes both the same logical swipe (the checks of trackBackSwipe: 32 px to the right)
    const qreal startPanel = 300, endPanel = 240;           // turned: leftward on the panel
    const int sign = EosWrist::axisSign(turn.map(QPointF(1, 0)) - turn.map(QPointF(0, 0)));
    CHECK(sign * (endPanel - startPanel) == 60);
    CHECK((endPanel - startPanel) < 0);
    const qreal dx = sign * endPanel - sign * startPanel;   // the tracker's x is sign * scene x
    CHECK(dx >= 32.0);
}

static void tellsTheHub()
{
    FakeHub hub;
    CHECK(hub.start());
    {
        WristOrientation w(nullptr, QDBusConnection::sessionBus(), QLatin1String(kService));
        int changed = 0, flip = 0;
        QObject::connect(&w, &WristOrientation::changed, &w, [&] { changed++; });
        QObject::connect(&w, &WristOrientation::flipChanged, &w, [&] { flip++; });
        CHECK(w.mode() == 0 && !w.flip() && w.rotation() == 0);

        // the start: the stored default is told to the hub too
        w.setMode(QVariant(), true);
        CHECK(waitCalls(hub, 1));
        CHECK(hub.adaptor->calls == QList<int>({ 0 }));
        CHECK(changed == 0 && flip == 0);

        // the same value again: nothing is sent
        w.setMode(QVariant(0));
        wait(150);
        CHECK(hub.adaptor->calls.size() == 1);

        w.setMode(QVariant(1));
        CHECK(waitCalls(hub, 2));
        CHECK(hub.adaptor->calls.last() == 1);
        CHECK(w.mode() == 1 && w.flip() && w.crownLeft() && !w.rightWrist() && w.rotation() == 180);
        CHECK(w.gestureXSign() == 1);
        CHECK(changed == 1 && flip == 1);

        // crown left on the other wrist: still turned, no new flipChanged
        w.setMode(QVariant(3));
        CHECK(waitCalls(hub, 3));
        CHECK(hub.adaptor->calls.last() == 3);
        CHECK(w.flip() && w.rightWrist() && w.gestureXSign() == -1);
        CHECK(changed == 2 && flip == 1);

        w.setMode(QVariant(2));
        CHECK(waitCalls(hub, 4));
        CHECK(hub.adaptor->calls.last() == 2);
        CHECK(!w.flip() && w.rotation() == 0 && w.rightWrist());
        CHECK(flip == 2);

        // an unreadable value is the default, and is told as such
        w.setMode(QVariant(QStringLiteral("junk")));
        CHECK(waitCalls(hub, 5));
        CHECK(hub.adaptor->calls.last() == 0);
        CHECK(w.mode() == 0);
    }
    hub.stop();
}

static void hubComesLater()
{
    // the launcher starts first: the call finds no service (and does not start one); when the service
    // appears on the bus the launcher tells it the mode, once, on the bus's own signal
    WristOrientation w(nullptr, QDBusConnection::sessionBus(), QLatin1String(kService));
    w.setMode(QVariant(3), true);
    wait(200);
    FakeHub hub;
    CHECK(hub.adaptor->calls.isEmpty());
    CHECK(hub.start());
    CHECK(waitCalls(hub, 1));
    wait(150);
    CHECK(hub.adaptor->calls == QList<int>({ 3 }));
    // the hub restarts: told again, with the mode it has now
    hub.stop();
    wait(100);
    w.setMode(QVariant(2));
    wait(100);
    CHECK(hub.start());
    CHECK(waitCalls(hub, 2));
    CHECK(hub.adaptor->calls.last() == 2);
    hub.stop();
}

static void crownFilter()
{
    Target window;
    WristOrientation w(nullptr, QDBusConnection::sessionBus(), QLatin1String("org.eos.test.NoSuchHub"));
    w.attachWindow(&window);

    // not flipped: the event arrives as it is
    sendWheel(&window, QPoint(0, 120), QPoint(0, 4));
    CHECK(window.angle.size() == 1 && window.angle[0] == QPoint(0, 120));
    CHECK(window.pixel[0] == QPoint(0, 4));

    // flipped: once, negated, whatever the step
    w.setMode(QVariant(1));
    sendWheel(&window, QPoint(0, 120), QPoint(0, 4));
    CHECK(window.angle.size() == 2);
    CHECK(window.angle[1] == QPoint(0, -120));
    CHECK(window.pixel[1] == QPoint(0, -4));
    sendWheel(&window, QPoint(0, -15));
    CHECK(window.angle.size() == 3 && window.angle[2] == QPoint(0, 15));
    sendWheel(&window, QPoint(0, 1));
    CHECK(window.angle.last() == QPoint(0, -1));
    sendWheel(&window, QPoint(8, 0));
    CHECK(window.angle.last() == QPoint(-8, 0));

    // the accepted flag goes back to the sender of the original
    window.accept = false;
    QWheelEvent e(QPointF(), QPointF(), QPoint(), QPoint(0, 120), Qt::NoButton, Qt::NoModifier,
                  Qt::NoScrollPhase, false);
    e.setAccepted(true);
    QCoreApplication::sendEvent(&window, &e);
    CHECK(!e.isAccepted());
    window.accept = true;

    // other events are not touched
    QKeyEvent key(QEvent::KeyPress, Qt::Key_A, Qt::NoModifier);
    QCoreApplication::sendEvent(&window, &key);
    CHECK(window.keys == 1);

    // mode 3 turns, mode 2 does not
    const int before = window.angle.size();
    w.setMode(QVariant(3));
    sendWheel(&window, QPoint(0, 30));
    CHECK(window.angle[before] == QPoint(0, -30));
    w.setMode(QVariant(2));
    sendWheel(&window, QPoint(0, 30));
    CHECK(window.angle.last() == QPoint(0, 30));
    CHECK(window.angle.size() == before + 2);

    // another window: the old one is let go
    Target second;
    w.setMode(QVariant(1));
    w.attachWindow(&second);
    sendWheel(&window, QPoint(0, 60));
    CHECK(window.angle.last() == QPoint(0, 60));
    sendWheel(&second, QPoint(0, 60));
    CHECK(second.angle.size() == 1 && second.angle[0] == QPoint(0, -60));
    // the same window twice: still one turn
    w.attachWindow(&second);
    sendWheel(&second, QPoint(0, 60));
    CHECK(second.angle.size() == 2 && second.angle[1] == QPoint(0, -60));
    // no window: nothing is filtered
    w.attachWindow(nullptr);
    sendWheel(&second, QPoint(0, 60));
    CHECK(second.angle.last() == QPoint(0, 60));
}

/* qml-asteroid's RotaryInput is an application-level filter that consumes the window's wheel event
 * (rotaryinput.cpp: handleWheel returns true) and installed itself first (RotaryInput::install, at the
 * controls plugin's load). A stand-in with the same manners: it eats every wheel event sent to the
 * watched object, and counts what it was shown. */
class Eater : public QObject
{
public:
    QObject *only = nullptr;
    QList<QPoint> seen;
    bool eventFilter(QObject *watched, QEvent *e) override
    {
        if (e->type() != QEvent::Wheel || watched != only)
            return false;
        seen << static_cast<QWheelEvent *>(e)->angleDelta();
        e->accept();
        return true;
    }
};

static void crownBeforeRotaryInput()
{
    Target window, item;
    Eater rotary;
    rotary.only = &window;
    qApp->installEventFilter(&rotary);                       // RotaryInput::install, at the plugin load
    WristOrientation w(nullptr, QDBusConnection::sessionBus(), QLatin1String("org.eos.test.NoSuchHub"));
    w.attachWindow(&window);

    // not flipped: the consumer sees the raw turn, the window's own handler never does (consumed)
    sendWheel(&window, QPoint(0, 120), QPoint(0, 4));
    CHECK(rotary.seen.size() == 1 && rotary.seen[0] == QPoint(0, 120));
    CHECK(window.angle.isEmpty());

    // flipped: the consumer sees the turn negated, once (the copy passes the application filters again)
    w.setMode(QVariant(1));
    sendWheel(&window, QPoint(0, 120), QPoint(0, 4));
    CHECK(rotary.seen.size() == 2 && rotary.seen[1] == QPoint(0, -120));
    sendWheel(&window, QPoint(0, -30));
    CHECK(rotary.seen.size() == 3 && rotary.seen[2] == QPoint(0, 30));
    CHECK(window.angle.isEmpty());

    // an item's copy of the event (Qt Quick sends it on to the item through the same filters) is not turned again
    rotary.only = &item;
    sendWheel(&item, QPoint(0, 120));
    CHECK(rotary.seen.size() == 4 && rotary.seen[3] == QPoint(0, 120));
    CHECK(item.angle.isEmpty());
    rotary.only = &window;

    // a consumer installed after the attach is ahead of the flip: attaching again puts the flip in front
    Eater late;
    late.only = &window;
    qApp->installEventFilter(&late);
    sendWheel(&window, QPoint(0, 60));
    CHECK(late.seen.size() == 1 && late.seen[0] == QPoint(0, 60));      // raw: the flip is behind it
    w.attachWindow(&window);
    sendWheel(&window, QPoint(0, 60));
    CHECK(late.seen.size() == 2 && late.seen[1] == QPoint(0, -60));
    CHECK(rotary.seen.size() == 4);
    qApp->removeEventFilter(&late);

    // the flip off: raw again
    w.setMode(QVariant(0));
    sendWheel(&window, QPoint(0, 60));
    CHECK(rotary.seen.size() == 5 && rotary.seen[4] == QPoint(0, 60));

    // no window: nothing is turned
    w.setMode(QVariant(1));
    w.attachWindow(nullptr);
    sendWheel(&window, QPoint(0, 60));
    CHECK(rotary.seen.size() == 6 && rotary.seen[5] == QPoint(0, 60));
    qApp->removeEventFilter(&rotary);
}

static void filterGoesWithTheWindow()
{
    WristOrientation w(nullptr, QDBusConnection::sessionBus(), QLatin1String("org.eos.test.NoSuchHub"));
    w.setMode(QVariant(1));
    {
        Target gone;
        w.attachWindow(&gone);
    }
    Target next;
    w.attachWindow(&next);                                  // the old one is gone: no dangling filter
    sendWheel(&next, QPoint(0, 10));
    CHECK(next.angle.size() == 1 && next.angle[0] == QPoint(0, -10));
}

int main(int argc, char **argv)
{
    qputenv("QT_QPA_PLATFORM", "offscreen");
    QGuiApplication app(argc, argv);
    if (!QDBusConnection::sessionBus().isConnected()) {
        fprintf(stderr, "tst_wrist: no session bus (run it under dbus-run-session)\n");
        return 2;
    }
    rules();
    axisSign();
    tellsTheHub();
    hubComesLater();
    crownFilter();
    filterGoesWithTheWindow();
    crownBeforeRotaryInput();
    if (failures)
        fprintf(stderr, "tst_wrist: %d of %d checks failed\n", failures, checks);
    else
        fprintf(stderr, "tst_wrist: all %d checks passed\n", checks);
    return failures ? 1 : 0;
}

#include "tst_wrist.moc"
