#include "shims.h"

#include <fcitx/addonfactory.h>
#include <fcitx/addoninstance.h>
#include <fcitx/addonmanager.h>

// Rust exports
extern "C" {
    void* rust_addon_init(FcitxAddonManager* mgr);
    void  rust_addon_destroy(void* state);
}

// Thin C++ shell that satisfies fcitx5's vtable requirement.
// All logic lives on the Rust side.
class EmojizasuAddon : public fcitx::AddonInstance {
public:
    explicit EmojizasuAddon(fcitx::AddonManager* mgr)
        : rust_state_(rust_addon_init(
              reinterpret_cast<FcitxAddonManager*>(mgr))) {}

    ~EmojizasuAddon() override {
        rust_addon_destroy(rust_state_);
    }

private:
    void* rust_state_;
};

class EmojizasuFactory : public fcitx::AddonFactory {
public:
    fcitx::AddonInstance* create(fcitx::AddonManager* mgr) override {
        return new EmojizasuAddon(mgr);
    }
};

// Called from Rust's #[no_mangle] fcitx_addon_factory_instance so that
// Rust's linker version script controls the symbol's export visibility.
extern "C" fcitx::AddonFactory* emojizasu_get_factory() {
    static EmojizasuFactory factory;
    return &factory;
}
