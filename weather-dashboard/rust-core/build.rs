use std::{env, fs, path::PathBuf};

fn main() {
    let dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    println!("cargo:rerun-if-changed=src/lib.rs");
    println!("cargo:rerun-if-changed=cbindgen.toml");
    let bindings = cbindgen::Builder::new()
        .with_crate(&dir)
        .with_config(cbindgen::Config::from_file(dir.join("cbindgen.toml")).unwrap())
        .generate()
        .expect("cbindgen failed");
    let mut out = Vec::new();
    bindings.write(&mut out);
    let path = dir.join("include/weather_core.h");
    if fs::read(&path).map(|old| old != out).unwrap_or(true) {
        fs::write(&path, out).unwrap();
    }
}
