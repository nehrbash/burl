#pragma once

#include "colour/colour.hpp"
#include "json.hpp"
#include "paths.hpp"

#include <optional>
#include <qstringlist.h>

namespace burl {

using Colours = colour::Colours;

JsonValue coloursToJson(const Colours& colours);

extern const QStringList schemeVariants;

QStringList schemeNames(const Paths& paths);
QStringList schemeFlavours(const Paths& paths, const QString& name);
QStringList schemeModes(const Paths& paths, const QString& name, const QString& flavour);

Colours readColoursFromFile(const QString& path);

class Scheme {
public:
    Scheme(const Paths& paths, QString name, QString flavour, QString mode, QString variant, Colours colours);

    // The saved scheme, or nocturne when none is saved. Never writes.
    [[nodiscard]] static Scheme load(const Paths& paths);

    [[nodiscard]] const QString& name() const { return m_name; }
    [[nodiscard]] const QString& flavour() const { return m_flavour; }
    [[nodiscard]] const QString& mode() const { return m_mode; }
    [[nodiscard]] const QString& variant() const { return m_variant; }
    [[nodiscard]] const Colours& colours() const { return m_colours; }

    void setNotify(bool notify) { m_notify = notify; }

    // Change a field without regenerating the colours.
    void setMode(const QString& mode);
    void setVariant(const QString& variant);
    void select(const QString& name, const QString& flavour, const QString& mode, const QString& variant);
    void setRandom();

    // Throws Error when a dynamic scheme has no wallpaper to draw from.
    void refreshColours();
    // As refreshColours, drawing a dynamic scheme from `image`.
    void refreshColoursFrom(const QString& image);
    void updateColours();
    void save() const;

    [[nodiscard]] QString coloursPath() const;
    [[nodiscard]] QString summary() const;

private:
    void checkFlavour();
    void checkMode();

    const Paths& m_paths;
    QString m_name;
    QString m_flavour;
    QString m_mode;
    QString m_variant;
    Colours m_colours;
    bool m_notify = false;
};

} // namespace burl
