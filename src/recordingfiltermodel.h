#ifndef RECORDINGFILTERMODEL_H
#define RECORDINGFILTERMODEL_H

#include <QSortFilterProxyModel>

// Shows either the saved clips or the full background recordings of a
// SteamRecordingManager, so each gets its own tab
class RecordingFilterModel : public QSortFilterProxyModel
{
    Q_OBJECT

    Q_PROPERTY(bool backgroundRecordings READ backgroundRecordings WRITE setBackgroundRecordings NOTIFY backgroundRecordingsChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    explicit RecordingFilterModel(QObject *parent = nullptr);

    bool backgroundRecordings() const { return m_backgroundRecordings; }
    void setBackgroundRecordings(bool backgroundRecordings);
    int count() const { return rowCount(); }

signals:
    void backgroundRecordingsChanged();
    void countChanged();

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;

private:
    bool m_backgroundRecordings;
};

#endif // RECORDINGFILTERMODEL_H
