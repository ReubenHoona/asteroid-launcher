/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef FACEPREVIEWS_H
#define FACEPREVIEWS_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QUrl>

/*
 * The cached previews of the watch face picker (W2-launcher-face-picker,
 * face-interaction-19): one PNG per favourite, ~/.cache/asteroid-launcher/
 * face-previews/<id>.png, written from QML (QQuickItemGrabResult.saveToFile)
 * when the picker opens, which cannot make a directory. This class makes it
 * and names the files; it reads nothing and runs nothing in the
 * background. Context property `facePreviews` of the launcher.
 */
class FacePreviews : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString dir READ dir CONSTANT)

public:
    explicit FacePreviews(const QString &dir = QString(), QObject *parent = nullptr);

    QString dir() const { return m_dir; }

    //! The file to write the preview of favourite  id to (the folder is made
    //! now); empty when the id is no file name or the folder cannot be made.
    Q_INVOKABLE QString path(const QString &id) const;
    //! The file URL of a preview that exists, else an empty URL.
    Q_INVOKABLE QUrl url(const QString &id) const;
    Q_INVOKABLE bool exists(const QString &id) const;
    //! A favourite was removed: its file goes.
    Q_INVOKABLE void remove(const QString &id);
    //! Every preview but those of  ids goes (stale files of removed favourites).
    Q_INVOKABLE int keepOnly(const QStringList &ids);

    //! The file name of an id (the id's characters a-z, 0-9, - and _; others are not allowed): empty if invalid
    static QString fileName(const QString &id);

private:
    QString m_dir;
};

#endif // FACEPREVIEWS_H
