/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * HubOffload::build for the Concentric face (src/watchfaces/027-concentric.qml): the sensor hub's
 * always-on layout with the turning minutes dial (huboffload.h: eosHubDial, eosHubCover, eosHubZeroPad).
 *  - the layout is made and handed over, the 12 h hour as two digits ("06": four time sprites);
 *  - the dial is 60 numeral slots (cells of 60: one per value) and 60 long-tick slots (61 cells),
 *    the same at every minute (the hub turns it), each numeral slot exactly where the AP draws the
 *    numeral of that slot (one ink offset for all), each long tick inside its slot's cell;
 *  - the black disk and the circle are drawn by the hub over the dial;
 *  - Dial II has no tick slots; under the wrist flip every slot is the point mirror;
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

static QStringList timeSprites, dialLines, warnings;
static void handler(QtMsgType type, const QMessageLogContext &, const QString &msg)
{
    if (msg.contains(QLatin1String("hub offload: sprite at")))
        timeSprites << msg;
    else if (msg.contains(QLatin1String("hub offload: dial cells")))
        dialLines << msg;
    else if (type == QtWarningMsg || type == QtCriticalMsg)
        warnings << msg;
}

// one cells group of the log: "hub offload: dial cells <i> <w>x<h>x<n>: x,y x,y ..."
struct Group {
    QSize cell;
    int n = 0;
    QList<QPoint> at;
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
            const QStringList xy = p.split(QLatin1Char(','));
            g.at << QPoint(xy.value(0).toInt(), xy.value(1).toInt());
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
};

static Built build(QQmlEngine *engine, const QString &transform, int h, int m, bool use12h,
                   const QString &style = QString(), int shownMinute = -1, const QString &keep = QString())
{
    timeSprites.clear();
    dialLines.clear();
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
    HubOffload hub;
    b.ok = hub.update(s.face, use12h, QStringLiteral("concentric") + transform + style,
                      shown(h, shownMinute < 0 ? m : shownMinute));
    b.groups = groups();
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

// the dial of an upright layout: numerals (60 cells), ticks (61 cells), two covers
static void dialIsSlots(const Built &b, int m, bool ticks)
{
    CHECK(b.ok);
    CHECK(b.layouts == 1 && b.fileSize > 20000);
    CHECK(b.groups.size() == (ticks ? 4 : 3));
    if (b.groups.size() != (ticks ? 4 : 3))
        return;
    const Group &num = b.groups[0];
    CHECK(num.n == 60 && num.at.size() == 60);
    // every numeral of the AP is at its slot's sprite less one ink offset, the same for all 12
    QPoint offset(INT_MIN, INT_MIN);
    int seen = 0;
    for (int j = 0; j < 60 && num.at.size() == 60; j++) {
        if (b.numeralTopLeft[j].x() < 0)
            continue;
        seen++;
        CHECK(((m + j) % 60) % 5 == 0);
        const QPoint d = num.at[j] - b.numeralTopLeft[j];
        if (offset.x() == INT_MIN)
            offset = d;
        if (d != offset)
            fprintf(stderr, "  slot %d: offset %d,%d, slot of the first %d,%d\n", j, d.x(), d.y(), offset.x(), offset.y());
        CHECK(d == offset);
    }
    CHECK(seen == 12);
    // the numeral cell is about a numeral's ink (23 px Roboto: two digits, 17 px tall)
    CHECK(num.cell.height() >= 16 && num.cell.height() <= 20 && num.cell.width() >= 20 && num.cell.width() <= 32);
    int next = 1;
    if (ticks) {
        const Group &tk = b.groups[next++];
        CHECK(tk.n == 61 && tk.at.size() == 60);
        int inside = 0;
        for (int j = 0; j < 60 && tk.at.size() == 60; j++) {
            if (b.tickRect[j].isNull())
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
        CHECK(inside == 12);
        CHECK(tk.cell.width() <= 16 && tk.cell.height() <= 16);
    }
    // the covers: the black disk, then the circle, each one cell over its Rectangle
    for (int i = 0; i < 2; i++) {
        const Group &cv = b.groups[next + i];
        CHECK(cv.n == 1 && cv.at.size() == 1);
        if (cv.at.size() == 1 && i < b.covers.size())
            CHECK(QRect(cv.at[0], cv.cell).contains(b.covers[i].toAlignedRect()));
    }
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
    CHECK(a.groups.size() == 4 && b.groups.size() == 4);
    for (int i = 0; i < qMin(a.groups.size(), b.groups.size()); i++) {
        CHECK(a.groups[i].at == b.groups[i].at);
        CHECK(a.groups[i].cell == b.groups[i].cell);
    }

    // 24 h at 18:05, Dial II: no tick slots
    const Built c = build(&engine, QString(), 18, 5, false, QStringLiteral("dial2"));
    dialIsSlots(c, 5, false);
    CHECK(c.timeSprites == 4);

    // the wrist flip: every slot is the point mirror of the upright one
    const Built t = build(&engine, kTurn, 6, 42, true);
    CHECK(t.ok);
    CHECK(t.groups.size() == 4);
    for (int i = 0; i < qMin(t.groups.size(), a.groups.size()); i++) {
        CHECK(t.groups[i].at.size() == a.groups[i].at.size());
        CHECK(t.groups[i].cell == a.groups[i].cell || i == 1);
        if (i == 0) {
            for (int j = 0; j < qMin(t.groups[0].at.size(), a.groups[0].at.size()); j++)
                CHECK(t.groups[0].at[j] == QPoint(384, 384) - a.groups[0].at[j] - QPoint(a.groups[0].cell.width(),
                                                                                         a.groups[0].cell.height()));
        }
    }

    // a dial that is not at the minute of the layout: refused, no layout
    const Built r = build(&engine, QString(), 6, 42, true, QString(), 43);
    CHECK(!r.ok);
    CHECK(r.layouts == 0);

    fprintf(stderr, "%s: %d checks, %d failed\n", failures ? "FAIL" : "PASS", checks, failures);
    return failures ? 1 : 0;
}
