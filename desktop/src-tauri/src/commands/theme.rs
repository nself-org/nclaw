#[tauri::command]
pub async fn set_window_theme(mode: String) -> Result<(), String> {
    // Stub: real implementation uses tauri WebviewWindow.set_theme() in Tauri 2
    // For now, theme is managed entirely on the React side via DOM classList
    match mode.as_str() {
        "light" | "dark" | "system" => Ok(()),
        _ => Err(format!("Invalid theme mode: {}", mode)),
    }
}
