#include "systemchecker.h"
#include "ffmpeg.h"

#include <QDir>
#include <QFileInfo>
#include <QSettings>
#include <QStandardPaths>
#include <QTimer>

SystemChecker::SystemChecker(QObject *parent)
    : QObject(parent)
    // Set by Steam in SteamOS game mode
    , m_isSteamGameMode(qEnvironmentVariable("SteamDeck") == QLatin1String("1"))
{
}

void SystemChecker::startSystemCheck()
{
    QTimer::singleShot(0, this, [this]() {
        m_steamPath = findSteamPath();
        const QString ffmpeg = ffmpegProgram();
        m_ffmpegFound = QFileInfo(ffmpeg).isExecutable() || !QStandardPaths::findExecutable(ffmpeg).isEmpty();
        emit checked();
        emit systemCheckCompleted();
    });
}

QString SystemChecker::findSteamPath()
{
    QStringList candidates;
#ifdef Q_OS_WIN
    for (const char *key : {"HKEY_LOCAL_MACHINE\\SOFTWARE\\Wow6432Node\\Valve\\Steam",
                            "HKEY_LOCAL_MACHINE\\SOFTWARE\\Valve\\Steam"}) {
        const QString installPath = QSettings(QLatin1String(key), QSettings::NativeFormat).value("InstallPath").toString();
        if (!installPath.isEmpty()) {
            candidates << QDir::fromNativeSeparators(installPath);
        }
    }
    candidates << QStringLiteral("C:/Program Files (x86)/Steam") << QStringLiteral("C:/Program Files/Steam");
#else
    const QString home = QDir::homePath();
    candidates << home + QStringLiteral("/.steam/steam")
               << home + QStringLiteral("/.local/share/Steam")
               << home + QStringLiteral("/.var/app/com.valvesoftware.Steam/.local/share/Steam");
#endif
    for (const QString &path : std::as_const(candidates)) {
        if (isSteamPath(path)) {
            return path;
        }
    }
    return QString();
}

bool SystemChecker::isSteamPath(const QString &path)
{
    const QDir dir(path);
#ifdef Q_OS_WIN
    const QString launcher = QStringLiteral("steam.exe");
#else
    const QString launcher = QStringLiteral("steam.sh");
#endif
    return dir.exists(QStringLiteral("userdata")) && dir.exists(QStringLiteral("steamapps")) && dir.exists(launcher);
}
