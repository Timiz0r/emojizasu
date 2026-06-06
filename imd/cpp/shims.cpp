#include "shims.h"

#include <fcitx/addonmanager.h>
#include <fcitx/event.h>
#include <fcitx/inputcontext.h>
#include <fcitx/instance.h>
#include <fcitx-utils/event.h>
#include <fcitx-utils/handlertable.h>
#include <fcitx-utils/key.h>

#include <memory>
#include <string>

static std::unique_ptr<fcitx::HandlerTableEntry<fcitx::EventHandler>> s_key_watcher;

extern "C" bool rust_io_event_handler(fcitx::EventSourceIO*, int, fcitx::IOEventFlags);
extern "C" bool rust_key_handler(unsigned int sym, unsigned int states, const char* utf8, size_t utf8_len, bool isRelease);

extern "C" {

FcitxInstance* shim_get_instance(FcitxAddonManager* mgr) {
    return reinterpret_cast<FcitxInstance*>(
        reinterpret_cast<fcitx::AddonManager*>(mgr)->instance());
}

void shim_install_key_watcher(FcitxInstance* inst_opaque) {
    auto* inst = reinterpret_cast<fcitx::Instance*>(inst_opaque);

    s_key_watcher = inst->watchEvent(
        fcitx::EventType::InputContextKeyEvent,
        fcitx::EventWatcherPhase::PreInputMethod,
        [](fcitx::Event& evt) {
            auto& ke = static_cast<fcitx::KeyEvent&>(evt);
            fcitx::Key key = ke.key();
            if (key.isModifier()) return;
            std::string utf8 = fcitx::Key::keySymToUTF8(key.sym());
            bool consumed = rust_key_handler(
                static_cast<unsigned int>(key.sym()),
                static_cast<unsigned int>(key.states().toInteger()),
                utf8.c_str(), utf8.size(), ke.isRelease());
            if (consumed) ke.filterAndAccept();
        }
    );
}

void shim_commit_to_target(FcitxInstance* inst_opaque, const char* text, size_t len) {
    auto* ic = reinterpret_cast<fcitx::Instance*>(inst_opaque)->mostRecentInputContext();
    if (!ic) return;
    ic->commitString(std::string(text, len));
}

FcitxEventSourceIO* shim_install_io_event(FcitxInstance* inst_opaque, int fd) {
    auto* inst = reinterpret_cast<fcitx::Instance*>(inst_opaque);
    auto src = inst->eventLoop().addIOEvent(
        fd, fcitx::IOEventFlag::In,
        rust_io_event_handler
    );
    return reinterpret_cast<FcitxEventSourceIO*>(src.release());
}

void shim_free_io_event(FcitxEventSourceIO* src) {
    delete reinterpret_cast<fcitx::EventSourceIO*>(src);
}

} // extern "C"
