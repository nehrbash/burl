#include "json.hpp"

#include <cctype>
#include <charconv>
#include <cstdio>
#include <qstring.h>

namespace burl {

JsonValue JsonValue::string(std::string value) {
    JsonValue result;
    result.m_type = Type::String;
    result.m_string = std::move(value);
    return result;
}

JsonValue JsonValue::object() {
    JsonValue result;
    result.m_type = Type::Object;
    return result;
}

const JsonValue* JsonValue::find(const std::string& key) const {
    for (const auto& [name, value] : m_members) {
        if (name == key) {
            return &value;
        }
    }
    return nullptr;
}

void JsonValue::set(std::string key, JsonValue value) {
    for (auto& [name, existing] : m_members) {
        if (name == key) {
            existing = std::move(value);
            return;
        }
    }
    m_members.emplace_back(std::move(key), std::move(value));
}

bool JsonValue::truthy() const {
    switch (m_type) {
    case Type::Null:
        return false;
    case Type::Bool:
        return m_bool;
    case Type::Number:
        return m_number < 0 || m_number > 0;
    case Type::String:
        return !m_string.empty();
    case Type::Array:
        return !m_items.empty();
    case Type::Object:
        return !m_members.empty();
    }
    return false;
}

namespace {

constexpr int maxDepth = 256;

} // namespace

class JsonValue::Parser {
public:
    explicit Parser(std::string_view text)
        : m_text(text) {}

    JsonValue parseDocument() {
        auto value = parseValue(0);
        skipSpace();
        if (m_pos != m_text.size()) {
            fail("extra data");
        }
        return value;
    }

private:
    static JsonValue scalar(Type type, bool value) {
        JsonValue result;
        result.m_type = type;
        result.m_bool = value;
        return result;
    }

    [[noreturn]] void fail(const char* message) const {
        throw JsonError(std::string(message) + " at offset " + std::to_string(m_pos));
    }

    void skipSpace() {
        while (m_pos < m_text.size()
               && (m_text[m_pos] == ' ' || m_text[m_pos] == '\t' || m_text[m_pos] == '\n' || m_text[m_pos] == '\r')) {
            m_pos++;
        }
    }

    bool consume(std::string_view literal) {
        if (m_text.substr(m_pos, literal.size()) == literal) {
            m_pos += literal.size();
            return true;
        }
        return false;
    }

    JsonValue parseValue(int depth) {
        if (depth > maxDepth) {
            fail("nesting too deep");
        }
        skipSpace();
        if (m_pos >= m_text.size()) {
            fail("unexpected end of input");
        }
        switch (m_text[m_pos]) {
        case '{':
            return parseObject(depth);
        case '[':
            return parseArray(depth);
        case '"':
            return JsonValue::string(parseString());
        case 't':
            if (consume("true")) {
                return scalar(Type::Bool, true);
            }
            break;
        case 'f':
            if (consume("false")) {
                return scalar(Type::Bool, false);
            }
            break;
        case 'n':
            if (consume("null")) {
                return {};
            }
            break;
        default:
            return parseNumber();
        }
        fail("invalid literal");
    }

    JsonValue parseNumber() {
        const auto start = m_pos;
        while (m_pos < m_text.size()
               && (std::isdigit(static_cast<unsigned char>(m_text[m_pos])) || m_text[m_pos] == '-'
                   || m_text[m_pos] == '+' || m_text[m_pos] == '.' || m_text[m_pos] == 'e' || m_text[m_pos] == 'E')) {
            m_pos++;
        }
        if (m_pos == start) {
            fail("unexpected character");
        }
        const auto* first = m_text.data() + start;
        const auto* last = m_text.data() + m_pos;
        double value = 0;
        const auto [end, error] = std::from_chars(first, last, value);
        if (error != std::errc() || end != last) {
            m_pos = start;
            fail("invalid number");
        }
        JsonValue result;
        result.m_type = Type::Number;
        result.m_number = value;
        return result;
    }

    unsigned parseHex4() {
        if (m_pos + 4 > m_text.size()) {
            fail("truncated escape");
        }
        unsigned value = 0;
        for (int i = 0; i < 4; i++) {
            const auto c = m_text[m_pos++];
            value <<= 4;
            if (c >= '0' && c <= '9') {
                value |= static_cast<unsigned>(c - '0');
            } else if (c >= 'a' && c <= 'f') {
                value |= static_cast<unsigned>(c - 'a' + 10);
            } else if (c >= 'A' && c <= 'F') {
                value |= static_cast<unsigned>(c - 'A' + 10);
            } else {
                fail("invalid escape");
            }
        }
        return value;
    }

    std::string parseString() {
        m_pos++; // opening quote
        QString result;
        std::string raw;
        const auto flush = [&] {
            if (!raw.empty()) {
                result += QString::fromUtf8(raw.data(), static_cast<qsizetype>(raw.size()));
                raw.clear();
            }
        };
        while (true) {
            if (m_pos >= m_text.size()) {
                fail("unterminated string");
            }
            const auto c = m_text[m_pos++];
            if (c == '"') {
                break;
            }
            if (c != '\\') {
                raw.push_back(c);
                continue;
            }
            flush();
            if (m_pos >= m_text.size()) {
                fail("unterminated string");
            }
            const auto escape = m_text[m_pos++];
            switch (escape) {
            case '"':
            case '\\':
            case '/':
                result += QChar::fromLatin1(escape);
                break;
            case 'b':
                result += u'\b';
                break;
            case 'f':
                result += u'\f';
                break;
            case 'n':
                result += u'\n';
                break;
            case 'r':
                result += u'\r';
                break;
            case 't':
                result += u'\t';
                break;
            case 'u':
                result += QChar(static_cast<char16_t>(parseHex4()));
                break;
            default:
                fail("invalid escape");
            }
        }
        flush();
        return result.toStdString();
    }

    JsonValue parseArray(int depth) {
        m_pos++;
        JsonValue result;
        result.m_type = Type::Array;
        skipSpace();
        if (m_pos < m_text.size() && m_text[m_pos] == ']') {
            m_pos++;
            return result;
        }
        while (true) {
            result.m_items.push_back(parseValue(depth + 1));
            skipSpace();
            if (m_pos >= m_text.size()) {
                fail("unterminated array");
            }
            const auto c = m_text[m_pos++];
            if (c == ']') {
                return result;
            }
            if (c != ',') {
                m_pos--;
                fail("expected ',' or ']'");
            }
        }
    }

    JsonValue parseObject(int depth) {
        m_pos++;
        auto result = JsonValue::object();
        skipSpace();
        if (m_pos < m_text.size() && m_text[m_pos] == '}') {
            m_pos++;
            return result;
        }
        while (true) {
            skipSpace();
            if (m_pos >= m_text.size() || m_text[m_pos] != '"') {
                fail("expected property name");
            }
            auto key = parseString();
            skipSpace();
            if (m_pos >= m_text.size() || m_text[m_pos] != ':') {
                fail("expected ':'");
            }
            m_pos++;
            result.set(std::move(key), parseValue(depth + 1));
            skipSpace();
            if (m_pos >= m_text.size()) {
                fail("unterminated object");
            }
            const auto c = m_text[m_pos++];
            if (c == '}') {
                return result;
            }
            if (c != ',') {
                m_pos--;
                fail("expected ',' or '}'");
            }
        }
    }

    std::string_view m_text;
    std::size_t m_pos = 0;
};

namespace {

void dumpString(std::string& out, const std::string& value) {
    out.push_back('"');
    const auto text = QString::fromStdString(value);
    for (const auto unit : text) {
        const auto code = unit.unicode();
        switch (code) {
        case u'"':
            out += "\\\"";
            break;
        case u'\\':
            out += "\\\\";
            break;
        case u'\n':
            out += "\\n";
            break;
        case u'\r':
            out += "\\r";
            break;
        case u'\t':
            out += "\\t";
            break;
        case u'\b':
            out += "\\b";
            break;
        case u'\f':
            out += "\\f";
            break;
        default:
            if (code >= 0x20 && code < 0x7f) {
                out.push_back(static_cast<char>(code));
            } else {
                char buffer[8];
                std::snprintf(buffer, sizeof(buffer), "\\u%04x", static_cast<unsigned>(code));
                out += buffer;
            }
        }
    }
    out.push_back('"');
}

} // namespace

void JsonValue::dump(std::string& out) const {
    switch (m_type) {
    case Type::Null:
        out += "null";
        break;
    case Type::Bool:
        out += m_bool ? "true" : "false";
        break;
    case Type::Number: {
        char buffer[40];
        const auto result = std::to_chars(buffer, buffer + sizeof(buffer), m_number);
        out.append(buffer, result.ptr);
        break;
    }
    case Type::String:
        dumpString(out, m_string);
        break;
    case Type::Array: {
        out.push_back('[');
        bool first = true;
        for (const auto& item : m_items) {
            if (!first) {
                out += ", ";
            }
            first = false;
            item.dump(out);
        }
        out.push_back(']');
        break;
    }
    case Type::Object: {
        out.push_back('{');
        bool first = true;
        for (const auto& [key, member] : m_members) {
            if (!first) {
                out += ", ";
            }
            first = false;
            dumpString(out, key);
            out += ": ";
            member.dump(out);
        }
        out.push_back('}');
        break;
    }
    }
}

JsonValue parseJson(std::string_view text) {
    return JsonValue::Parser(text).parseDocument();
}

std::string dumpJson(const JsonValue& value) {
    std::string out;
    value.dump(out);
    return out;
}

} // namespace burl
