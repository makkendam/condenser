#ifndef THUMBNAILPROVIDER_H
#define THUMBNAILPROVIDER_H

#include <QObject>
#include <QSet>
#include <QString>
#include <QUrl>
#include <QList>

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

public:
    explicit ThumbnailProvider(QObject *parent = nullptr);
    ~ThumbnailProvider() override;

    QString segmentPath() const { return m_segmentPath; }
    void setSegmentPath(const QString &path);
    int revision() const { return m_revision; }

    // Closest available thumbnail for a playback position (empty URL if none
    // yet); also asks for the exact one if it doesn't exist
    Q_INVOKABLE QUrl thumbnailAt(qint64 positionMs);

    // Delete cached thumbnails of recordings that no longer exist
    static void pruneCache();

signals:
    void segmentPathChanged();
    void revisionChanged();

private:
    void reset();
    void readChunkLayout();
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

    QSet<int> m_available;   // chunks with a thumbnail on disk
    QSet<int> m_inProgress;
    QSet<int> m_failed;      // don't retry these on every mouse move
    int m_hoverRequest = -1; // most recent chunk asked for by hovering
    QList<int> m_backgroundQueue;
    QList<QProcess *> m_processes;
};

#endif // THUMBNAILPROVIDER_H
