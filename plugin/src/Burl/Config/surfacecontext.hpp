#pragma once

#include <qquickattachedpropertypropagator.h>
#include <qqmlengine.h>

namespace burl::config {

class SurfaceContext : public QQuickAttachedPropertyPropagator {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("")
    QML_ATTACHED(SurfaceContext)
    Q_PROPERTY(bool folio READ folio WRITE setFolio RESET resetFolio NOTIFY folioChanged)

public:
    explicit SurfaceContext(QObject* parent = nullptr);
    [[nodiscard]] bool folio() const;
    void setFolio(bool folio);
    Q_INVOKABLE void resetFolio();
    static SurfaceContext* qmlAttachedProperties(QObject* object);

signals:
    void folioChanged();

protected:
    void attachedParentChange(
        QQuickAttachedPropertyPropagator* newParent, QQuickAttachedPropertyPropagator* oldParent) override;

private:
    void inheritFolio(bool folio);
    void updateFolio(bool folio);

    bool m_explicit = false;
    bool m_inherited = false;
    bool m_folio = false;
};

} // namespace burl::config
