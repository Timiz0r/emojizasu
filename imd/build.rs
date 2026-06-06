fn main() {
    let fcitx5 = pkg_config::Config::new()
        .atleast_version("5.0")
        .probe("Fcitx5Core")
        .expect("Fcitx5Core not found — install fcitx5 dev headers");

    let mut build = cc::Build::new();
    build
        .cpp(true)
        .std("c++20")
        .file("cpp/shims.cpp")
        .file("cpp/factory.cpp")
        .cargo_metadata(false); // we emit the link directive ourselves below

    for path in &fcitx5.include_paths {
        build.include(path);
    }

    build.compile("fcitx5_shims");

    // +whole-archive prevents the linker from dead-code-eliminating
    // fcitx_addon_factory_instance, which is only called by fcitx5 at
    // runtime and has no Rust-side reference to keep it alive.
    let out_dir = std::env::var("OUT_DIR").unwrap();
    println!("cargo:rustc-link-search=native={out_dir}");
    println!("cargo:rustc-link-lib=static:+whole-archive=fcitx5_shims");
    // --gc-sections would otherwise drop fcitx_addon_factory_instance since
    // no Rust code references it; it's only called by fcitx5 at runtime.
    println!("cargo:rustc-link-arg=-Wl,--export-dynamic-symbol=fcitx_addon_factory_instance");

    for path in &fcitx5.link_paths {
        println!("cargo:rustc-link-search=native={}", path.display());
    }
    for lib in &fcitx5.libs {
        println!("cargo:rustc-link-lib={lib}");
    }

    println!("cargo:rerun-if-changed=cpp/shims.cpp");
    println!("cargo:rerun-if-changed=cpp/factory.cpp");
    println!("cargo:rerun-if-changed=cpp/shims.h");
}
