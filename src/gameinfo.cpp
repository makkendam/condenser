#include "gameinfo.h"
#include "qvdfparser.h"
#include <QFile>
#include <QTextStream>
#include <QRegularExpression>
#include <QDir>
#include <QFileInfo>
#include <QDebug>
#include <QLocale>
#include <functional>

GameInfo::GameInfo(QObject *parent)
    : QObject(parent)
{
}

GameInfo::GameInfo(const QString &appId, QObject *parent)
    : QObject(parent)
    , m_appId(appId)
{
}

void GameInfo::setAppId(const QString &appId)
{
    if (m_appId != appId) {
        m_appId = appId;
        emit appIdChanged();
        emit isValidChanged();
    }
}

void GameInfo::setName(const QString &name)
{
    if (m_name != name) {
        m_name = name;
        emit nameChanged();
        emit isValidChanged();
    }
}

GameInfo* GameInfo::fromAppId(const QString &appId, const QString &steamPath, QObject *parent)
{
    // Recordings of non-Steam games use a 64-bit game ID with the shortcut's
    // app ID in the upper 32 bits, e.g. 17800632051548815360 = 4144532618 << 32 | 0x02000000
    bool isNumber = false;
    const quint64 gameId = appId.toULongLong(&isNumber);
    if (isNumber && gameId > 0xFFFFFFFFull) {
        const QString name = shortcutName(quint32(gameId >> 32), steamPath);
        if (name.isEmpty()) {
            return nullptr;
        }
        GameInfo *gameInfo = new GameInfo(appId, parent);
        gameInfo->setName(name);
        return gameInfo;
    }

    GameInfo *gameInfo = new GameInfo(appId, parent);
    
    QString acfFilePath = gameInfo->findAcfFilePath(appId, steamPath);
    if (!acfFilePath.isEmpty() && gameInfo->loadFromAcf(acfFilePath)) {
        return gameInfo;
    } else {
        delete gameInfo;
        return nullptr;
    }
}

// shortcuts.vdf is binary VDF: a type byte (0 = nested map, 1 = string,
// 2 = int32, 8 = end of map), a NUL terminated key, then the value
namespace {
struct BinaryVdfReader {
    const QByteArray &data;
    qsizetype pos = 0;

    bool readCString(QByteArray &out)
    {
        const qsizetype end = data.indexOf('\0', pos);
        if (end < 0) {
            return false;
        }
        out = data.mid(pos, end - pos);
        pos = end + 1;
        return true;
    }

    // Walks a map; calls onEntry(appId, name) for every map that has both
    bool readMap(const std::function<void(quint32, const QString &)> &onEntry, int depth = 0)
    {
        bool haveAppId = false;
        quint32 appId = 0;
        QString name;
        while (pos < data.size()) {
            const char type = data.at(pos++);
            if (type == 0x08) {
                if (haveAppId && !name.isEmpty()) {
                    onEntry(appId, name);
                }
                return true;
            }
            QByteArray key;
            if (!readCString(key)) {
                return false;
            }
            if (type == 0x00) {
                if (depth > 8 || !readMap(onEntry, depth + 1)) {
                    return false;
                }
            } else if (type == 0x01) {
                QByteArray value;
                if (!readCString(value)) {
                    return false;
                }
                if (key.compare("appname", Qt::CaseInsensitive) == 0) {
                    name = QString::fromUtf8(value);
                }
            } else if (type == 0x02) {
                if (pos + 4 > data.size()) {
                    return false;
                }
                const quint32 value = quint8(data.at(pos)) | quint8(data.at(pos + 1)) << 8
                                    | quint8(data.at(pos + 2)) << 16 | quint32(quint8(data.at(pos + 3))) << 24;
                pos += 4;
                if (key.compare("appid", Qt::CaseInsensitive) == 0) {
                    appId = value;
                    haveAppId = true;
                }
            } else {
                return false; // Other types don't occur in shortcuts.vdf
            }
        }
        return false;
    }
};
} // namespace

QString GameInfo::shortcutName(quint32 shortcutAppId, const QString &steamPath)
{
    const QDir userDataDir(QDir(steamPath).absoluteFilePath(QStringLiteral("userdata")));
    const QStringList users = userDataDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &user : users) {
        QFile file(userDataDir.absoluteFilePath(user + QStringLiteral("/config/shortcuts.vdf")));
        if (!file.open(QIODevice::ReadOnly)) {
            continue;
        }
        const QByteArray data = file.readAll();
        QString found;
        BinaryVdfReader reader{data};
        reader.readMap([&](quint32 appId, const QString &name) {
            if (appId == shortcutAppId) {
                found = name;
            }
        });
        if (!found.isEmpty()) {
            return found;
        }
    }
    return QString();
}

bool GameInfo::loadFromAcf(const QString &acfFilePath)
{
    QVdfParser parser;
    auto root = parser.parseFile(acfFilePath);
    
    if (!root) {
        qWarning() << "Failed to parse ACF file:" << acfFilePath;
        qWarning() << "Parser error:" << parser.lastError();
        return false;
    }

    // Parse the ACF content using VDF parser
    QString appId = root->stringAttribute("appid");
    QString name = root->stringAttribute("name");

    // Validate required fields
    if (appId.isEmpty() || name.isEmpty()) {
        qWarning() << "ACF file missing required fields (appid or name):" << acfFilePath;
        return false;
    }

    // Set the parsed values
    setAppId(appId);
    setName(name);

    qDebug() << "Successfully loaded game info for:" << name << "(AppID:" << appId << ")";
    return true;
}

QString GameInfo::findAcfFilePath(const QString &appId, const QString &steamPath) const
{
    if (appId.isEmpty() || steamPath.isEmpty()) {
        return QString();
    }

    // Prefer reading libraryfolders.vdf to enumerate all Steam libraries
    const QString libraryFoldersPath = steamPath + "/config/libraryfolders.vdf";
    QVdfParser parser;
    auto libraries = parser.parseFile(libraryFoldersPath);

    const QString acfFileName = QString("appmanifest_%1.acf").arg(appId);

    if (libraries && libraries->name() == QLatin1String("libraryfolders")) {
        const auto libraryEntries = libraries->children();
        for (const auto *entry : libraryEntries) {
            if (!entry) continue;
            const QString libraryPath = entry->stringAttribute("path");
            if (libraryPath.isEmpty()) continue;

            const QString normalizedLibraryPath = QDir::fromNativeSeparators(libraryPath);
            QDir steamAppsDir(normalizedLibraryPath + "/steamapps");
            const QString acfFilePath = steamAppsDir.absoluteFilePath(acfFileName);

            if (QFileInfo::exists(acfFilePath)) {
                return acfFilePath;
            }

            // Optional: if apps list indicates presence, still try path
            if (auto apps = entry->child("apps")) {
                if (apps->hasAttribute(appId)) {
                    if (QFileInfo::exists(acfFilePath)) {
                        return acfFilePath;
                    }
                }
            }
        }
    } else {
        qWarning() << "Failed to parse libraryfolders.vdf:" << libraryFoldersPath << "error:" << parser.lastError();
    }

    // Fallback: check default steamapps under steamPath
    QDir defaultSteamAppsDir(steamPath + "/steamapps");
    if (defaultSteamAppsDir.exists()) {
        const QString fallbackAcfPath = defaultSteamAppsDir.absoluteFilePath(acfFileName);
        if (QFileInfo::exists(fallbackAcfPath)) {
            return fallbackAcfPath;
        }
    } else {
        qWarning() << "Default Steamapps directory does not exist:" << defaultSteamAppsDir.absolutePath();
    }

    qWarning() << "ACF file not found for AppID" << appId << "in any library defined in" << libraryFoldersPath;
    return QString();
}
