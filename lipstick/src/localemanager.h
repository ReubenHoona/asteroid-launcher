/***************************************************************************
**
** Copyright (C) 2017 Florent Revest <revestflo@gmail.com>
**
** This file is part of lipstick.
**
** This library is free software; you can redistribute it and/or
** modify it under the terms of the GNU Lesser General Public
** License version 2.1 as published by the Free Software Foundation
** and appearing in the file LICENSE.LGPL included in the packaging
** of this file.
**
****************************************************************************/

#ifndef LOCALEMANAGER_H
#define LOCALEMANAGER_H

#include <QObject>
#include <QDBusAbstractAdaptor>
#include <QTranslator>

#include <homeapplication.h>

class LocaleManager : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.nemomobile.lipstick")
    Q_PROPERTY(QString changesObserver READ getEmptyString NOTIFY emptyStringChanged)
    // Counts the language changes: a binding that calls Qt.locale() (day names, number and time
    // formats) reads it to be evaluated again (locale-formats-02)
    Q_PROPERTY(int localeRevision READ localeRevision NOTIFY localeRevisionChanged)

public:
    LocaleManager(HomeApplication *app);
    QString getEmptyString();
    int localeRevision() const { return m_revision; }

public slots:
    Q_INVOKABLE void selectLocale(QString locale);

signals:
    void localeChanged();
    void emptyStringChanged();
    void localeRevisionChanged();

private:
    void loadLocaleCatalog();

    HomeApplication *m_app;
    QTranslator *m_translator;
    QTranslator *m_fallbackTranslator;
    int m_revision = 0;
};

#endif // LOCALEMANAGER_H

