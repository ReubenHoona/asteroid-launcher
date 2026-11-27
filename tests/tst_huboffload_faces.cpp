/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * HubOffload::build for the eos digital faces drawn by the sensor hub always-on (R5 A-07): the real face file
 * at an always-on minute, its digit items (eosHubHour, eosHubMinute) made into a layout within the hub's atlas
 * budget, so the AP sleeps through the minutes:
 *  - Big Time (src/watchfaces/028-big-time.qml): 167 px digits in two colours, at 10:09 and 06:33 in 12 h (the
 *    one- and two-digit hours: five time sprites) and 18:33 in 24 h (four), each sprite in its item's colour;
 *  - Large Scale on its Spring default (022-large) and Everyday Big (020-stacked, 172 px) as the faces with the
 *    biggest digits before it.
 * Software Qt Quick in an offscreen window; the compositor is a stand-in (tests/stubs/lipstickcompositor.h).
 *   QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software ./tst_huboffload_faces
 */

#include "huboffload.h"
#include "lipstickcompositor.h"

#include <QDateTime>
#include <QElapsedTimer>
#include <QFile>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QTemporaryDir>
#include <QThread>
#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static QStringList timeSprites, loaded, warnings;
static void handler(QtMsgType type, const QMessageLogContext &, const QString &msg)
{
    if (msg.contains(QLatin1String("hub offload: sprite at")))
        timeSprites << msg;
    else if (msg.contains(QLatin1String("hub offload: layout of")))
        loaded << msg;
    else if (type == QtWarningMsg || type == QtCriticalMsg)
        warnings << msg;
}

struct Built {
    bool ok = false;
    int layouts = 0;
    int sprites = 0;
    int atlasKb = -1;
    QString hourText, minuteText;
    QColor hourColor, minuteColor;
};

// the face at h:m always-on, as the home screen has it (FaceLayer's context; style: a JS object of the favourite's
// options), then the hub's layout
static Built build(QQmlEngine *engine, const QString &file, int h, int m, bool use12h, const QString &style = QString())
{
    timeSprites.clear();
    loaded.clear();
    warnings.clear();
    LipstickCompositor::instance()->layouts.clear();
    LipstickCompositor::instance()->layout = false;
    Built b;
    QQuickWindow window;
    window.resize(384, 384);
    const QString qml = QString(R"(
import QtQuick
Item {
    width: 384; height: 384
    property var wallClock: ({ time: new Date(2026, 10, 24, %1, %2, 5) })
    property var use12H: ({ value: %3 })
    property bool displayAmbient: true
    property var faceStyle: %5
    Rectangle { anchors.fill: parent; color: "black" }
    Loader {
        objectName: "faceLoader"
        anchors.fill: parent
        source: "%4"
        onLoaded: item.eosStyle = faceStyle
    }
}
)").arg(h).arg(m).arg(use12h ? "true" : "false")
   .arg(QUrl::fromLocalFile(QStringLiteral(SRC_ROOT "/src/watchfaces/") + file).toString(),
        style.isEmpty() ? QStringLiteral("({})") : style);
    QQmlComponent c(engine);
    c.setData(qml.toUtf8(), QUrl());
    QObject *o = c.create();
    if (!o) {
        fprintf(stderr, "qml: %s\n", qPrintable(c.errorString()));
        return b;
    }
    QQuickItem *stage = qobject_cast<QQuickItem *>(o);
    stage->setParentItem(window.contentItem());
    window.show();
    QObject *loader = stage->findChild<QObject *>(QStringLiteral("faceLoader"));
    QQuickItem *face = nullptr;
    for (int i = 0; i < 400 && !face; i++) {
        QCoreApplication::processEvents();
        face = loader ? loader->property("item").value<QQuickItem *>() : nullptr;
    }
    QElapsedTimer waited;
    waited.start();
    while (face && (face->property("blend").toReal() < 1 || waited.elapsed() < 600) && waited.elapsed() < 60000) {
        QCoreApplication::processEvents();
        QThread::msleep(5);
    }
    for (int i = 0; i < 40; i++)
        QCoreApplication::processEvents();
    if (!face) {
        fprintf(stderr, "%s did not load\n", qPrintable(file));
        delete stage;
        return b;
    }
    QQuickItem *hour = face->findChild<QQuickItem *>(QStringLiteral("eosHubHour"));
    QQuickItem *minute = face->findChild<QQuickItem *>(QStringLiteral("eosHubMinute"));
    if (hour && minute) {
        b.hourText = hour->property("text").toString();
        b.minuteText = minute->property("text").toString();
        b.hourColor = hour->property("color").value<QColor>();
        b.minuteColor = minute->property("color").value<QColor>();
    }
    HubOffload hub;
    b.ok = hub.update(face, use12h, file + style, QDateTime(QDate(2026, 11, 24), QTime(h, m)));
    b.layouts = LipstickCompositor::instance()->layouts.size();
    b.sprites = timeSprites.size();
    const auto lm = QRegularExpression(QStringLiteral("\\((\\d+) sprites, atlases (\\d+) KB\\)"))
                        .match(loaded.isEmpty() ? QString() : loaded.last());
    if (lm.hasMatch())
        b.atlasKb = lm.captured(2).toInt();
    if (!b.ok)
        for (const QString &w : warnings)
            fprintf(stderr, "  %s: %s\n", qPrintable(file), qPrintable(w));
    else
        fprintf(stderr, "  %s %02d:%02d%s: %d time sprites, atlases %d KB\n", qPrintable(file), h, m,
                use12h ? " 12 h" : "", b.sprites, b.atlasKb);
    delete stage;
    return b;
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
    const QString big = QStringLiteral("028-big-time.qml");

    // Big Time, 10:09 in 12 h: a layout; the hour's one- and two-digit strings and the two minute digits
    Built a = build(&engine, big, 10, 9, true);
    CHECK(a.ok);
    CHECK(a.layouts == 1);
    CHECK(a.hourText == QStringLiteral("10") && a.minuteText == QStringLiteral("09"));
    CHECK(a.sprites == 5);
    CHECK(a.atlasKb > 0 && a.atlasKb <= 384);
    // the two tones: Pomelo's text colour over its light ramp
    CHECK(a.hourColor == QColor(QStringLiteral("#f8908b")));
    CHECK(a.minuteColor == QColor(QStringLiteral("#ffcbc9")));
    // 06:33: the one-digit hour, the same layout rules
    Built b = build(&engine, big, 6, 33, true);
    CHECK(b.ok && b.layouts == 1);
    CHECK(b.hourText == QStringLiteral("6"));
    CHECK(b.sprites == 5);
    // 24 h: two digits each
    Built c = build(&engine, big, 18, 33, false);
    CHECK(c.ok && c.layouts == 1);
    CHECK(c.hourText == QStringLiteral("18"));
    CHECK(c.sprites == 4);
    CHECK(c.atlasKb > 0 && c.atlasKb <= 384);
    // a two-tone colourway of the long list (Sunset: the hours pink, the minutes blue)
    Built d = build(&engine, big, 10, 9, true, QStringLiteral("({ color: \"sunset\" })"));
    CHECK(d.ok && d.layouts == 1);
    CHECK(d.hourColor == QColor(QStringLiteral("#ffcaed")));
    CHECK(d.minuteColor == QColor(QStringLiteral("#b6daf1")));

    // the other big-digit faces still fit
    Built e = build(&engine, QStringLiteral("022-large.qml"), 10, 9, true);
    CHECK(e.ok && e.layouts == 1);
    Built f = build(&engine, QStringLiteral("020-stacked.qml"), 10, 9, true, QStringLiteral("({ layout: \"big\" })"));
    CHECK(f.ok && f.layouts == 1);

    fprintf(stderr, "%s: %d checks, %d failed\n", failures ? "FAIL" : "PASS", checks, failures);
    return failures ? 1 : 0;
}
