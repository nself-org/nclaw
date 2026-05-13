//! Export TypeScript bindings from libnclaw shared types.
//! Generates .ts files in ../../app/lib/bindings/
//!
//! Run with: cargo run --bin export-bindings --features ts-export

#[cfg(feature = "ts-export")]
fn main() {
    use std::path::PathBuf;
    use ts_rs::TS;

    let out_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../app/lib/bindings");

    std::fs::create_dir_all(&out_dir).expect("Failed to create bindings directory");

    // Export core types
    libnclaw::types::Conversation::export_all(&out_dir).expect("Failed to export Conversation");
    libnclaw::types::Message::export_all(&out_dir).expect("Failed to export Message");
    libnclaw::types::Topic::export_all(&out_dir).expect("Failed to export Topic");
    libnclaw::types::Memory::export_all(&out_dir).expect("Failed to export Memory");
    libnclaw::types::Entity::export_all(&out_dir).expect("Failed to export Entity");
    libnclaw::types::Plugin::export_all(&out_dir).expect("Failed to export Plugin");
    libnclaw::types::Document::export_all(&out_dir).expect("Failed to export Document");

    println!("✅ TypeScript bindings exported to {}", out_dir.display());
}

#[cfg(not(feature = "ts-export"))]
fn main() {
    eprintln!("Error: ts-export feature not enabled. Run with --features ts-export");
    std::process::exit(1);
}
