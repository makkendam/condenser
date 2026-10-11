#ifndef SYSTEMCHECKER_H
#define SYSTEMCHECKER_H

#include <QObject>
#include <QString>

// Finds Steam and FFmpeg at startup. Only file lookups, no processes, so it
// costs next to nothing; the QML shows a page only when something is missing.
class SystemChecker : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool steamFound READ steamFound NOTIFY checked)
    Q_PROPERTY(bool ffmpegFound READ ffmpegFound NOTIFY checked)
    Q_PROPERTY(QString steamPath READ steamPath NOTIFY checked)
    Q_PROPERTY(bool allChecksPass READ allChecksPass NOTIFY checked)
    Q_PROPERTY(bool isSteamGameMode READ isSteamGameMode CONSTANT)

public:
    explicit SystemChecker(QObject *parent = nullptr);

    bool steamFound() const { return !m_steamPath.isEmpty(); }
    bool ffmpegFound() const { return m_ffmpegFound; }
    QString steamPath() const { return m_steamPath; }
    bool allChecksPass() const { return steamFound() && m_ffmpegFound; }
    bool isSteamGameMode() const { return m_isSteamGameMode; }

public slots:
    // Runs the checks on the next event loop pass, then emits systemCheckCompleted()
    void startSystemCheck();

signals:
    void checked();
    void systemCheckCompleted();

private:
    static QString findSteamPath();
    static bool isSteamPath(const QString &path);

    QString m_steamPath;
    bool m_ffmpegFound = false;
    bool m_isSteamGameMode = false;
};

#endif // SYSTEMCHECKER_H
