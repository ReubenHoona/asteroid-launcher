/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The screenshot file (system-dialogs-misc-09): lipstick/src/eosscreenshot.h. The capture cut to a circle
 * with transparent corners, wear_screenshot_<time>.png, Pictures/Screenshots. Qt Gui only (offscreen).
 */

#include "eosscreenshot.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QGuiApplication>
#include <QImage>
#include <QTemporaryDir>
#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static QImage frame(int w, int h)
{
    QImage img(w, h, QImage::Format_RGB32);
    img.fill(QColor(200, 100, 50));
    return img;
}

static void name()
{
    const QDateTime t(QDate(2026, 11, 14), QTime(9, 30, 15));
    CHECK(EosShot::fileName(t) == QLatin1String("wear_screenshot_20261114-093015.png"));
    CHECK(EosShot::directory(QStringLiteral("/home/ceres/Pictures")) == QLatin1String("/home/ceres/Pictures/Screenshots"));
}

static void roundMask()
{
    const QImage in = frame(384, 384);
    const QImage out = EosShot::roundMask(in);
    CHECK(out.size() == in.size());
    CHECK(out.hasAlphaChannel());
    // the four corners are transparent, the centre and the points of the circle's edge are kept
    CHECK(qAlpha(out.pixel(0, 0)) == 0);
    CHECK(qAlpha(out.pixel(383, 0)) == 0);
    CHECK(qAlpha(out.pixel(0, 383)) == 0);
    CHECK(qAlpha(out.pixel(383, 383)) == 0);
    CHECK(qAlpha(out.pixel(20, 20)) == 0);
    CHECK(qAlpha(out.pixel(192, 192)) == 255);
    CHECK(qAlpha(out.pixel(192, 2)) == 255);          // top of the circle
    CHECK(qAlpha(out.pixel(2, 192)) == 255);
    CHECK(qAlpha(out.pixel(381, 192)) == 255);
    CHECK(qAlpha(out.pixel(192, 381)) == 255);
    // 45 degrees: inside at 0.70 of the radius, outside at 1.05
    const int in45 = 192 + int(0.70 * 192 * 0.7071);
    const int out45 = 192 + int(1.05 * 192 * 0.7071);
    CHECK(qAlpha(out.pixel(in45, in45)) == 255);
    CHECK(qAlpha(out.pixel(out45, out45)) == 0);
    // the colour inside is the capture's
    CHECK(qRed(out.pixel(192, 192)) == 200 && qGreen(out.pixel(192, 192)) == 100 && qBlue(out.pixel(192, 192)) == 50);
    // the area is the circle's: pi r^2 within 1 %
    long long opaque = 0;
    for (int y = 0; y < out.height(); y++)
        for (int x = 0; x < out.width(); x++)
            if (qAlpha(out.pixel(x, y)) > 127)
                opaque++;
    const double disc = 3.14159265 * 192.0 * 192.0;
    CHECK(opaque > disc * 0.99 && opaque < disc * 1.01);
}

static void squareOrRectangularInput()
{
    // a non-square grab: the circle is the shorter side's
    const QImage out = EosShot::roundMask(frame(400, 300));
    CHECK(qAlpha(out.pixel(200, 150)) == 255);
    CHECK(qAlpha(out.pixel(54, 150)) == 255);          // the circle of radius 150 centred at 200: its left edge is at 50
    CHECK(qAlpha(out.pixel(44, 150)) == 0);
    CHECK(qAlpha(out.pixel(0, 0)) == 0);
}

static void saveInTheFolder()
{
    QTemporaryDir dir;
    CHECK(dir.isValid());
    const QString pictures = dir.path() + QStringLiteral("/Pictures");
    const QDateTime t(QDate(2026, 11, 14), QTime(9, 30, 15));
    const QString path = EosShot::savePath(pictures, t);
    CHECK(path == pictures + QLatin1String("/Screenshots/wear_screenshot_20261114-093015.png"));
    CHECK(QDir(pictures + QLatin1String("/Screenshots")).exists());     // made on the way
    CHECK(EosShot::roundMask(frame(384, 384)).save(path, "PNG", 100));
    QImage back(path);
    CHECK(!back.isNull());
    CHECK(back.hasAlphaChannel());
    CHECK(qAlpha(back.pixel(0, 0)) == 0);
    CHECK(qAlpha(back.pixel(192, 192)) == 255);
    // a second call finds the folder there
    CHECK(EosShot::savePath(pictures, t.addSecs(1)).endsWith(QLatin1String("wear_screenshot_20261114-093016.png")));
}

int main(int argc, char **argv)
{
    qputenv("QT_QPA_PLATFORM", "offscreen");
    QGuiApplication app(argc, argv);
    name();
    roundMask();
    squareOrRectangularInput();
    saveInTheFolder();
    if (failures)
        fprintf(stderr, "tst_screenshot: %d of %d checks failed\n", failures, checks);
    else
        fprintf(stderr, "tst_screenshot: all %d checks passed\n", checks);
    return failures ? 1 : 0;
}
