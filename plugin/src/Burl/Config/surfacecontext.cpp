#include "surfacecontext.hpp"

namespace burl::config {

SurfaceContext::SurfaceContext(QObject* parent)
    : QQuickAttachedPropertyPropagator(parent) {
    initialize();
}

bool SurfaceContext::folio() const {
    return m_folio;
}

void SurfaceContext::setFolio(bool folio) {
    m_explicit = true;
    updateFolio(folio);
}

void SurfaceContext::resetFolio() {
    m_explicit = false;
    updateFolio(m_inherited);
}

void SurfaceContext::inheritFolio(bool folio) {
    m_inherited = folio;
    if (!m_explicit)
        updateFolio(folio);
}

void SurfaceContext::updateFolio(bool folio) {
    if (m_folio == folio)
        return;
    m_folio = folio;
    for (auto* child : attachedChildren()) {
        if (auto* context = qobject_cast<SurfaceContext*>(child))
            context->inheritFolio(folio);
    }
    emit folioChanged();
}

void SurfaceContext::attachedParentChange(
    QQuickAttachedPropertyPropagator* newParent, QQuickAttachedPropertyPropagator* oldParent) {
    Q_UNUSED(oldParent);
    auto* context = qobject_cast<SurfaceContext*>(newParent);
    inheritFolio(context ? context->folio() : false);
}

SurfaceContext* SurfaceContext::qmlAttachedProperties(QObject* object) {
    return new SurfaceContext(object);
}

} // namespace burl::config
