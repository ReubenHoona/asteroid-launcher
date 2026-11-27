/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef EOSCATALOGUES_H
#define EOSCATALOGUES_H

#include <QDir>
#include <QLocale>
#include <QString>
#include <QStringList>

/*
 * The nearest catalogue of a language for a region the image has none for (R5 C-04). The watch takes the
 * phone's language with the phone's region (de_AT: Austrian formats), as stock's PhoneSettingLocaleListener
 * does (it applies the phone's locale when the watch supports its language), but the image ships the
 * catalogue of de_DE only, and QTranslator::load(QLocale) looks for de_AT and then de. This gives the
 * language's catalogue for its main region (QLocale(language): de -> de_DE) when there is one, else the first
 * of its other regions by name; "" when the language has none (the text stays English). The same rule as
 * qml-asteroid's AsteroidApp::installTranslators.
 */
namespace EosCatalogues {

inline QString nearest(const QString &name, const QString &directory, const QLocale &locale)
{
    if (locale.language() == QLocale::C || locale.language() == QLocale::AnyLanguage)
        return QString();
    const QString lang = QLocale::languageToCode(locale.language());
    const QDir dir(directory);
    const QStringList found = dir.entryList({ name + QLatin1Char('.') + lang + QStringLiteral("_*.qm") },
                                            QDir::Files, QDir::Name);
    if (found.isEmpty())
        return QString();
    const QString main = name + QLatin1Char('.') + QLocale(lang).name() + QStringLiteral(".qm");
    return dir.filePath(found.contains(main) ? main : found.first());
}

} // namespace EosCatalogues

#endif // EOSCATALOGUES_H
