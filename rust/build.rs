use std::env;
use std::path::PathBuf;

fn main() {
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let rubberband_dir = manifest_dir.join("vendor").join("rubberband");
    let single_cpp = rubberband_dir.join("single").join("RubberBandSingle.cpp");

    println!("cargo:rerun-if-changed={}", single_cpp.display());
    println!(
        "cargo:rerun-if-changed={}",
        rubberband_dir.join("rubberband").display()
    );
    println!(
        "cargo:rerun-if-changed={}",
        rubberband_dir.join("src").display()
    );

    let target = env::var("TARGET").unwrap_or_default();
    let mut build = cc::Build::new();
    build
        .cpp(true)
        .file(single_cpp)
        .include(&rubberband_dir)
        .include(rubberband_dir.join("src"))
        .define("RUBBERBAND_STATIC", None)
        .define("NDEBUG", None)
        .warnings(false);

    if target.contains("msvc") {
        build
            .std("c++14")
            .define("__MSVC__", None)
            .define("NOMINMAX", None)
            .define("_USE_MATH_DEFINES", None);
    } else {
        build.std("c++11");
    }

    build.compile("rubberband_single");

    if target.contains("apple") {
        println!("cargo:rustc-link-lib=framework=Accelerate");
    }
}
