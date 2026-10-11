#ifndef GAMEINFO_H
#define GAMEINFO_H

#include <QObject>
#include <QString>

class GameInfo : public QObject
{
    Q_OBJECT
    
    Q_PROPERTY(QString appId READ appId WRITE setAppId NOTIFY appIdChanged)
    Q_PROPERTY(QString name READ name WRITE setName NOTIFY nameChanged)
    Q_PROPERTY(bool isValid READ isValid NOTIFY isValidChanged)

public:
    explicit GameInfo(QObject *parent = nullptr);
    explicit GameInfo(const QString &appId, QObject *parent = nullptr);

    // Property getters
    QString appId() const { return m_appId; }
    QString name() const { return m_name; }
    bool isValid() const { return !m_appId.isEmpty() && !m_name.isEmpty(); }

    // Property setters
    void setAppId(const QString &appId);
    void setName(const QString &name);

    // Static methods for loading game info
    static GameInfo* fromAppId(const QString &appId, const QString &steamPath, QObject *parent = nullptr);
    // Name of a non-Steam game shortcut (from userdata/*/config/shortcuts.vdf), empty if unknown
    static QString shortcutName(quint32 shortcutAppId, const QString &steamPath);

    // Utility methods
    Q_INVOKABLE bool loadFromAcf(const QString &acfFilePath);

signals:
    void appIdChanged();
    void nameChanged();
    void isValidChanged();

private:
    // Helper methods for parsing ACF files
    QString findAcfFilePath(const QString &appId, const QString &steamPath) const;

    // Member variables
    QString m_appId;
    QString m_name;
};

#endif // GAMEINFO_H