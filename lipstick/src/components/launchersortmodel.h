/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef LAUNCHERSORTMODEL_H
#define LAUNCHERSORTMODEL_H

#include <QCollator>
#include <QLocale>
#include <QSortFilterProxyModel>

/*
 * The order of the Wear app list and grid (audit app-launcher-22): the
 * installed launcher activities alphabetically by label with the collator of
 * the current locale (stock SysUI moq.java:2659-2665), ignoring the saved
 * LauncherOrder of the AsteroidOS styles; a new app lands in its place, and
 * nothing is saved. The order is case-insensitive and numeric ("App 2"
 * before "App 10"), see naturalCompare.
 *
 * A proxy over the LauncherModel (the roles of QObjectListModel: "object"
 * holds the LauncherItem), so the AsteroidOS styles keep the model and its
 * saved order. QML: LauncherSortModel { sourceModel: launcherModel }. The
 * rows re-sort by themselves when the source adds, removes, moves or changes
 * a row (dynamicSortFilter); resort() makes the collator again and sorts
 * after a language change (the labels come from the locale's catalog).
 *
 * Apps left out (FP-L3): the desktop ids in the dconf list
 * /org/asteroidos/launcher/hidden-apps (Settings > Apps & notifications >
 * App info > Hide app, CR-19), and the Assistant while
 * /org/asteroidos/assistant/enabled is off (CR-15). QML sets hiddenApps and
 * assistantEnabled from the two keys; the rows leave and come back by
 * themselves (the list, the grid and Recents are built from this model's
 * apps; Recents applies EosLauncherSort.hidden's rule too, recents.js).
 *
 * The comparison is EosLauncherSort::less, the exclusion EosLauncherSort::hidden,
 * plain C++ for the host test tests/tst_launchersort.cpp.
 */
namespace EosLauncherSort {

/* Natural order of two labels: case folded (so "alarm" and "Alarm" are one
 * letter, as a case-insensitive collator treats them) and numeric (a run of
 * digits compares as a number: "App 2" before "App 10"), the letters by the
 * collator of the locale. Done here and not with QCollator's own case and
 * numeric modes so that it is the same with and without ICU (the host test
 * has none; the image has ICU 77). */
inline int naturalCompare(const QCollator &collator, const QString &a, const QString &b)
{
    const QString x = a.toCaseFolded();
    const QString y = b.toCaseFolded();
    int i = 0, j = 0;
    while (i < x.size() && j < y.size()) {
        const bool dx = x.at(i).isDigit();
        const bool dy = y.at(j).isDigit();
        int ie = i, je = j;
        while (ie < x.size() && x.at(ie).isDigit() == dx)
            ie++;
        while (je < y.size() && y.at(je).isDigit() == dy)
            je++;
        QString cx = x.mid(i, ie - i);
        QString cy = y.mid(j, je - j);
        if (dx && dy) {
            int zx = 0, zy = 0;
            while (zx < cx.size() - 1 && cx.at(zx) == QLatin1Char('0'))
                zx++;
            while (zy < cy.size() - 1 && cy.at(zy) == QLatin1Char('0'))
                zy++;
            cx = cx.mid(zx);
            cy = cy.mid(zy);
            if (cx.size() != cy.size())
                return cx.size() < cy.size() ? -1 : 1;
            if (cx != cy)
                return cx < cy ? -1 : 1;
        } else {
            const int c = collator.compare(cx, cy);
            if (c != 0)
                return c < 0 ? -1 : 1;
        }
        i = ie;
        j = je;
    }
    if (i < x.size())
        return 1;
    if (j < y.size())
        return -1;
    return 0;
}

/* a before b: natural order of the titles; equal titles by file path, so
 * the order is the same on every run */
inline bool less(const QCollator &collator, const QString &titleA, const QString &pathA,
                 const QString &titleB, const QString &pathB)
{
    const int c = naturalCompare(collator, titleA, titleB);
    if (c != 0)
        return c < 0;
    return pathA < pathB;
}

/* "/usr/share/applications/asteroid-timer.desktop" -> "asteroid-timer" */
inline QString desktopId(const QString &filePath)
{
    QString name = filePath.mid(filePath.lastIndexOf(QLatin1Char('/')) + 1);
    if (name.endsWith(QLatin1String(".desktop")) && name.size() > 8)
        name.chop(8);
    return name;
}

/* the app of the Assistant: its entry and tile are hidden while assistant/enabled is off */
inline QString assistantId()
{
    return QStringLiteral("asteroid-assistant");
}

/* whether the app stays out of the list: its desktop id is in hidden-apps (a list entry may
 * carry the ".desktop" suffix), or it is the Assistant and the Assistant is off */
inline bool hidden(const QStringList &hiddenApps, bool assistantEnabled, const QString &filePath)
{
    const QString id = desktopId(filePath);
    if (id.isEmpty())
        return false;
    if (!assistantEnabled && id == assistantId())
        return true;
    for (const QString &entry : hiddenApps) {
        const QString e = entry.trimmed();
        if (e == id || e == id + QLatin1String(".desktop"))
            return true;
    }
    return false;
}

inline QCollator makeCollator(const QLocale &locale)
{
    return QCollator(locale);
}

}

class LauncherSortModel : public QSortFilterProxyModel
{
    Q_OBJECT
    /* the role of the source that holds the item (a QObject with title and filePath) */
    Q_PROPERTY(QString objectRole READ objectRole WRITE setObjectRole NOTIFY objectRoleChanged)
    Q_PROPERTY(int itemCount READ itemCount NOTIFY itemCountChanged)
    /* the desktop ids left out (dconf /org/asteroidos/launcher/hidden-apps, CR-19) */
    Q_PROPERTY(QStringList hiddenApps READ hiddenApps WRITE setHiddenApps NOTIFY hiddenAppsChanged)
    /* false: the Assistant is left out too (dconf /org/asteroidos/assistant/enabled, CR-15) */
    Q_PROPERTY(bool assistantEnabled READ assistantEnabled WRITE setAssistantEnabled NOTIFY assistantEnabledChanged)

public:
    explicit LauncherSortModel(QObject *parent = nullptr);

    QString objectRole() const { return m_objectRole; }
    void setObjectRole(const QString &role);
    int itemCount() const { return rowCount(); }
    QStringList hiddenApps() const { return m_hiddenApps; }
    void setHiddenApps(const QStringList &apps);
    bool assistantEnabled() const { return m_assistantEnabled; }
    void setAssistantEnabled(bool enabled);

    /* make the collator again (the language changed) and sort */
    Q_INVOKABLE void resort();
    /* the item of a sorted row, or null */
    Q_INVOKABLE QObject *get(int row) const;

    void setSourceModel(QAbstractItemModel *model) override;

signals:
    void objectRoleChanged();
    void itemCountChanged();
    void hiddenAppsChanged();
    void assistantEnabledChanged();

protected:
    bool lessThan(const QModelIndex &left, const QModelIndex &right) const override;
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;

private:
    QObject *itemOf(const QModelIndex &sourceIndex) const;
    int roleId() const;

    QString m_objectRole = QStringLiteral("object");
    QCollator m_collator;
    QStringList m_hiddenApps;
    bool m_assistantEnabled = true;
};

#endif // LAUNCHERSORTMODEL_H
