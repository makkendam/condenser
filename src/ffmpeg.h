#ifndef FFMPEG_H
#define FFMPEG_H

#include <QCoreApplication>
#include <QStandardPaths>
#include <QString>

// The FFmpeg executable all exports and thumbnails run: one shipped next to
// the app (as a Windows build would bundle it), otherwise ffmpeg from PATH
inline QString ffmpegProgram()
{
    static const QString program = [] {
        const QString bundled = QStandardPaths::findExecutable(QStringLiteral("ffmpeg"),
                                                               {QCoreApplication::applicationDirPath()});
        return bundled.isEmpty() ? QStringLiteral("ffmpeg") : bundled;
    }();
    return program;
}

#endif // FFMPEG_H
