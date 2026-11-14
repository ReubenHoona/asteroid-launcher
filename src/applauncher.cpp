#include "applauncher.h"
#include "appwatcher.h"

AppLauncher::AppLauncher(QObject *parent) : QObject(parent)
{
}

bool AppLauncher::launchApp(const QString &appName)
{
    // owned by the watcher: how it ends is known (system-dialogs-misc-02); the name may
    // carry arguments, as startDetached(command) took them
    QStringList tokens = QProcess::splitCommand(QStringView(appName));
    if (tokens.isEmpty())
        return false;
    const QString program = tokens.takeFirst();
    QString key = program;
    const int slash = key.lastIndexOf(QLatin1Char('/'));
    if (slash >= 0)
        key = key.mid(slash + 1);
    return AppWatcher::instance()->launch(program, tokens, key);
}

bool AppLauncher::launchDesktopFile(const QString &desktopFile) {
    QString appName = desktopFile;
    if (appName.endsWith(".desktop")) {
        appName.chop(strlen(".desktop"));
    }
    return launchApp(appName);
}
