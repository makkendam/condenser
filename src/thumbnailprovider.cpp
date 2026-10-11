#include "thumbnailprovider.h"
#include "ffmpeg.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QPointer>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>

namespace {
// FFmpeg processes running at the same time
const int MaxParallel = 2;
// Background thumbnails roughly every this many ms; hovering fills the gaps
const qint64 BackgroundIntervalMs = 12000;
// Thumbnail width; height follows the aspect ratio
const char *ThumbnailScale = "scale=240:-2";
// Identical chunk sizes in a row before a stretch counts as frozen
const int MinFrozenChunks = 3;
// File in each cache directory naming the segment it belongs to
const char *SourceFileName = "source";

QString cacheRoot()
{
    return QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/thumbnails");
}

// The Steam recordings directory a segment lives in: the part before
// /video/bg_... or /clips/clip_.../video/...
QString recordingsRoot(const QString &segmentPath)
{
    static const QRegularExpression rootRe(QStringLiteral("^(.*)/(video|clips)/[^/]+"));
    return rootRe.match(segmentPath).captured(1);
}
}

ThumbnailProvider::ThumbnailProvider(QObject *parent)
    : QObject(parent)
{
}

ThumbnailProvider::~ThumbnailProvider()
{
    reset();
}

void ThumbnailProvider::setSegmentPath(const QString &path)
{
    if (m_segmentPath == path) {
        return;
    }
    reset();
    m_segmentPath = path;

    if (m_segmentPath.isEmpty()) {
        emit segmentPathChanged();
        return;
    }

    m_cacheDir = cacheDirFor(m_segmentPath);

    readChunkLayout();
    findFrozenRanges();
    emit segmentPathChanged();

    const QStringList cached = QDir(m_cacheDir).entryList({QStringLiteral("*.jpg")}, QDir::Files);
    for (const QString &name : cached) {
        bool ok = false;
        const int chunk = QFileInfo(name).completeBaseName().toInt(&ok);
        if (ok) {
            m_available.insert(chunk);
        }
    }

    const int step = int(qMax<qint64>(1, BackgroundIntervalMs / m_chunkDurationMs));
    for (int chunk = m_firstChunk; chunk < m_firstChunk + m_chunkCount; chunk += step) {
        if (!m_available.contains(chunk)) {
            m_backgroundQueue.append(chunk);
        }
    }

    m_revision++;
    emit revisionChanged();
    startNext();
}

QString ThumbnailProvider::cacheDirFor(const QString &segmentPath)
{
    // One cache directory per segment; clips have their own chunk numbering,
    // so key on the full path rather than the directory name
    const QByteArray key = QCryptographicHash::hash(segmentPath.toUtf8(), QCryptographicHash::Sha1).toHex().left(16);
    const QString dir = cacheRoot() + QLatin1Char('/') + QString::fromLatin1(key);
    QDir().mkpath(dir);
    QFile source(dir + QLatin1Char('/') + QLatin1String(SourceFileName));
    if (!source.exists() && source.open(QIODevice::WriteOnly)) {
        source.write(segmentPath.toUtf8());
    }
    return dir;
}

namespace {
// Covers are made one at a time, so a long list of recordings doesn't
// start a crowd of FFmpeg processes at startup
struct CoverJob {
    QString segmentPath;
    QString coverPath;
    QPointer<QObject> context;
    std::function<void(const QString &)> done;
    int attempt = 0;
};
// Where in the recording to look, tried in turn while the frame comes out (nearly) black
const double CoverPositions[] = {0.25, 0.5, 0.75};
// A black 320px JPEG is about 1–2 KB, a real frame 8 KB or more
const qint64 MinCoverBytes = 4000;
QList<CoverJob> coverQueue;
bool coverRunning = false;

// A chunk worth showing: `position` of the way in (past loading screens), and
// not part of a frozen stretch, where neighbouring chunks have identical sizes
QString pickCoverChunk(const QString &segmentPath, double position)
{
    QDir dir(segmentPath);
    const QStringList chunks = dir.entryList({QStringLiteral("chunk-stream0-*.m4s")}, QDir::Files, QDir::Name);
    if (chunks.isEmpty()) {
        return QString();
    }
    auto sizeAt = [&](int i) { return QFileInfo(dir.absoluteFilePath(chunks.at(i))).size(); };
    const int start = qMin(int(chunks.size() * position), int(chunks.size()) - 1);
    for (int i = qMax(1, start); i < chunks.size() - 1; ++i) {
        const qint64 size = sizeAt(i);
        if (size != sizeAt(i - 1) && size != sizeAt(i + 1)) {
            return dir.absoluteFilePath(chunks.at(i));
        }
    }
    return dir.absoluteFilePath(chunks.at(start));
}

void runNextCover()
{
    while (!coverRunning && !coverQueue.isEmpty()) {
        const CoverJob job = coverQueue.takeFirst();
        if (!job.context) {
            continue;
        }
        QFile init(QDir(job.segmentPath).absoluteFilePath(QStringLiteral("init-stream0.m4s")));
        QFile media(pickCoverChunk(job.segmentPath, CoverPositions[job.attempt]));
        if (!init.open(QIODevice::ReadOnly) || !media.open(QIODevice::ReadOnly)) {
            continue;
        }

        coverRunning = true;
        auto *process = new QProcess();
        QObject::connect(process, &QProcess::finished, process, [process, job]() {
            process->deleteLater();
            coverRunning = false;
            const qint64 size = QFileInfo(job.coverPath).size();
            const bool ok = process->exitStatus() == QProcess::NormalExit && process->exitCode() == 0 && size > 0;
            const int attempts = int(sizeof(CoverPositions) / sizeof(CoverPositions[0]));
            if (ok && size < MinCoverBytes && job.attempt + 1 < attempts) {
                // Try further in; the dark one stays on disk in case all are dark.
                // Only the final image is reported, as QML caches images by path.
                CoverJob retry = job;
                retry.attempt++;
                coverQueue.prepend(retry);
            } else if (ok && job.context) {
                job.done(job.coverPath);
            }
            runNextCover();
        });
        QObject::connect(process, &QProcess::errorOccurred, process, [process](QProcess::ProcessError error) {
            if (error == QProcess::FailedToStart) {
                process->deleteLater();
                coverRunning = false;
                coverQueue.clear(); // No FFmpeg: no point trying the rest
            }
        });
        process->start(ffmpegProgram(), {
            QStringLiteral("-v"), QStringLiteral("error"), QStringLiteral("-y"),
            // Only decode the keyframe the chunk starts with, not the whole chunk
            QStringLiteral("-skip_frame"), QStringLiteral("nokey"),
            QStringLiteral("-f"), QStringLiteral("mp4"), QStringLiteral("-i"), QStringLiteral("pipe:0"),
            QStringLiteral("-frames:v"), QStringLiteral("1"),
            QStringLiteral("-vf"), QStringLiteral("scale=320:-2"),
            QStringLiteral("-q:v"), QStringLiteral("4"),
            job.coverPath,
        });
        process->write(init.readAll());
        process->write(media.readAll());
        process->closeWriteChannel();
    }
}
}

QString ThumbnailProvider::coverFor(const QString &segmentPath, QObject *context,
                                    const std::function<void(const QString &)> &done)
{
    const QString coverPath = cacheDirFor(segmentPath) + QStringLiteral("/cover.jpg");
    if (QFileInfo(coverPath).size() > 0) {
        return coverPath;
    }
    coverQueue.append({segmentPath, coverPath, context, done});
    runNextCover();
    return QString();
}

void ThumbnailProvider::reset()
{
    for (QProcess *process : std::as_const(m_processes)) {
        process->disconnect(this);
        process->kill();
        process->waitForFinished(1000);
        process->deleteLater();
    }
    m_processes.clear();
    m_available.clear();
    m_inProgress.clear();
    m_failed.clear();
    m_backgroundQueue.clear();
    m_hoverRequest = -1;
    m_chunkCount = 0;
    m_frozenRanges.clear();
    m_cacheDir.clear();
}

void ThumbnailProvider::readChunkLayout()
{
    QDir dir(m_segmentPath);
    m_chunkCount = dir.entryList({QStringLiteral("chunk-stream0-*.m4s")}, QDir::Files).size();

    // <SegmentTemplate timescale="1000000" duration="3000000" ... startNumber="1"/>
    QFile mpd(dir.absoluteFilePath(QStringLiteral("session.mpd")));
    if (!mpd.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return;
    }
    const QString content = QString::fromUtf8(mpd.readAll());
    static const QRegularExpression templateRe(QStringLiteral("<SegmentTemplate\\b[^>]*>"));
    const QString tag = templateRe.match(content).captured(0);
    auto attribute = [&tag](const char *name) {
        const QRegularExpression re(QStringLiteral("\\b%1=\"(\\d+)\"").arg(QLatin1String(name)));
        return re.match(tag).captured(1).toLongLong();
    };
    const qint64 timescale = attribute("timescale");
    const qint64 duration = attribute("duration");
    if (timescale > 0 && duration > 0) {
        m_chunkDurationMs = qMax<qint64>(1, duration * 1000 / timescale);
    }
    const qint64 startNumber = attribute("startNumber");
    if (startNumber > 0) {
        m_firstChunk = int(startNumber);
    }
}

void ThumbnailProvider::findFrozenRanges()
{
    auto addRange = [this](int runStart, int runLength) {
        if (runLength < MinFrozenChunks) {
            return;
        }
        QVariantMap range;
        range[QStringLiteral("startMs")] = qint64(runStart - m_firstChunk) * m_chunkDurationMs;
        range[QStringLiteral("endMs")] = qint64(runStart + runLength - m_firstChunk) * m_chunkDurationMs;
        m_frozenRanges.append(range);
    };

    qint64 previousSize = -1;
    int runStart = m_firstChunk;
    for (int chunk = m_firstChunk; chunk < m_firstChunk + m_chunkCount; ++chunk) {
        const qint64 size = QFileInfo(chunkFile(chunk)).size();
        if (size <= 0 || size != previousSize) {
            addRange(runStart, chunk - runStart);
            runStart = chunk;
        }
        previousSize = size;
    }
    addRange(runStart, m_firstChunk + m_chunkCount - runStart);
}

void ThumbnailProvider::pruneCache()
{
    QDir root(cacheRoot());
    const QStringList dirs = root.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &name : dirs) {
        QDir dir(root.absoluteFilePath(name));
        QFile source(dir.absoluteFilePath(QLatin1String(SourceFileName)));
        if (source.open(QIODevice::ReadOnly)) {
            const QString segmentPath = QString::fromUtf8(source.readAll());
            source.close();
            if (QFileInfo::exists(segmentPath)) {
                continue;
            }
            // Recordings folder itself unreachable (e.g. unmounted disk): keep the cache
            const QString recordings = recordingsRoot(segmentPath);
            if (recordings.isEmpty() || !QFileInfo::exists(recordings)) {
                continue;
            }
        }
        dir.removeRecursively();
    }
}

QString ThumbnailProvider::thumbnailFile(int chunk) const
{
    return m_cacheDir + QLatin1Char('/') + QString::number(chunk) + QStringLiteral(".jpg");
}

QString ThumbnailProvider::chunkFile(int chunk) const
{
    return QDir(m_segmentPath).absoluteFilePath(
        QStringLiteral("chunk-stream0-%1.m4s").arg(chunk, 5, 10, QLatin1Char('0')));
}

QUrl ThumbnailProvider::thumbnailAt(qint64 positionMs)
{
    if (m_chunkCount <= 0 || positionMs < 0) {
        return QUrl();
    }

    const int chunk = qBound(m_firstChunk, m_firstChunk + int(positionMs / m_chunkDurationMs),
                             m_firstChunk + m_chunkCount - 1);
    if (m_available.contains(chunk)) {
        return QUrl::fromLocalFile(thumbnailFile(chunk));
    }

    request(chunk);

    // Meanwhile show the nearest one we have
    for (int distance = 1; distance < m_chunkCount; ++distance) {
        if (m_available.contains(chunk - distance)) {
            return QUrl::fromLocalFile(thumbnailFile(chunk - distance));
        }
        if (m_available.contains(chunk + distance)) {
            return QUrl::fromLocalFile(thumbnailFile(chunk + distance));
        }
        if (distance > 20) {
            break; // Too far away to be a useful stand-in
        }
    }
    return QUrl();
}

void ThumbnailProvider::request(int chunk)
{
    // Only the latest hover position matters; older ones are dropped
    m_hoverRequest = chunk;
    startNext();
}

void ThumbnailProvider::startNext()
{
    while (m_processes.size() < MaxParallel) {
        int chunk = -1;
        if (m_hoverRequest >= 0) {
            chunk = m_hoverRequest;
            m_hoverRequest = -1;
        } else if (!m_backgroundQueue.isEmpty()) {
            chunk = m_backgroundQueue.takeFirst();
        } else {
            return;
        }
        if (m_available.contains(chunk) || m_inProgress.contains(chunk) || m_failed.contains(chunk)) {
            continue;
        }

        QFile init(QDir(m_segmentPath).absoluteFilePath(QStringLiteral("init-stream0.m4s")));
        QFile media(chunkFile(chunk));
        if (!init.open(QIODevice::ReadOnly) || !media.open(QIODevice::ReadOnly)) {
            m_failed.insert(chunk);
            continue;
        }

        auto *process = new QProcess(this);
        m_processes.append(process);
        m_inProgress.insert(chunk);
        connect(process, &QProcess::finished, this, [this, process, chunk]() { onFinished(process, chunk); });
        connect(process, &QProcess::errorOccurred, this, [this, process, chunk](QProcess::ProcessError error) {
            if (error == QProcess::FailedToStart) {
                onFinished(process, chunk);
            }
        });

        process->start(ffmpegProgram(), {
            QStringLiteral("-v"), QStringLiteral("error"), QStringLiteral("-y"),
            // Only decode the keyframe the chunk starts with, not the whole chunk
            QStringLiteral("-skip_frame"), QStringLiteral("nokey"),
            QStringLiteral("-f"), QStringLiteral("mp4"), QStringLiteral("-i"), QStringLiteral("pipe:0"),
            QStringLiteral("-frames:v"), QStringLiteral("1"),
            QStringLiteral("-vf"), QLatin1String(ThumbnailScale),
            QStringLiteral("-q:v"), QStringLiteral("5"),
            thumbnailFile(chunk),
        });
        process->write(init.readAll());
        process->write(media.readAll());
        process->closeWriteChannel();
    }
}

void ThumbnailProvider::onFinished(QProcess *process, int chunk)
{
    if (!m_processes.removeOne(process)) {
        return; // Already handled (e.g. errorOccurred followed by finished)
    }
    process->deleteLater();
    m_inProgress.remove(chunk);

    if (process->exitStatus() == QProcess::NormalExit && process->exitCode() == 0
        && QFileInfo(thumbnailFile(chunk)).size() > 0) {
        m_available.insert(chunk);
        m_revision++;
        emit revisionChanged();
    } else {
        m_failed.insert(chunk);
    }
    startNext();
}
