#ifndef THUMBNAILPROVIDER_H
#define THUMBNAILPROVIDER_H

#include <QObject>
#include <QSet>
#include <QString>
#include <QUrl>
#include <QList>
#include <QVariantList>

#include <functional>

class QProcess;

// Preview images for hovering the timeline. Steam stores a recording as
// ~3 second DASH chunks that each start with a keyframe, so one thumbnail per
// chunk is cheap: feed FFmpeg the init segment plus that chunk and grab the
// first frame. The chunk under the mouse is made first; the rest of the
// recording is filled in the background. Thumbnails are cached on disk.
class ThumbnailProvider : public QObject
{
    Q_OBJECT

    // A recording segment directory (holding session.mpd and the chunks)
    Q_PROPERTY(QString segmentPath READ segmentPath WRITE setSegmentPath NOTIFY segmentPathChanged)
    // Bumped whenever a new thumbnail is available, so QML bindings re-query
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)
    // Stretches where the picture doesn't move, as [{startMs, endMs}]. Steam
    // keeps recording audio but repeats the last frame while the game isn't
    // presenting frames (e.g. alt-tabbed); such chunks encode to identical sizes.
    Q_PROPERTY(QVariantList frozenRanges READ frozenRanges NOTIFY segmentPathChanged)

public:
    explicit ThumbnailProvider(QObject *parent = nullptr);
    ~ThumbnailProvider() override;

    QString segmentPath() const { return m_segmentPath; }
    void setSegmentPath(const QString &path);
    int revision() const { return m_revision; }
    QVariantList frozenRanges() const { return m_frozenRanges; }

    // Closest available thumbnail for a playback position (empty URL if none
    // yet); also asks for the exact one if it doesn't exist
    Q_INVOKABLE QUrl thumbnailAt(qint64 positionMs);

    // Delete cached thumbnails of recordings that no longer exist
    static void pruneCache();

    // Cover image for a recording segment, for the recordings list (Steam only
    // saves one for clips). Returns the cached file right away if there is one;
    // otherwise returns an empty string, makes it in the background and calls
    // `done` with its path, unless `context` is gone by then.
    static QString coverFor(const QString &segmentPath, QObject *context,
                            const std::function<void(const QString &)> &done);

    // Cache directory for a segment's images (created on demand)
    static QString cacheDirFor(const QString &segmentPath);

signals:
    void segmentPathChanged();
    void revisionChanged();

private:
    void reset();
    void readChunkLayout();
    void findFrozenRanges();
    QString thumbnailFile(int chunk) const;
    QString chunkFile(int chunk) const;
    void request(int chunk);
    void startNext();
    void onFinished(QProcess *process, int chunk);

    QString m_segmentPath;
    QString m_cacheDir;
    int m_revision = 0;

    // Chunk layout, from the manifest's SegmentTemplate
    int m_firstChunk = 1;
    int m_chunkCount = 0;
    qint64 m_chunkDurationMs = 3000;

    QVariantList m_frozenRanges;

    QSet<int> m_available;   // chunks with a thumbnail on disk
    QSet<int> m_inProgress;
    QSet<int> m_failed;      // don't retry these on every mouse move
    int m_hoverRequest = -1; // most recent chunk asked for by hovering
    QList<int> m_backgroundQueue;
    QList<QProcess *> m_processes;
};

#endif // THUMBNAILPROVIDER_H
