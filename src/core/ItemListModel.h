#pragma once

#include <QAbstractListModel>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// List model for the browse grids. A plain QVariantList model resets the view
// on every reassignment — all delegates torn down, scroll position lost. This
// model lets pages APPEND (infinite scroll) and lets watched-state refreshes
// UPDATE rows in place, so delegates and the scroll position survive both.
// Single role: delegates keep reading `modelData` (single-role alias), so the
// same delegate works against this model and plain JS arrays.
class ItemListModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    explicit ItemListModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return int(m_items.size()); }

    Q_INVOKABLE void setItems(const QVariantList &items);    // full reset (sort/filter change)
    Q_INVOKABLE void appendItems(const QVariantList &items); // next page (infinite scroll)
    Q_INVOKABLE void updateItems(const QVariantList &items); // in-place refresh (user-data)
    Q_INVOKABLE void clear();
    Q_INVOKABLE QVariantMap get(int row) const;

Q_SIGNALS:
    void countChanged();

private:
    static constexpr int ItemRole = Qt::UserRole + 1;
    QVariantList m_items;
};
