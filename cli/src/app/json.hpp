#pragma once

#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace burl {

// JSON value that keeps object member order; the colour maps are written to
// config files in the order the generator emits them.
class JsonValue {
public:
    using Members = std::vector<std::pair<std::string, JsonValue>>;

    JsonValue() = default;

    [[nodiscard]] static JsonValue string(std::string value);
    [[nodiscard]] static JsonValue object();

    [[nodiscard]] bool isString() const { return m_type == Type::String; }
    [[nodiscard]] bool isObject() const { return m_type == Type::Object; }

    [[nodiscard]] const std::string& asString() const { return m_string; }
    [[nodiscard]] const Members& members() const { return m_members; }

    [[nodiscard]] const JsonValue* find(const std::string& key) const;
    void set(std::string key, JsonValue value);

    // False for null, false, zero, and empty strings, arrays and objects.
    [[nodiscard]] bool truthy() const;

private:
    class Parser;
    enum class Type { Null, Bool, Number, String, Array, Object };

    void dump(std::string& out) const;
    friend JsonValue parseJson(std::string_view text);
    friend std::string dumpJson(const JsonValue& value);

    Type m_type = Type::Null;
    bool m_bool = false;
    double m_number = 0;
    std::string m_string;
    Members m_members;
    std::vector<JsonValue> m_items;
};

class JsonError : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

// Throws JsonError.
[[nodiscard]] JsonValue parseJson(std::string_view text);

// ", " and ": " separators, ASCII only; numbers are locale independent.
[[nodiscard]] std::string dumpJson(const JsonValue& value);

} // namespace burl
