/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * HubOffload::build for the Concentric face (src/watchfaces/027-concentric.qml): the sensor hub's
 * always-on layout with the turning minutes dial (huboffload.h: eosHubDial, eosHubCover, eosHubZeroPad).
 *  - the layout is made and handed over, the 12 h hour as two digits ("06": four time sprites);
 *  - the dial is numeral slots (60 cells, one per value, and 12 more for each slot the covers reach)
 *    and long-tick slots (61 cells), the same at every minute (the hub turns it), each numeral slot
 *    exactly where the AP draws the numeral of that slot (one ink offset for all), each long tick
 *    inside its slot's cell;
 *  - the black disk and the circle stay in the background: no sprite of theirs; the numeral slots
 *    they reach have cells of their own (cut by them), the ones they hide (3 o'clock: the minute's
 *    circle) have no sprite, and an AP numeral there lies under the disk; at a whole five minutes
 *    (10:40) the slot under the circle has no numeral sprite but its long tick (cut by the disk);
 *  - the AP's always-on short ticks are the same pixels at every minute (the hub's background has
 *    them; they stand still, only the long ones turn);
 *  - Dial II has no tick slots; under the wrist flip every slot is the point mirror;
 *  - Half Dial (R5 A-06): the dial moved left, the slots off the panel without sprites, the vignette's
 *    (eosHubShade) slots with cells of their own, the AP's ticks darkened by it;
 *  - a dial that shows another minute is refused (the AP draws).
 * The real face file, its eoskit and the image's org.asteroid.controls (Motion), software Qt Quick in an
 * offscreen window; the compositor is a stand-in (tests/stubs/lipstickcompositor.h). With CONC_OUT set the
 * layouts and the AP's frames are kept there (for the hub model's picture, aod91 layoutmodel.py).
 *   QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software ./tst_huboffload_dial
 */

#include "huboffload.h"
#include "lipstickcompositor.h"

#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QGuiApplication>
#include <QImage>
#include <QMap>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QTemporaryDir>
#include <QThread>
#include <climits>
#include <cmath>
#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static QStringList timeSprites, dialLines, dialSummary, warnings;
static void handler(QtMsgType type, const QMessageLogContext &, const QString &msg)
{
    if (msg.contains(QLatin1String("hub offload: sprite at")))
        timeSprites << msg;
    else if (msg.contains(QLatin1String("hub offload: dial cells")))
        dialLines << msg;
    else if (msg.contains(QLatin1String("hub offload: dial of")))
        dialSummary << msg;
    else if (type == QtWarningMsg || type == QtCriticalMsg)
        warnings << msg;
}

// one cells group of the log: "hub offload: dial cells <i> <w>x<h>x<n>: j:x,y j:x,y ..." (slot j's
// sprite top-left)
struct Group {
    QSize cell;
    int n = 0;
    QMap<int, QPoint> at;
};
static QList<Group> groups()
{
    QList<Group> out;
    const QRegularExpression re(QStringLiteral("dial cells (\\d+) (\\d+)x(\\d+)x(\\d+):(.*)$"));
    for (const QString &l : dialLines) {
        const auto m = re.match(l);
        if (!m.hasMatch())
            continue;
        Group g;
        g.cell = QSize(m.captured(2).toInt(), m.captured(3).toInt());
        g.n = m.captured(4).toInt();
        const QStringList pts = m.captured(5).split(QLatin1Char(' '), Qt::SkipEmptyParts);
        for (const QString &p : pts) {
            const QStringList jxy = p.split(QLatin1Char(':'));
            const QStringList xy = jxy.value(1).split(QLatin1Char(','));
            g.at.insert(jxy.value(0).toInt(), QPoint(xy.value(0).toInt(), xy.value(1).toInt()));
        }
        out << g;
    }
    return out;
}

static void findNamed(QQuickItem *item, const QString &name, QList<QQuickItem *> *out)
{
    if (!item->isVisible())
        return;
    if (item->objectName() == name)
        *out << item;
    for (QQuickItem *c : item->childItems())
        findNamed(c, name, out);
}

static const QString kTurn = QStringLiteral("transform: Rotation { origin.x: 192; origin.y: 192; angle: 180 }");

struct Scene {
    QQuickWindow window;
    QQuickItem *stage = nullptr;
    QQuickItem *face = nullptr;
    Scene(QQmlEngine *engine, const QString &transform, int h, int m, bool use12h, const QString &style)
    {
        window.resize(384, 384);
        const QString qml = QString(R"(
import QtQuick
Item {
    width: 384; height: 384
    %1
    property var wallClock: ({ time: new Date(2026, 10, 24, %2, %3, 5) })
    property var use12H: ({ value: %4 })
    property bool displayAmbient: true
    Rectangle { anchors.fill: parent; color: "black" }
    Loader {
        objectName: "faceLoader"
        anchors.fill: parent
        source: "%5"
        onLoaded: if ("%6" !== "") item.eosStyle = { layout: "%6" }
    }
}
)").arg(transform).arg(h).arg(m).arg(use12h ? "true" : "false")
   .arg(QUrl::fromLocalFile(QStringLiteral(SRC_ROOT "/src/watchfaces/027-concentric.qml")).toString(), style);
        QQmlComponent c(engine);
        c.setData(qml.toUtf8(), QUrl());
        QObject *o = c.create();
        if (!o) {
            fprintf(stderr, "qml: %s\n", qPrintable(c.errorString()));
            return;
        }
        stage = qobject_cast<QQuickItem *>(o);
        stage->setParentItem(window.contentItem());
        window.show();
        QObject *loader = stage->findChild<QObject *>(QStringLiteral("faceLoader"));
        for (int i = 0; i < 400 && !face; i++) {
            QCoreApplication::processEvents();
            face = loader ? loader->property("item").value<QQuickItem *>() : nullptr;
        }
        // the always-on look is in when the face's blend has run to 1 (300 ms; it may start late)
        QElapsedTimer waited;
        waited.start();
        while (face && (face->property("blend").toReal() < 1 || waited.elapsed() < 600) && waited.elapsed() < 60000) {
            QCoreApplication::processEvents();
            QThread::msleep(5);
        }
        for (int i = 0; i < 40; i++)
            QCoreApplication::processEvents();
        if (!face)
            fprintf(stderr, "the face did not load\n");
    }
    ~Scene() { delete stage; }
};

static QDateTime shown(int h, int m) { return QDateTime(QDate(2026, 11, 24), QTime(h, m)); }

struct Built {
    bool ok = false;
    QList<Group> groups;
    int timeSprites = 0;
    int layouts = 0;
    qint64 fileSize = 0;
    QStringList warn;
    QList<QPoint> numeralTopLeft;       // the AP's numeral Texts (scene, rounded) by slot, -1,-1 if none
    QList<QRect> tickRect;              // the AP's long ticks (scene) by slot
    QList<QRectF> covers;
    // "dial of N numeral slots (K with cells of their own, H under the covers), C covers in the background"
    int numeralSlots = -1, ownSlots = -1, hiddenSlots = -1, coversInBackground = -1;
    QImage ap;                          // the AP's always-on frame
};

static Built build(QQmlEngine *engine, const QString &transform, int h, int m, bool use12h,
                   const QString &style = QString(), int shownMinute = -1, const QString &keep = QString())
{
    timeSprites.clear();
    dialLines.clear();
    dialSummary.clear();
    warnings.clear();
    LipstickCompositor::instance()->layouts.clear();
    LipstickCompositor::instance()->layout = false;
    Scene s(engine, transform, h, m, use12h, style);
    Built b;
    if (!s.face)
        return b;
    for (int j = 0; j < 60; j++) {
        b.numeralTopLeft << QPoint(-1, -1);
        b.tickRect << QRect();
    }
    QList<QQuickItem *> numerals, ticks, covers;
    findNamed(s.face, QStringLiteral("eosHubDialNumeral"), &numerals);
    findNamed(s.face, QStringLiteral("eosHubDialTick"), &ticks);
    findNamed(s.face, QStringLiteral("eosHubCover"), &covers);
    for (QQuickItem *n : numerals) {
        const int v = n->property("text").toString().toInt();
        const int slot = ((v - m) % 60 + 60) % 60;
        // the corner of the turned item is its bottom-right on the panel
        const QRectF r = n->mapRectToScene(QRectF(0, 0, n->width(), n->height()));
        b.numeralTopLeft[slot] = QPoint(qRound(r.left()), qRound(r.top()));
    }
    QQuickItem *dial = s.face->findChild<QQuickItem *>(QStringLiteral("eosHubDial"));
    for (QQuickItem *t : ticks) {
        const QRectF r = t->mapRectToScene(QRectF(0, 0, t->width(), t->height()));
        // the slot: the long tick of slot j runs out at j * 6 degrees
        const QPointF c = r.center() - dial->mapToScene(QPointF(192, 192));
        const qreal deg = std::atan2(-c.y(), c.x()) * 180 / M_PI;
        const int slot = (qRound(deg / 6) % 60 + 60) % 60;
        b.tickRect[transform.isEmpty() ? slot : (slot + 30) % 60] = r.toAlignedRect();
    }
    for (QQuickItem *c : covers)
        b.covers << c->mapRectToScene(QRectF(0, 0, c->width(), c->height()));
    b.ap = s.window.grabWindow().convertToFormat(QImage::Format_RGB32);
    HubOffload hub;
    b.ok = hub.update(s.face, use12h, QStringLiteral("concentric") + transform + style,
                      shown(h, shownMinute < 0 ? m : shownMinute));
    b.groups = groups();
    if (!dialSummary.isEmpty()) {
        const auto sm = QRegularExpression(QStringLiteral("dial of (\\d+) numeral slots \\((\\d+) with cells of their "
                                                          "own, (\\d+) under the covers\\), (\\d+) covers"))
                            .match(dialSummary.last());
        if (sm.hasMatch()) {
            b.numeralSlots = sm.captured(1).toInt();
            b.ownSlots = sm.captured(2).toInt();
            b.hiddenSlots = sm.captured(3).toInt();
            b.coversInBackground = sm.captured(4).toInt();
        }
    }
    b.timeSprites = timeSprites.size();
    b.warn = warnings;
    b.layouts = LipstickCompositor::instance()->layouts.size();
    if (b.layouts)
        b.fileSize = QFile(LipstickCompositor::instance()->layouts.last()).size();
    const QByteArray out = qgetenv("CONC_OUT");
    if (!out.isEmpty() && !keep.isEmpty() && b.layouts) {
        QDir().mkpath(QString::fromLocal8Bit(out));
        const QString base = QString::fromLocal8Bit(out) + QLatin1Char('/') + keep;
        QFile::remove(base + ".bin");
        QFile::copy(LipstickCompositor::instance()->layouts.last(), base + ".bin");
        s.window.grabWindow().save(base + "-ap.png");
    }
    if (!b.ok)
        for (const QString &w : b.warn)
            fprintf(stderr, "  warning: %s\n", qPrintable(w));
    return b;
}

// the dial of an upright layout: numeral slots (60 cells, 12 more per slot the covers reach), long-tick
// slots (61 cells); the covers (the black disk, then the circle) in the background
static void dialIsSlots(const Built &b, int m, bool ticks)
{
    CHECK(b.ok);
    CHECK(b.layouts == 1 && b.fileSize > 20000);
    CHECK(b.groups.size() == (ticks ? 2 : 1));
    if (b.groups.size() != (ticks ? 2 : 1))
        return;
    CHECK(b.coversInBackground == 2);
    const Group &num = b.groups[0];
    CHECK(b.numeralSlots == num.at.size());
    CHECK(b.numeralSlots + b.hiddenSlots == 60);
    CHECK(num.n == 60 + 12 * b.ownSlots);
    // the disk under the circle hides the slots at 3 o'clock and reaches a few round them
    CHECK(b.hiddenSlots >= 1 && b.hiddenSlots <= 5);
    CHECK(b.ownSlots >= 2 && b.ownSlots <= 10);
    CHECK(!num.at.contains(0));
    const QRectF disk = b.covers.value(0);
    // every numeral of the AP is at its slot's sprite less one ink offset, the same for all; one
    // whose slot has no sprite lies under the disk
    QPoint offset(INT_MIN, INT_MIN);
    int seen = 0, under = 0;
    for (int j = 0; j < 60; j++) {
        if (b.numeralTopLeft[j].x() < 0)
            continue;
        seen++;
        CHECK(((m + j) % 60) % 5 == 0);
        if (!num.at.contains(j)) {
            under++;
            const QPointF c = QPointF(b.numeralTopLeft[j]) + QPointF(13, 10) - disk.center();
            if (std::hypot(c.x(), c.y()) > disk.width() / 2 - 8)
                fprintf(stderr, "  slot %d: no sprite, but the numeral is not under the disk\n", j);
            CHECK(std::hypot(c.x(), c.y()) <= disk.width() / 2 - 8);
            continue;
        }
        const QPoint d = num.at[j] - b.numeralTopLeft[j];
        if (offset.x() == INT_MIN)
            offset = d;
        if (d != offset)
            fprintf(stderr, "  slot %d: offset %d,%d, slot of the first %d,%d\n", j, d.x(), d.y(), offset.x(), offset.y());
        CHECK(d == offset);
    }
    CHECK(seen == 12);
    CHECK(under <= 1);
    // the numeral cell is about a numeral's ink (23 px Roboto: two digits, 17 px tall)
    CHECK(num.cell.height() >= 16 && num.cell.height() <= 20 && num.cell.width() >= 20 && num.cell.width() <= 32);
    if (ticks) {
        const Group &tk = b.groups[1];
        CHECK(tk.n == 61 && tk.at.size() >= 56 && tk.at.size() <= 60);
        int inside = 0, ap = 0;
        for (int j = 0; j < 60; j++) {
            if (b.tickRect[j].isNull())
                continue;
            ap++;
            CHECK(tk.at.contains(j));
            if (!tk.at.contains(j))
                continue;
            const QRect cell(tk.at[j], tk.cell);
            // the scene graph's antialiasing reaches half a pixel over the bar
            if (cell.contains(b.tickRect[j].adjusted(1, 1, -1, -1)))
                inside++;
            else
                fprintf(stderr, "  tick slot %d: %d,%d %dx%d not in cell %d,%d %dx%d\n", j, b.tickRect[j].x(),
                        b.tickRect[j].y(), b.tickRect[j].width(), b.tickRect[j].height(), cell.x(), cell.y(),
                        cell.width(), cell.height());
        }
        CHECK(ap == 12 && inside == 12);
        CHECK(tk.cell.width() <= 16 && tk.cell.height() <= 16);
    }
}

// the AP's short ticks of the inner ring (130.5..137.5 px out, 2 px wide) at the slots where neither
// minute has a long tick: the same pixels in both frames, but for a level of rounding (the software
// renderer of the test draws a window in parts); a tick a pixel over is a hundred levels
static int shortTicksDiffer(const Built &a, int ma, const Built &b, int mb)
{
    int bad = 0;
    for (int j = 0; j < 60; j++) {
        if ((ma + j) % 5 == 0 || (mb + j) % 5 == 0)
            continue;
        const qreal t = j * 6 * M_PI / 180;
        const QPointF p0(192 + 130.5 * std::cos(t), 192 - 130.5 * std::sin(t));
        const QPointF p1(192 + 137.5 * std::cos(t), 192 - 137.5 * std::sin(t));
        const QRect r = QRectF(p0, p1).normalized().toAlignedRect().adjusted(-2, -2, 2, 2);
        for (int y = r.top(); y <= r.bottom(); y++)
            for (int x = r.left(); x <= r.right(); x++)
                if (std::abs(qRed(a.ap.pixel(x, y)) - qRed(b.ap.pixel(x, y))) > 2 ||
                    std::abs(qGreen(a.ap.pixel(x, y)) - qGreen(b.ap.pixel(x, y))) > 2 ||
                    std::abs(qBlue(a.ap.pixel(x, y)) - qBlue(b.ap.pixel(x, y))) > 2) {
                    if (!bad)
                        fprintf(stderr, "  short tick of slot %d differs at %d,%d\n", j, x, y);
                    bad++;
                }
    }
    return bad;
}

// the same slots (keys and places) in two layouts
static bool sameSlots(const Built &a, const Built &b)
{
    if (a.groups.size() != b.groups.size())
        return false;
    for (int i = 0; i < a.groups.size(); i++)
        if (a.groups[i].at != b.groups[i].at || a.groups[i].cell != b.groups[i].cell || a.groups[i].n != b.groups[i].n)
            return false;
    return true;
}

int main(int argc, char **argv)
{
    qputenv("QT_QPA_PLATFORM", "offscreen");
    qputenv("QT_QUICK_BACKEND", "software");
    QTemporaryDir runtime;
    qputenv("XDG_RUNTIME_DIR", runtime.path().toUtf8());
    qInstallMessageHandler(handler);
    QGuiApplication app(argc, argv);
    QQmlEngine engine;

    // 12 h, 06:42 and 10:09: the dial and two-digit hours (four time sprites, no one-digit variant)
    const Built a = build(&engine, QString(), 6, 42, true, QString(), -1, QStringLiteral("hub-0642"));
    dialIsSlots(a, 42, true);
    CHECK(a.timeSprites == 4);
    const Built b = build(&engine, QString(), 10, 9, true, QString(), -1, QStringLiteral("hub-1009"));
    dialIsSlots(b, 9, true);
    CHECK(b.timeSprites == 4);
    // the slots do not depend on the minute: the hub turns the dial
    CHECK(a.groups.size() == 2 && b.groups.size() == 2);
    CHECK(sameSlots(a, b));
    // the short ticks stand still always-on: the background holds at every minute
    CHECK(shortTicksDiffer(a, 42, b, 9) == 0);

    // a whole five minutes: 40 is under the circle (no numeral sprite at slot 0, the AP's 40 under the
    // disk), the long tick at 3 o'clock is there, cut by the disk (the hub model's picture shows it)
    const Built f = build(&engine, QString(), 10, 40, true, QString(), -1, QStringLiteral("hub-1040"));
    dialIsSlots(f, 40, true);
    CHECK(sameSlots(a, f));
    CHECK(f.numeralTopLeft[0].x() >= 0 && f.groups.size() == 2 && !f.groups[0].at.contains(0));
    CHECK(f.groups.size() == 2 && f.groups[1].at.contains(0));
    // and one with partly covered numerals next to the circle (45 at slot 2, 40 at slot 57)
    const Built g = build(&engine, QString(), 10, 43, true, QString(), -1, QStringLiteral("hub-1043"));
    dialIsSlots(g, 43, true);
    CHECK(sameSlots(a, g));
    CHECK(shortTicksDiffer(f, 40, g, 43) == 0);
    CHECK(shortTicksDiffer(b, 9, g, 43) == 0);

    // 24 h at 18:05, Dial II: no tick slots
    const Built c = build(&engine, QString(), 18, 5, false, QStringLiteral("dial2"));
    dialIsSlots(c, 5, false);
    CHECK(c.timeSprites == 4);

    // the wrist flip: every numeral slot is the point mirror of the upright one (the covers turn with
    // the face, so the same slots have sprites and cells of their own)
    const Built t = build(&engine, kTurn, 6, 42, true);
    CHECK(t.ok);
    CHECK(t.groups.size() == 2);
    CHECK(t.ownSlots == a.ownSlots && t.hiddenSlots == a.hiddenSlots);
    if (t.groups.size() == 2 && a.groups.size() == 2) {
        CHECK(t.groups[0].cell == a.groups[0].cell && t.groups[0].n == a.groups[0].n);
        CHECK(t.groups[0].at.keys() == a.groups[0].at.keys());
        for (int j : a.groups[0].at.keys())
            CHECK(t.groups[0].at.value(j) == QPoint(384, 384) - a.groups[0].at[j] - QPoint(a.groups[0].cell.width(),
                                                                                         a.groups[0].cell.height()));
        CHECK(t.groups[1].at.size() == a.groups[1].at.size());
    }

    // Half Dial (R5 A-06): the dial 142 px to the left, the hour at 82 px, the vignette over the left half.
    // The numeral slots off the panel have no sprite; the ones the vignette darkens have cells of their own (cut
    // by it, as by a cover), so there are more of those than on Dial I; every sprite is where the AP draws its
    // numeral (one ink offset for all)
    const Built hd = build(&engine, QString(), 10, 9, true, QStringLiteral("half"), -1, QStringLiteral("hub-half-1009"));
    CHECK(hd.ok);
    CHECK(hd.layouts == 1);
    CHECK(hd.timeSprites == 4);
    fprintf(stderr, "  Half Dial: %d numeral slots (%d with cells of their own, %d hidden), %d cell atlases, layout %lld bytes"
                    " (Dial I: %d slots, %d own)\n", hd.numeralSlots, hd.ownSlots, hd.hiddenSlots, int(hd.groups.size()),
            hd.fileSize, b.numeralSlots, b.ownSlots);
    CHECK(hd.coversInBackground == 2);
    CHECK(hd.numeralSlots + hd.hiddenSlots == 60);
    CHECK(hd.hiddenSlots > b.hiddenSlots + 5);
    CHECK(hd.ownSlots > b.ownSlots);
    // more than 16 slots of their own: their cells spill into a second numeral atlas (at most 256 cells each:
    // 60 + 12 x 16, then 1 + 12 x 21), the long ticks' atlas last
    CHECK(hd.ownSlots > 16);
    CHECK(hd.groups.size() == 2 + (hd.ownSlots - 16 + 20) / 21);
    for (const Group &g : hd.groups)
        CHECK(g.n <= 256);
    if (hd.groups.size() >= 3) {
        CHECK(hd.groups[0].n == 60 + 12 * 16);
        CHECK(hd.groups[1].n == 1 + 12 * qMin(21, hd.ownSlots - 16));
        CHECK(hd.groups.last().n == 61);
        // every numeral slot in exactly one atlas
        Group num;
        int inBoth = 0;
        for (int i = 0; i + 1 < hd.groups.size(); i++)
            for (int j : hd.groups[i].at.keys()) {
                if (num.at.contains(j))
                    inBoth++;
                num.at.insert(j, hd.groups[i].at[j]);
            }
        CHECK(inBoth == 0);
        CHECK(num.at.size() == hd.numeralSlots);
        QPoint offset(INT_MIN, INT_MIN);
        int withSprite = 0;
        for (int j = 0; j < 60; j++) {
            if (hd.numeralTopLeft[j].x() == -1 && hd.numeralTopLeft[j].y() == -1)
                continue;
            if (!num.at.contains(j)) {
                // no sprite: the numeral is off the panel or under the disk
                const QPoint p = hd.numeralTopLeft[j];
                const QPointF c = QPointF(p) + QPointF(13, 10) - hd.covers.value(0).center();
                const bool off = p.x() < -10 || p.y() < -10 || p.x() > 384 - 16 || p.y() > 384 - 10;
                CHECK(off || std::hypot(c.x(), c.y()) <= hd.covers.value(0).width() / 2);
                continue;
            }
            withSprite++;
            const QPoint d = num.at[j] - hd.numeralTopLeft[j];
            if (offset.x() == INT_MIN)
                offset = d;
            CHECK(d == offset);
        }
        CHECK(withSprite >= 5);
        // the AP's long ticks: under the vignette darker by its alpha (black of a ramp from 151.2 to 201.6 px
        // from the screen's middle, on its left half), outside it as bright as on Dial I
        int shaded = 0, clear = 0;
        for (int j = 0; j < 60; j++) {
            const QRect r = hd.tickRect[j].intersected(QRect(0, 0, 384, 384));
            if (r.isEmpty())
                continue;
            int peak = 0;
            for (int y = r.top(); y <= r.bottom(); y++)
                for (int x = r.left(); x <= r.right(); x++)
                    peak = qMax(peak, qMax(qRed(hd.ap.pixel(x, y)), qMax(qGreen(hd.ap.pixel(x, y)), qBlue(hd.ap.pixel(x, y)))));
            const QPointF c = QRectF(r).center() - QPointF(192, 192);
            // only what the round panel shows (the square's corners lie outside the vignette's disc)
            if (std::hypot(c.x(), c.y()) > 188)
                continue;
            const qreal a = c.x() > 0 ? 0 : qBound(0.0, (std::hypot(c.x(), c.y()) / 201.6 - 0.75) / 0.25, 1.0);
            if (a == 0) {
                clear++;
                CHECK(peak >= 80);
            } else if (a >= 0.4) {
                shaded++;
                if (peak > (1 - a) * 104 + 16)
                    fprintf(stderr, "  tick slot %d: peak %d under a vignette of %.2f\n", j, peak, a);
                CHECK(peak <= (1 - a) * 104 + 16);
            }
        }
        CHECK(clear >= 4);
        CHECK(shaded >= 1);
    }

    // a dial that is not at the minute of the layout: refused, no layout
    const Built r = build(&engine, QString(), 6, 42, true, QString(), 43);
    CHECK(!r.ok);
    CHECK(r.layouts == 0);

    fprintf(stderr, "%s: %d checks, %d failed\n", failures ? "FAIL" : "PASS", checks, failures);
    return failures ? 1 : 0;
}
