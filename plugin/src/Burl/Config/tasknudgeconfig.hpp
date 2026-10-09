#pragma once

#include "configobject.hpp"

namespace burl::config {

// TaskNudge: the full-screen clock-in / break overlay (modules/tasknudge).
//
// It is deliberately intrusive — it takes the whole screen and keyboard focus —
// so how often it may re-appear is the difference between a useful nudge and
// something that interrupts you every few minutes. Dismissing it (Escape or a
// click outside the card) defers it for `deferMinutes'.
class TasknudgeConfig : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    // Minutes to stay quiet after a dismissal, and before the FIRST nag of a
    // session (the overlay starts deferred). 0 disables re-arming entirely, so
    // a dismissal is final until you clock in or restart the shell.
    CONFIG_GLOBAL_PROPERTY(int, deferMinutes, 30)
    // Master switch, independent of Emacs's own `clock-in-reminders' pref:
    // that one is about whether reminders are wanted at all, this one lets the
    // overlay be disabled without touching task state.
    CONFIG_GLOBAL_PROPERTY(bool, enabled, true)

public:
    explicit TasknudgeConfig(QObject* parent = nullptr)
        : ConfigObject(parent) {}
};

} // namespace burl::config
