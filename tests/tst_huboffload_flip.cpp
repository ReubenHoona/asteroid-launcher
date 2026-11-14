/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * HubOffload::build under the wrist flip (W3-launcher-wrist, wrist-orientation-08): the digit items of a face
 * under the compositor's 180 degree root turn are still offloaded, each sprite where the turned quad is on the
 * panel ((384 - x - w, 384 - y - h) of the upright layout), and a face in any other transform is still refused.
 * Software Qt Quick in an offscreen window; the compositor is a stand-in (tests/stubs/lipstickcompositor.h).
 *   QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software ./tst_huboffload_flip
 */

#include "huboffload.h"
#include "lipstickcompositor.h"

#include <QDateTime>
#include <QFile>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QTemporaryDir>
#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static QStringList sprites, sizes, warnings;
static void handler(QtMsgType type, const QMessageLogContext &, const QString &msg)
{
    if (msg.contains(QLatin1String("hub offload: sprite at")))
        sprites << msg;
    else if (msg.contains(QLatin1String("hub offload: sprite size")))
        sizes << msg;
    else if (type == QtWarningMsg)
        warnings << msg;
}

static QList<QPoint> points(const QStringList &lines, const QString &after)
{
    QList<QPoint> out;
    const QRegularExpression re(after + QStringLiteral(" QPoint\\((-?\\d+),\\s*(-?\\d+)\\)"));
    for (const QString &l : lines) {
        const auto m = re.match(l);
        if (m.hasMatch())
            out << QPoint(m.captured(1).toInt(), m.captured(2).toInt());
    }
    return out;
}

static QList<QSize> sizesOf(const QStringList &lines)
{
    QList<QSize> out;
    const QRegularExpression re(QStringLiteral("QSize\\((\\d+)\\s*[x,]\\s*(\\d+)\\)"));
    for (const QString &l : lines) {
        const auto m = re.match(l);
        if (m.hasMatch())
            out << QSize(m.captured(1).toInt(), m.captured(2).toInt());
    }
    return out;
}

// a face as the bundled digital ones: Roboto Medium, native rendering, a black background, a date text
static QString faceQml(const QString &rootTransform, const QString &hourText, const QString &minuteText)
{
    return QString(R"(
import QtQuick
Item {
    id: stage
    width: 384; height: 384
    %1
    Rectangle { anchors.fill: parent; color: "black" }
    Text { objectName: "eosHubHour"; x: 74; y: 52; text: "%2"; color: "white"; renderType: Text.NativeRendering
           font { family: "Roboto"; pixelSize: 138; weight: Font.Medium } }
    Text { objectName: "eosHubMinute"; x: 150; y: 190; text: "%3"; color: "#c0c0c0"; renderType: Text.NativeRendering
           font { family: "Roboto"; pixelSize: 96; weight: Font.Medium } }
    Text { x: 120; y: 330; text: "Sun 15"; color: "white"; renderType: Text.NativeRendering
           font { family: "Roboto"; pixelSize: 24 } }
}
)").arg(rootTransform, hourText, minuteText);
}

struct Scene {
    QQuickWindow window;
    QQuickItem *face = nullptr;
    Scene(QQmlEngine *engine, const QString &qml)
    {
        window.resize(384, 384);
        QQmlComponent c(engine);
        c.setData(qml.toUtf8(), QUrl());
        QObject *o = c.create();
        if (!o) {
            fprintf(stderr, "qml: %s\n", qPrintable(c.errorString()));
            return;
        }
        face = qobject_cast<QQuickItem *>(o);
        face->setParentItem(window.contentItem());
        window.show();
        QTest_wait();
    }
    static void QTest_wait()
    {
        for (int i = 0; i < 20; i++) {
            QCoreApplication::processEvents();
        }
    }
    ~Scene() { delete face; }
};

static QDateTime shown(int h, int m) { return QDateTime(QDate(2026, 11, 15), QTime(h, m)); }

struct Built {
    bool ok = false;
    QList<QPoint> at;
    QList<QSize> size;
    QStringList warn;
    int layouts = 0;
    qint64 fileSize = 0;
};

static Built build(QQmlEngine *engine, const QString &transform, bool use12h, const QString &hourText,
                   const QString &minuteText, int h, int m)
{
    sprites.clear();
    sizes.clear();
    warnings.clear();
    LipstickCompositor::instance()->layouts.clear();
    LipstickCompositor::instance()->layout = false;
    Scene s(engine, faceQml(transform, hourText, minuteText));
    Built b;
    if (!s.face)
        return b;
    HubOffload hub;
    b.ok = hub.update(s.face, use12h, QStringLiteral("test-face"), shown(h, m));
    b.at = points(sprites, QStringLiteral("hub offload: sprite at"));
    b.size = sizesOf(sizes);
    b.warn = warnings;
    b.layouts = LipstickCompositor::instance()->layouts.size();
    if (b.layouts)
        b.fileSize = QFile(LipstickCompositor::instance()->layouts.last()).size();
    return b;
}

static const QString kTurn = QStringLiteral("transform: Rotation { origin.x: 192; origin.y: 192; angle: 180 }");

static void turnedFaceIsOffloaded(QQmlEngine *engine, bool use12h, const QString &hourText, int h, int m)
{
    const Built up = build(engine, QString(), use12h, hourText, QStringLiteral("%1").arg(m, 2, 10, QLatin1Char('0')), h, m);
    CHECK(up.ok);
    CHECK(up.layouts == 1 && up.fileSize > 1000);
    CHECK(up.size.isEmpty());                           // upright: no turned sprites
    const Built tu = build(engine, kTurn, use12h, hourText, QStringLiteral("%1").arg(m, 2, 10, QLatin1Char('0')), h, m);
    if (!tu.ok) {
        for (const QString &w : tu.warn)
            fprintf(stderr, "  warning: %s\n", qPrintable(w));
    }
    CHECK(tu.ok);
    CHECK(tu.layouts == 1 && tu.fileSize > 1000);
    if (up.at.isEmpty() || up.at.size() != tu.at.size() || tu.size.size() != tu.at.size())
        fprintf(stderr, "  upright %d sprites, turned %d sprites and %d sizes; last log %s\n", int(up.at.size()),
                int(tu.at.size()), int(tu.size.size()), qPrintable(sprites.value(0) + " | " + sizes.value(0)));
    CHECK(!up.at.isEmpty() && up.at.size() == tu.at.size() && tu.size.size() == tu.at.size());
    // every sprite of the turned layout is the point mirror of the upright one, in the same order
    for (int i = 0; i < qMin(up.at.size(), qMin(tu.at.size(), tu.size.size())); i++) {
        CHECK(tu.at[i].x() == 384 - up.at[i].x() - tu.size[i].width());
        CHECK(tu.at[i].y() == 384 - up.at[i].y() - tu.size[i].height());
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

    // 24 h, 10:09: four sprites each way
    turnedFaceIsOffloaded(&engine, false, QStringLiteral("10"), 10, 9);
    // 12 h, a one-digit and a two-digit hour (both strings are in the layout, as the hub shows one of them)
    turnedFaceIsOffloaded(&engine, true, QStringLiteral("9"), 9, 41);
    turnedFaceIsOffloaded(&engine, true, QStringLiteral("11"), 23, 41);

    // the number of sprites is the same turned and upright (4 in 24 h): no digit lost
    {
        const Built up = build(&engine, QString(), false, QStringLiteral("10"), QStringLiteral("09"), 10, 9);
        const Built tu = build(&engine, kTurn, false, QStringLiteral("10"), QStringLiteral("09"), 10, 9);
        CHECK(up.at.size() == 4 && tu.at.size() == 4);
    }

    // another transform is refused, with the reason, and no layout reaches the daemon
    {
        const Built r90 = build(&engine, QStringLiteral("rotation: 90"), false, QStringLiteral("10"), QStringLiteral("09"), 10, 9);
        CHECK(!r90.ok);
        CHECK(r90.layouts == 0);
        bool reason = false;
        for (const QString &w : r90.warn)
            reason |= w.contains(QLatin1String("rotated or scaled"));
        CHECK(reason);
        const Built r5 = build(&engine, QStringLiteral("rotation: 180.5"), false, QStringLiteral("10"), QStringLiteral("09"), 10, 9);
        CHECK(!r5.ok && r5.layouts == 0);
        const Built sc = build(&engine, QStringLiteral("scale: 0.9"), false, QStringLiteral("10"), QStringLiteral("09"), 10, 9);
        CHECK(!sc.ok && sc.layouts == 0);
    }

    // a change of the turn is a new layout: the key holds it (one build per setting, none per update)
    {
        sprites.clear();
        LipstickCompositor::instance()->layouts.clear();
        Scene s(&engine, faceQml(QString(), QStringLiteral("10"), QStringLiteral("09")));
        HubOffload hub;
        CHECK(hub.update(s.face, false, QStringLiteral("k"), shown(10, 9)));
        CHECK(LipstickCompositor::instance()->layouts.size() == 1);
        CHECK(hub.update(s.face, false, QStringLiteral("k"), shown(10, 9)));        // same key: nothing rebuilt
        CHECK(LipstickCompositor::instance()->layouts.size() == 1);
        s.face->setProperty("rotation", 180);
        QCoreApplication::processEvents();
        CHECK(hub.update(s.face, false, QStringLiteral("k"), shown(10, 9)));
        CHECK(LipstickCompositor::instance()->layouts.size() == 2);
    }

    if (failures)
        fprintf(stderr, "tst_huboffload_flip: %d of %d checks failed\n", failures, checks);
    else
        fprintf(stderr, "tst_huboffload_flip: all %d checks passed\n", checks);
    return failures ? 1 : 0;
}
