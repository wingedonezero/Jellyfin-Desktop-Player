#include "ItemListModel.h"

ItemListModel::ItemListModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int ItemListModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_items.size());
}

QVariant ItemListModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size())
        return {};
    if (role == ItemRole)
        return m_items.at(index.row());
    return {};
}

QHash<int, QByteArray> ItemListModel::roleNames() const
{
    return { { ItemRole, "itemData" } };
}

void ItemListModel::setItems(const QVariantList &items)
{
    beginResetModel();
    m_items = items;
    endResetModel();
    Q_EMIT countChanged();
}

void ItemListModel::appendItems(const QVariantList &items)
{
    if (items.isEmpty())
        return;
    beginInsertRows(QModelIndex(), int(m_items.size()), int(m_items.size() + items.size()) - 1);
    m_items += items;
    endInsertRows();
    Q_EMIT countChanged();
}

void ItemListModel::updateItems(const QVariantList &items)
{
    const int common = qMin(int(m_items.size()), int(items.size()));
    if (common > 0) {
        for (int i = 0; i < common; ++i)
            m_items[i] = items.at(i);
        Q_EMIT dataChanged(index(0), index(common - 1), { ItemRole });
    }
    if (items.size() > m_items.size()) {
        beginInsertRows(QModelIndex(), common, int(items.size()) - 1);
        for (qsizetype i = common; i < items.size(); ++i)
            m_items.append(items.at(i));
        endInsertRows();
        Q_EMIT countChanged();
    } else if (items.size() < m_items.size()) {
        beginRemoveRows(QModelIndex(), int(items.size()), int(m_items.size()) - 1);
        m_items.resize(items.size());
        endRemoveRows();
        Q_EMIT countChanged();
    }
}

void ItemListModel::clear()
{
    if (m_items.isEmpty())
        return;
    beginResetModel();
    m_items.clear();
    endResetModel();
    Q_EMIT countChanged();
}

QVariantMap ItemListModel::get(int row) const
{
    if (row < 0 || row >= m_items.size())
        return {};
    return m_items.at(row).toMap();
}
