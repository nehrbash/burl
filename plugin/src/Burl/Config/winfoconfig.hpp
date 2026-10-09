#pragma once

#include "configobject.hpp"

namespace burl::config {

// WInfoConfig has no serialized properties (serializer returns {})
class WInfoConfig : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

public:
    explicit WInfoConfig(QObject* parent = nullptr)
        : ConfigObject(parent) {}
};

} // namespace burl::config
