/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "launchersortmodel.h"

LauncherSortModel::LauncherSortModel(QObject *parent) : QSortFilterProxyModel(parent),
    m_collator(EosLauncherSort::makeCollator(QLocale()))
{
    setDynamicSortFilter(true);
    sort(0);
    connect(this, &QAbstractItemModel::rowsInserted, this, &LauncherSortModel::itemCountChanged);
    connect(this, &QAbstractItemModel::rowsRemoved, this, &LauncherSortModel::itemCountChanged);
    connect(this, &QAbstractItemModel::modelReset, this, &LauncherSortModel::itemCountChanged);
}

void LauncherSortModel::setObjectRole(const QString &role)
{
    if (role == m_objectRole)
        return;
    m_objectRole = role;
    emit objectRoleChanged();
    invalidate();
}

void LauncherSortModel::setSourceModel(QAbstractItemModel *model)
{
    QSortFilterProxyModel::setSourceModel(model);
    sort(0);
}

int LauncherSortModel::roleId() const
{
    QAbstractItemModel *src = sourceModel();
    return src ? src->roleNames().key(m_objectRole.toUtf8(), -1) : -1;
}

QObject *LauncherSortModel::itemOf(const QModelIndex &sourceIndex) const
{
    const int role = roleId();
    if (role < 0 || !sourceIndex.isValid())
        return nullptr;
    return sourceIndex.data(role).value<QObject *>();
}

QObject *LauncherSortModel::get(int row) const
{
    return itemOf(mapToSource(index(row, 0)));
}

void LauncherSortModel::resort()
{
    m_collator = EosLauncherSort::makeCollator(QLocale());
    invalidate();
    sort(0);
}

bool LauncherSortModel::lessThan(const QModelIndex &left, const QModelIndex &right) const
{
    QObject *a = itemOf(left);
    QObject *b = itemOf(right);
    if (!a || !b)
        return a == nullptr && b != nullptr;
    return EosLauncherSort::less(m_collator,
                                 a->property("title").toString(), a->property("filePath").toString(),
                                 b->property("title").toString(), b->property("filePath").toString());
}
