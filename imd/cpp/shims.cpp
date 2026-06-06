#include "shims.h"

#include <fcitx/addonmanager.h>
#include <fcitx/event.h>
#include <fcitx/inputcontext.h>
#include <fcitx/instance.h>
#include <fcitx-utils/event.h>
#include <fcitx-utils/handlertable.h>
#include <fcitx-utils/trackableobject.h>

#include <cstdio>
#include <memory>
#include <string>

// ── IC focus tracking (all accessed on fcitx5 main thread) ───────────────────

static fcitx::Instance* s_inst = nullptr;
static fcitx::InputContext* s_target_ic = nullptr;
// Locked snapshot taken when the picker opens.
static fcitx::InputContext* s_locked_ic = nullptr;
// Text queued to commit the next time s_locked_ic regains focus.
static std::string s_pending_commit;

static std::unique_ptr<fcitx::HandlerTableEntry<fcitx::EventHandler>> s_focus_watcher;
static std::unique_ptr<fcitx::HandlerTableEntry<fcitx::EventHandler>> s_destroy_watcher;
// Deferred commit event: fires after waylandim finishes updating currentIC_.
static std::unique_ptr<fcitx::EventSource> s_deferred_commit;

static void clear_if_matches(fcitx::InputContext* dying) {
    if (s_target_ic == dying) s_target_ic = nullptr;
    if (s_locked_ic == dying) s_locked_ic = nullptr;
}

extern "C" {

FcitxInstance* shim_get_instance(FcitxAddonManager* mgr) {
    return reinterpret_cast<FcitxInstance*>(
        reinterpret_cast<fcitx::AddonManager*>(mgr)->instance());
}

void shim_setup_ic_tracking(FcitxInstance* inst_opaque, const char* skip_program) {
    auto* inst = reinterpret_cast<fcitx::Instance*>(inst_opaque);
    s_inst = inst;
    (void)skip_program;

    s_focus_watcher = inst->watchEvent(
        fcitx::EventType::InputContextFocusIn,
        fcitx::EventWatcherPhase::Default,
        [](fcitx::Event& evt) {
            auto* ic = static_cast<fcitx::InputContextEvent&>(evt).inputContext();
            fprintf(stderr, "emojizasu: FocusIn ic=%p program=%s locked=%p\n",
                    ic, ic->program().c_str(), s_locked_ic);
            // Only track real apps as the target — ignore empty-program ICs
            // (those come from the picker's own TextInput via zwp_text_input_v3)
            if (!ic->program().empty()) {
                s_target_ic = ic;
            }
            if (!s_pending_commit.empty() && ic == s_locked_ic) {
                // Defer the commit to after this event cycle so waylandim has
                // finished updating its currentIC_ to this IC first.
                std::string text = std::move(s_pending_commit);
                s_pending_commit.clear();
                auto ref = ic->watch();
                fprintf(stderr, "emojizasu: PendingCommit deferred for ic=%p program=%s\n",
                        ic, ic->program().c_str());
                s_deferred_commit = s_inst->eventLoop().addPostEvent(
                    [ref, text](fcitx::EventSource*) mutable {
                        if (auto* ic2 = ref.get()) {
                            fprintf(stderr, "emojizasu: PendingCommit firing (deferred) ic=%p\n", ic2);
                            ic2->commitString(text);
                        }
                        return false;
                    }
                );
            }
        }
    );

    s_destroy_watcher = inst->watchEvent(
        fcitx::EventType::InputContextDestroyed,
        fcitx::EventWatcherPhase::Default,
        [](fcitx::Event& evt) {
            clear_if_matches(
                static_cast<fcitx::InputContextEvent&>(evt).inputContext());
        }
    );
}

void shim_lock_ic() {
    fprintf(stderr, "emojizasu: Lock: target_ic=%p program=%s\n",
            s_target_ic, s_target_ic ? s_target_ic->program().c_str() : "null");
    s_locked_ic = s_target_ic;
    s_pending_commit.clear();
}

void shim_queue_commit(const char* text, size_t len) {
    fprintf(stderr, "emojizasu: QueueCommit: locked_ic=%p program=%s target_ic=%p\n",
            s_locked_ic, s_locked_ic ? s_locked_ic->program().c_str() : "null",
            s_target_ic);
    if (s_locked_ic != nullptr && s_target_ic == s_locked_ic) {
        // Target already has focus — commit directly. No deferral needed since
        // we never stole focus, so waylandim's currentIC_ is already the target.
        fprintf(stderr, "emojizasu: QueueCommit: target active, committing directly\n");
        s_locked_ic->commitString(std::string(text, len));
    } else {
        s_pending_commit.assign(text, len);
    }
}

void shim_unlock_ic() {
    s_locked_ic = nullptr;
}

void shim_commit_to_target(FcitxInstance* inst_opaque,
                            const char* text, size_t len) {
    auto* ic = s_locked_ic ? s_locked_ic : s_target_ic;
    if (!ic)
        ic = reinterpret_cast<fcitx::Instance*>(inst_opaque)->mostRecentInputContext();
    fprintf(stderr, "emojizasu: Commit: locked=%p target=%p using=%p program=%s\n",
            s_locked_ic, s_target_ic, ic, ic ? ic->program().c_str() : "null");
    if (!ic) return;
    ic->commitString(std::string(text, len));
}

FcitxEventSourceIO* shim_add_io_event(FcitxInstance* inst_opaque, int fd,
                                       void (*cb)(void*), void* userdata) {
    auto* inst = reinterpret_cast<fcitx::Instance*>(inst_opaque);
    auto src = inst->eventLoop().addIOEvent(
        fd, fcitx::IOEventFlag::In,
        [cb, userdata](fcitx::EventSourceIO*, int, fcitx::IOEventFlags) -> bool {
            cb(userdata);
            return true;
        }
    );
    return reinterpret_cast<FcitxEventSourceIO*>(src.release());
}

void shim_free_io_event(FcitxEventSourceIO* src) {
    delete reinterpret_cast<fcitx::EventSourceIO*>(src);
}

} // extern "C"
