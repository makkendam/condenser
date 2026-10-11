#include "recordingfiltermodel.h"
#include "recordingclip.h"
#include "steamrecordingmanager.h"

RecordingFilterModel::RecordingFilterModel(QObject *parent)
    : QSortFilterProxyModel(parent)
    , m_backgroundRecordings(false)
{
    connect(this, &QAbstractItemModel::rowsInserted, this, &RecordingFilterModel::countChanged);
    connect(this, &QAbstractItemModel::rowsRemoved, this, &RecordingFilterModel::countChanged);
    connect(this, &QAbstractItemModel::modelReset, this, &RecordingFilterModel::countChanged);
    connect(this, &QAbstractItemModel::layoutChanged, this, &RecordingFilterModel::countChanged);
}

void RecordingFilterModel::setBackgroundRecordings(bool backgroundRecordings)
{
    if (m_backgroundRecordings != backgroundRecordings) {
#if QT_VERSION >= QT_VERSION_CHECK(6, 9, 0)
        beginFilterChange();
        m_backgroundRecordings = backgroundRecordings;
        endFilterChange();
#else
        m_backgroundRecordings = backgroundRecordings;
        invalidateFilter();
#endif
        emit backgroundRecordingsChanged();
        emit countChanged();
    }
}

bool RecordingFilterModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    const QModelIndex index = sourceModel()->index(sourceRow, 0, sourceParent);
    const auto *clip = index.data(SteamRecordingManager::ClipRole).value<RecordingClip *>();
    return clip && clip->isBackgroundRecording() == m_backgroundRecordings;
}
