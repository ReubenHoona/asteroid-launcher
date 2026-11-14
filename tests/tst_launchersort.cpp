/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The order of the Wear app list (lipstick/src/components/launchersortmodel.h):
 * collator order of the labels, case-insensitive and numeric, equal labels by
 * path, a new app lands in its place, a removed one leaves a gap, a label that
 * changes moves, and the order does not depend on the source order.
 * Core only (see CMakeLists.txt in this directory, LAUNCHER_TESTS).
 */

#include "launchersortmodel.h"

#include <QAbstractListModel>
#include <QCoreApplication>
#include <QStringList>
#include <cstdio>

static int failures = 0;
static int checks = 0;
#define CHECK(cond) do { checks++; if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)
#define CHECK_STR(a, b) do { checks++; const QString x_ = (a), y_ = (b); if (x_ != y_) { fprintf(stderr, "FAIL %s:%d: %s == %s (got '%s' want '%s')\n", __FILE__, __LINE__, #a, #b, qPrintable(x_), qPrintable(y_)); failures++; } } while (0)

class Item : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString title READ title WRITE setTitle)
    Q_PROPERTY(QString filePath READ filePath)
public:
    Item(const QString &t, const QString &p, QObject *parent = nullptr) : QObject(parent), m_title(t), m_path(p) {}
    QString title() const { return m_title; }
    void setTitle(const QString &t) { m_title = t; }
    QString filePath() const { return m_path; }
private:
    QString m_title, m_path;
};

/* the shape of QObjectListModel: one role "object" (Qt::UserRole + 1) */
class SourceModel : public QAbstractListModel
{
    Q_OBJECT
public:
    QList<Item *> items;
    int rowCount(const QModelIndex &p = QModelIndex()) const override { return p.isValid() ? 0 : items.size(); }
    QVariant data(const QModelIndex &i, int role) const override
    {
        if (role == Qt::UserRole + 1 && i.row() >= 0 && i.row() < items.size())
            return QVariant::fromValue<QObject *>(items.at(i.row()));
        return QVariant();
    }
    QHash<int, QByteArray> roleNames() const override { return {{Qt::UserRole + 1, "object"}}; }
    void add(const QString &t, const QString &p)
    {
        beginInsertRows(QModelIndex(), items.size(), items.size());
        items << new Item(t, p, this);
        endInsertRows();
    }
    void removeAt(int r)
    {
        beginRemoveRows(QModelIndex(), r, r);
        delete items.takeAt(r);
        endRemoveRows();
    }
    void move(int from, int to)
    {
        beginMoveRows(QModelIndex(), from, from, QModelIndex(), to > from ? to + 1 : to);
        items.move(from, to);
        endMoveRows();
    }
    void retitle(int r, const QString &t)
    {
        items.at(r)->setTitle(t);
        emit dataChanged(index(r), index(r));
    }
};

static QString titles(const LauncherSortModel &m)
{
    QStringList l;
    for (int i = 0; i < m.rowCount(); i++)
        l << m.get(i)->property("title").toString();
    return l.join("|");
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    // the host Qt has no ICU: only the C collation is there, which is all the checks need
    QLocale::setDefault(QLocale::c());

    /* the plain comparison */
    QCollator c = EosLauncherSort::makeCollator(QLocale::c());
    CHECK(EosLauncherSort::less(c, "apple", "/a", "Banana", "/b"));       // case-insensitive
    CHECK(!EosLauncherSort::less(c, "Banana", "/b", "apple", "/a"));
    CHECK(EosLauncherSort::less(c, "App 2", "/2", "App 10", "/10"));      // numeric
    CHECK(EosLauncherSort::less(c, "Clock", "/a", "Clock", "/b"));        // equal label: by path
    CHECK(!EosLauncherSort::less(c, "Clock", "/b", "Clock", "/a"));
    CHECK(!EosLauncherSort::less(c, "Clock", "/a", "Clock", "/a"));       // strict

    SourceModel src;
    /* the source order is the AsteroidOS one (saved positions): not alphabetical */
    const QStringList in = {"Timer", "alarm clock", "Weather", "Calendar", "Settings", "stopwatch", "Music", "App 10", "App 2"};
    for (int i = 0; i < in.size(); i++)
        src.add(in.at(i), QString("/usr/share/applications/%1.desktop").arg(i));

    LauncherSortModel m;
    m.setSourceModel(&src);
    CHECK(m.itemCount() == 9);
    QStringList want = {"alarm clock", "App 2", "App 10", "Calendar", "Music", "Settings", "stopwatch", "Timer", "Weather"};
    CHECK_STR(titles(m), want.join("|"));

    /* a new app lands in its place, not at the end */
    src.add("Contacts", "/usr/share/applications/new.desktop");
    want.insert(4, "Contacts");
    CHECK_STR(titles(m), want.join("|"));
    CHECK(m.itemCount() == 10);

    /* the AsteroidOS reorder (the source moves) does not change this model */
    src.move(0, 5);
    CHECK_STR(titles(m), want.join("|"));

    /* a removal */
    for (int i = 0; i < src.items.size(); i++) {
        if (src.items.at(i)->title() == "Music") {
            src.removeAt(i);
            break;
        }
    }
    want.removeAll("Music");
    CHECK_STR(titles(m), want.join("|"));
    CHECK(m.itemCount() == 9);

    /* a label that changes moves the row (the language changed) */
    for (int i = 0; i < src.items.size(); i++) {
        if (src.items.at(i)->title() == "Weather") {
            src.retitle(i, "Aaa");
            break;
        }
    }
    CHECK_STR(m.get(0)->property("title").toString(), "Aaa");
    CHECK_STR(m.get(1)->property("title").toString(), "alarm clock");
    CHECK(m.get(99) == nullptr);

    /* digits compare as numbers, leading zeros do not count, a label that is a prefix comes first */
    CHECK(EosLauncherSort::naturalCompare(c, "App 9", "App 10") < 0);
    CHECK(EosLauncherSort::naturalCompare(c, "App 007", "App 7") == 0);
    CHECK(EosLauncherSort::naturalCompare(c, "App", "App 1") < 0);
    CHECK(EosLauncherSort::naturalCompare(c, "2048", "10000") < 0);
    CHECK(EosLauncherSort::naturalCompare(c, "Alarm", "alarm") == 0);

    /* resort() makes the collator again and keeps the order */
    m.resort();
    CHECK_STR(m.get(0)->property("title").toString(), "Aaa");
    CHECK(m.itemCount() == 9);

    /* an empty or missing source */
    LauncherSortModel m3;
    CHECK(m3.itemCount() == 0);
    CHECK(m3.get(0) == nullptr);

    printf("%d checks, %d failures\n", checks, failures);
    return failures ? 1 : 0;
}

#include "tst_launchersort.moc"
