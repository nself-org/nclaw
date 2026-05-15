//! build.rs — nclaw/core native build script.
//!
//! When the `mobile-sqlite` feature is enabled, this script compiles the
//! vendored sqlite-vec C extension into a static library and links it into
//! the crate. The extension is registered at runtime via
//! `MobileSqliteEngine::open()` using `sqlite3_auto_extension`.
//!
//! # SQLITE_VEC_VERSION guard
//! The vendored submodule's VERSION file must match the compile-time constant
//! defined here. A mismatch is a hard build error — it prevents silent drift
//! between the binary you ship and the version string `vec_version()` returns.
//!
//! # Static linkage
//! The extension is compiled with `-DSQLITE_CORE` so it links against the
//! sqlite3 symbols already provided by rusqlite's bundled-sqlcipher, rather
//! than expecting a separate shared libsqlite3. No `.so` or `.dylib` is
//! produced — this is iOS App Store safe.
//!
//! # Cross-compile notes
//! iOS (arm64 device / arm64-sim / x86_64-sim) and Android (arm64-v8a,
//! armeabi-v7a, x86, x86_64) cross-compile targets are handled by the `cc`
//! crate's `TARGET` auto-detection. The CI matrix (S04.T01 / S04.T02) invokes
//! `cargo build --target <triple>` with appropriate `CC` / `AR` env vars set
//! by the platform toolchain scripts. This file is infrastructure-only — it
//! does not spawn xcrun or NDK directly.

use std::env;
use std::path::PathBuf;

/// The vendored sqlite-vec version this build expects.
/// Must match the raw content of `vendor/sqlite-vec/VERSION` (no leading 'v').
const SQLITE_VEC_VERSION: &str = "0.1.9";

fn main() {
    // Only build sqlite-vec when the mobile-sqlite feature is active.
    let mobile_sqlite = env::var("CARGO_FEATURE_MOBILE_SQLITE").is_ok();
    if !mobile_sqlite {
        return;
    }

    // -------------------------------------------------------------------------
    // Locate the vendored submodule relative to the manifest directory.
    // -------------------------------------------------------------------------
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let vendor_dir = manifest_dir.join("vendor").join("sqlite-vec");
    let version_file = vendor_dir.join("VERSION");

    // -------------------------------------------------------------------------
    // SQLITE_VEC_VERSION guard: mismatch is a hard build error.
    // -------------------------------------------------------------------------
    let vendored_version = std::fs::read_to_string(&version_file)
        .unwrap_or_else(|e| {
            panic!(
                "build.rs: cannot read vendor/sqlite-vec/VERSION: {e}\n\
                 Run: git submodule update --init core/vendor/sqlite-vec"
            )
        });
    let vendored_version = vendored_version.trim();
    if vendored_version != SQLITE_VEC_VERSION {
        panic!(
            "build.rs: sqlite-vec version mismatch!\n\
             Compile-time constant : {SQLITE_VEC_VERSION}\n\
             Vendored submodule    : {vendored_version}\n\
             Update the submodule or the SQLITE_VEC_VERSION constant to match."
        );
    }

    // -------------------------------------------------------------------------
    // Generate sqlite-vec.h from the template (VERSION substitution).
    // -------------------------------------------------------------------------
    // vendored_version is the raw VERSION content, e.g. "0.1.9".
    // The header template uses "${VERSION}" with a 'v' prefix in the string,
    // and numeric components separately.
    let ver_str = vendored_version; // already numeric: "0.1.9"
    let parts: Vec<&str> = ver_str.splitn(3, '.').collect();
    let (major, minor, patch) = (
        parts.first().copied().unwrap_or("0"),
        parts.get(1).copied().unwrap_or("0"),
        parts.get(2).copied().unwrap_or("0"),
    );
    // Template uses "v${VERSION}" style in the string literal, so prepend 'v'.
    let version_display = format!("v{ver_str}");

    let tmpl = std::fs::read_to_string(vendor_dir.join("sqlite-vec.h.tmpl"))
        .expect("build.rs: cannot read sqlite-vec.h.tmpl");

    let header = tmpl
        .replace("${VERSION}", &version_display)
        .replace("${DATE}", "2025-01-01") // placeholder; not used at runtime
        .replace("${SOURCE}", "vendored-submodule")
        .replace("${VERSION_MAJOR}", major)
        .replace("${VERSION_MINOR}", minor)
        .replace("${VERSION_PATCH}", patch);

    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    let generated_header = out_dir.join("sqlite-vec.h");
    std::fs::write(&generated_header, &header)
        .expect("build.rs: cannot write generated sqlite-vec.h");

    // -------------------------------------------------------------------------
    // Compile sqlite-vec.c as a static library.
    //
    // Key flags:
    //   -DSQLITE_CORE       — use sqlite3.h symbols from rusqlite's bundled
    //                         SQLCipher rather than the extension API shim.
    //                         This enables static linkage without a separate
    //                         libsqlite3 shared lib.
    //   -DSQLITE_VEC_STATIC — suppress dllexport decoration (Windows compat).
    //   -O2                 — reasonable optimisation for vector math kernels.
    // -------------------------------------------------------------------------
    cc::Build::new()
        .file(vendor_dir.join("sqlite-vec.c"))
        // Tell the compiler where to find our generated sqlite-vec.h.
        .include(&out_dir)
        // Tell sqlite-vec.c to use sqlite3.h (core mode) rather than
        // sqlite3ext.h (extension mode). This is required for static linking.
        .define("SQLITE_CORE", None)
        // Suppress DLL export annotations — we always produce a static lib.
        .define("SQLITE_VEC_STATIC", None)
        .opt_level(2)
        // Suppress warnings from vendored C code — we cannot modify it.
        .warnings(false)
        .compile("sqlite_vec");

    // -------------------------------------------------------------------------
    // Link the compiled static library.
    // cargo:rustc-link-lib=static=sqlite_vec  (emitted by cc::Build::compile)
    // The cc crate emits this automatically via `compile("sqlite_vec")`.
    // We emit a duplicate for clarity and CI grepping.
    // -------------------------------------------------------------------------
    println!("cargo:rustc-link-lib=static=sqlite_vec");

    // Re-run if the C source or version file changes.
    println!(
        "cargo:rerun-if-changed={}",
        vendor_dir.join("sqlite-vec.c").display()
    );
    println!(
        "cargo:rerun-if-changed={}",
        vendor_dir.join("sqlite-vec.h.tmpl").display()
    );
    println!("cargo:rerun-if-changed={}", version_file.display());
}
