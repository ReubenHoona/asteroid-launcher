/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

// The cached previews of the face picker (src/facepreviews.h): file names, the folder, remove, prune.
//   dir is a temporary folder; nothing outside it is touched.

#include "facepreviews.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static void touch(const QString &p)
{
    QFile f(p);
    (void)f.open(QIODevice::WriteOnly);
    f.write("png");
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QTemporaryDir tmp;
    CHECK(tmp.isValid());
    const QString dir = tmp.path() + QStringLiteral("/a/b/face-previews");
    FacePreviews fp(dir);

    // the folder does not exist until a path is asked for
    CHECK(!QDir(dir).exists());
    CHECK(fp.dir() == dir);
    const QString p = fp.path(QStringLiteral("010-analog-aviator"));
    CHECK(p == dir + QStringLiteral("/010-analog-aviator.png"));
    CHECK(QDir(dir).exists());

    // ids that are no file names get none
    CHECK(fp.path(QString()).isEmpty());
    CHECK(fp.path(QStringLiteral("../x")).isEmpty());
    CHECK(fp.path(QStringLiteral("a/b")).isEmpty());
    CHECK(fp.path(QStringLiteral("Upper")).isEmpty());
    CHECK(fp.path(QStringLiteral("with space")).isEmpty());
    CHECK(fp.path(QString(121, QLatin1Char('a'))).isEmpty());
    CHECK(!fp.path(QString(120, QLatin1Char('a'))).isEmpty());
    CHECK(FacePreviews::fileName(QStringLiteral("a_b-2")) == QStringLiteral("a_b-2.png"));

    // a preview is there when its file has content
    CHECK(!fp.exists(QStringLiteral("010-analog-aviator")));
    CHECK(fp.url(QStringLiteral("010-analog-aviator")).isEmpty());
    touch(p);
    CHECK(fp.exists(QStringLiteral("010-analog-aviator")));
    CHECK(fp.url(QStringLiteral("010-analog-aviator")) == QUrl::fromLocalFile(p));
    QFile empty(dir + QStringLiteral("/empty.png"));
    (void)empty.open(QIODevice::WriteOnly);
    empty.close();
    CHECK(!fp.exists(QStringLiteral("empty")));

    // remove
    fp.remove(QStringLiteral("010-analog-aviator"));
    CHECK(!fp.exists(QStringLiteral("010-analog-aviator")));
    fp.remove(QStringLiteral("../../escape"));   // no file name: nothing happens

    // keepOnly: the stale ones go, others (not png) stay
    touch(dir + QStringLiteral("/x1.png"));
    touch(dir + QStringLiteral("/x2.png"));
    touch(dir + QStringLiteral("/x3.png"));
    touch(dir + QStringLiteral("/note.txt"));
    CHECK(fp.keepOnly({ QStringLiteral("x2"), QStringLiteral("nothere") }) == 3);   // x1, x3, empty
    CHECK(fp.exists(QStringLiteral("x2")));
    CHECK(!fp.exists(QStringLiteral("x1")));
    CHECK(QFile::exists(dir + QStringLiteral("/note.txt")));

    // the default folder is the cache folder of the launcher
    qputenv("XDG_CACHE_HOME", tmp.path().toUtf8());
    FacePreviews def;
    CHECK(def.dir() == tmp.path() + QStringLiteral("/asteroid-launcher/face-previews"));

    printf("%d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}
