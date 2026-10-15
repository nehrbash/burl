#include "notify.hpp"

#include "util.hpp"

using Qt::StringLiterals::operator""_s;

namespace burl {

void notifyCritical(const QString& summary, const QString& body) {
    try {
        runProcess(u"notify-send"_s, {u"-a"_s, u"burl"_s, u"-u"_s, u"critical"_s, summary, body});
    } catch (const Error&) {
    }
}

} // namespace burl
