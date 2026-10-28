/*
 * SPDX-FileCopyrightText: 2026 Timo Könnecke <github.com/moWerk>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#ifndef WATCHFACERELOADER_H
#define WATCHFACERELOADER_H

#include <QObject>
#include <QFileSystemWatcher>
#include <QString>
#include <QHash>
#include <QUrl>

class QQmlEngine;
class QQuickItem;

/*!
 * \brief Drops the QML component cache when a watchface is added at runtime.
 *
 * Qt's QQmlTypeLoader reads a directory's listing the first time it resolves a
 * file there and then reuses that cached listing for the life of the process,
 * with no invalidation. A watchface downloaded into the user watchface folder
 * after that first read is therefore invisible to the loader ("File name case
 * mismatch") until the cache is dropped. This watches the folder and clears the
 * component cache when it changes so newly installed watchfaces load live,
 * without restarting the launcher.
 */
class WatchfaceReloader : public QObject
{
    Q_OBJECT
public:
    explicit WatchfaceReloader(QQmlEngine *engine, QObject *parent = nullptr);

    //! Whether the watchface at  face shows seconds (a seconds hand or
    //! digits): the launcher's clock then ticks every second, else every
    //! minute, so a face that shows hours and minutes draws one frame a
    //! minute. Read from the face's source (getSeconds(), an "ss" format),
    //! once per file; true when the file cannot be read.
    Q_INVOKABLE bool usesSeconds(const QUrl &face);

    //! Whether the seconds of the loaded watchface  item (from  face)
    //! are on screen now: faces name their seconds items second* (secondHand,
    //! secondText, secondSVG...) and hide them in nightstand, ambient or 12 h
    //! modes; a hidden one still redrew the screen every second. True when
    //! one such item is visible, false when all are hidden, and
    //! usesSeconds(face) when the face names none.
    Q_INVOKABLE bool secondsShown(QQuickItem *item, const QUrl &face);

signals:
    //! Emitted after the cache is cleared so QML can re-trigger the watchface
    //! loader against the freshly re-read directory.
    void reloadNeeded();

private slots:
    void onDirectoryChanged(const QString &path);

private:
    QQmlEngine *m_engine;
    QFileSystemWatcher m_watcher;
    QString m_dir;
    QHash<QString, bool> m_usesSeconds;
};

#endif // WATCHFACERELOADER_H
