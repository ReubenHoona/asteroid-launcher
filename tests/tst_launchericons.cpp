/*
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * D60-26 (WO-10): the app icon keys of a .desktop file that AppLauncherBackground reads for the app list,
 * the grid, Recents and the launch splash (src/applauncherbackground.*), on temporary files:
 *   X-Asteroid-Center-Color  the disc (unchanged; #888888 without it)
 *   X-Eos-Glyph-Color        the glyph on the disc; white without it (the AsteroidOS look)
 *   X-Eos-Own-Icon           true: the app's own full-colour icon with its own disc, drawn as it is;
 *                            without it: own icon only for a white centre colour with no X-Eos-Glyph-Color
 *                            (the AsteroidOS Flashlight before the key). CP3A's icons are white discs with
 *                            blue glyphs, so a white disc with a glyph colour is a disc.
 * Qt Core and Gui only; no display.
 */

#include "applauncherbackground.h"

#include <QCoreApplication>
#include <QFile>
#include <QTemporaryDir>
#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)
#define CHECK_COLOR(c, hex) do { checks++; const QString got_ = (c).name(QColor::HexRgb).toUpper(); if (got_ != QStringLiteral(hex)) { \
    fprintf(stderr, "FAIL %s:%d: %s == %s (got %s)\n", __FILE__, __LINE__, #c, hex, qPrintable(got_)); failures++; } } while (0)

static QString entry(const QTemporaryDir &dir, const QString &name, const QStringList &keys)
{
    const QString path = dir.filePath(name + ".desktop");
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return path;
    QByteArray b = "[Desktop Entry]\nType=Application\nName=" + name.toUtf8() + "\nExec=/usr/bin/" + name.toUtf8() + "\n";
    for (const QString &k : keys)
        b += k.toUtf8() + "\n";
    f.write(b);
    return path;
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QTemporaryDir dir;
    CHECK(dir.isValid());
    AppLauncherBackground alb;

    // a stock-like disc and glyph (the emulator's Alarm): both keys read
    const QString alarm = entry(dir, "alarm", { "Icon=ios-alarm-outline", "X-Asteroid-Center-Color=#FFF965",
                                                "X-Asteroid-Outer-Color=#0C0500", "X-Eos-Glyph-Color=#202124" });
    CHECK_COLOR(alb.centerColor(alarm), "#FFF965");
    CHECK_COLOR(alb.glyphColor(alarm), "#202124");
    CHECK(!alb.ownIcon(alarm));

    // CP3A's look: a white disc with a blue glyph is a disc, not an own icon
    const QString phone = entry(dir, "phone", { "X-Asteroid-Center-Color=#FFFFFF", "X-Eos-Glyph-Color=#0057CC" });
    CHECK_COLOR(alb.centerColor(phone), "#FFFFFF");
    CHECK_COLOR(alb.glyphColor(phone), "#0057CC");
    CHECK(!alb.ownIcon(phone));

    // the AsteroidOS Flashlight as shipped (white centre, no eos key): its own icon, as before
    const QString torch = entry(dir, "torch", { "Icon=asteroid-flashlight", "X-Asteroid-Center-Color=#FFFFFF",
                                                "X-Asteroid-Outer-Color=#FFFFFF" });
    CHECK(alb.ownIcon(torch));
    CHECK_COLOR(alb.glyphColor(torch), "#FFFFFF");

    // the key decides, whatever the centre colour
    const QString own = entry(dir, "own", { "X-Asteroid-Center-Color=#3366AA", "X-Eos-Own-Icon=true" });
    CHECK(alb.ownIcon(own));
    const QString notOwn = entry(dir, "notown", { "X-Asteroid-Center-Color=#FFFFFF", "X-Eos-Own-Icon=false" });
    CHECK(!alb.ownIcon(notOwn));

    // an AsteroidOS entry with a coloured centre and no eos key: a white glyph on its disc, as before
    const QString settings = entry(dir, "settings", { "Icon=ios-settings-outline", "X-Asteroid-Center-Color=#0044A6" });
    CHECK_COLOR(alb.glyphColor(settings), "#FFFFFF");
    CHECK(!alb.ownIcon(settings));

    // a glyph colour that is not a colour: white
    const QString bad = entry(dir, "bad", { "X-Asteroid-Center-Color=#202124", "X-Eos-Glyph-Color=nonsense" });
    CHECK_COLOR(alb.glyphColor(bad), "#FFFFFF");
    CHECK(!alb.ownIcon(bad));

    // no file: the defaults
    const QString none = dir.filePath("missing.desktop");
    CHECK_COLOR(alb.centerColor(none), "#888888");
    CHECK_COLOR(alb.glyphColor(none), "#FFFFFF");
    CHECK(!alb.ownIcon(none));

    // read once per file (cached, as the centre colour)
    QFile::remove(alarm);
    CHECK_COLOR(alb.glyphColor(alarm), "#202124");
    CHECK(!alb.ownIcon(alarm));

    fprintf(stderr, "%d checks, %d failures\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
