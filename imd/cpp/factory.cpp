#include "shims.h"

#include <fcitx/addonfactory.h>
#include <fcitx/addoninstance.h>
#include <fcitx/addonmanager.h>

// Rust exports
extern "C" {
    void rust_addon_init(FcitxAddonManager* mgr);
    void rust_addon_destroy();
}

class EmojizasuAddon : public fcitx::AddonInstance {
public:
    explicit EmojizasuAddon(fcitx::AddonManager* mgr) {
        rust_addon_init(reinterpret_cast<FcitxAddonManager*>(mgr));
    }

    ~EmojizasuAddon() override {
        rust_addon_destroy();
    }
};

class EmojizasuFactory : public fcitx::AddonFactory {
public:
    fcitx::AddonInstance* create(fcitx::AddonManager* mgr) override {
        return new EmojizasuAddon(mgr);
    }
};

extern "C" fcitx::AddonFactory* emojizasu_get_factory() {
    static EmojizasuFactory factory;
    return &factory;
}
