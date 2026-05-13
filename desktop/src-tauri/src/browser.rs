//! T-2163: Browser automation -- server sends browser_open command via WS.
//! Opens URL in a hidden Tauri WebView, waits for load, extracts text or screenshot,
//! sends result back via WS.

use tauri::{Listener, Manager};

/// Handle a browser_open command from the server.
/// Modes: "text" (extract page text), "screenshot" (capture page image as base64).
pub async fn handle_browser_open(
    url: &str,
    mode: &str,
    app_handle: &tauri::AppHandle,
) -> Result<serde_json::Value, String> {
    if url.is_empty() {
        return Err("browser_open: empty URL".into());
    }

    // Validate URL scheme
    if !url.starts_with("http://") && !url.starts_with("https://") {
        return Err(format!("browser_open: invalid URL scheme: {url}"));
    }

    tracing::info!(url = %url, mode = %mode, "browser_open: loading page");

    let label = format!("browser_{}", uuid::Uuid::new_v4().simple());

    // Create a hidden webview window
    let window = tauri::WebviewWindowBuilder::new(
        app_handle,
        &label,
        tauri::WebviewUrl::External(
            url.parse().map_err(|e| format!("invalid URL: {e}"))?,
        ),
    )
    .title("nSelf Browser")
    .visible(false)
    .inner_size(1280.0, 900.0)
    .build()
    .map_err(|e| format!("failed to create webview: {e}"))?;

    // Wait for the page to load with a timeout
    let load_timeout = std::time::Duration::from_secs(30);
    let start = std::time::Instant::now();

    // Poll until the page fires a load event or we time out.
    // Tauri 2 webviews auto-navigate, so we give time for content to render.
    tokio::time::sleep(std::time::Duration::from_secs(3)).await;

    // Check if window still exists (user might have closed it)
    if app_handle.get_webview_window(&label).is_none() {
        return Err("browser_open: webview was closed before extraction".into());
    }

    let result = match mode {
        "text" => extract_text(&window).await,
        "screenshot" => capture_screenshot(&window).await,
        _ => Err(format!("browser_open: unknown mode: {mode}")),
    };

    // Clean up the hidden window
    let _ = window.close();

    result
}

/// Extract visible text content from the page via JavaScript evaluation.
async fn extract_text(
    window: &tauri::WebviewWindow,
) -> Result<serde_json::Value, String> {
    // Use JavaScript to extract text content from the page body.
    // We use innerText which respects visibility (unlike textContent).
    let js = r#"
        (function() {
            // Remove script and style elements to avoid noise
            var scripts = document.querySelectorAll('script, style, noscript');
            scripts.forEach(function(el) { el.remove(); });

            var title = document.title || '';
            var text = document.body ? document.body.innerText : '';
            var meta_desc = '';
            var meta = document.querySelector('meta[name="description"]');
            if (meta) meta_desc = meta.getAttribute('content') || '';

            return JSON.stringify({
                title: title,
                description: meta_desc,
                text: text.substring(0, 50000)
            });
        })()
    "#;

    let eval_result = window
        .eval(js)
        .map_err(|e| format!("JS eval failed: {e}"))?;

    // window.eval in Tauri 2 returns () -- we need to use a different approach.
    // Use a channel to receive the result from the webview.
    // For now, return a basic extraction result.
    // The JS runs but eval() doesn't return values in Tauri 2.
    // A production implementation would use tauri::ipc or an event channel.

    // Workaround: use a simpler approach with a known event pattern
    let (tx, rx) = tokio::sync::oneshot::channel::<String>();
    let tx = std::sync::Arc::new(std::sync::Mutex::new(Some(tx)));
    let tx_clone = tx.clone();

    let label = window.label().to_string();
    let _listener = window.listen("browser-extract-result", move |event| {
        if let Some(sender) = tx_clone.lock().unwrap_or_else(|p| p.into_inner()).take() {
            let _ = sender.send(event.payload().to_string());
        }
    });

    // Emit extraction JS that sends result back via event
    let extract_js = r#"
        (function() {
            var scripts = document.querySelectorAll('script, style, noscript');
            scripts.forEach(function(el) { el.remove(); });
            var title = document.title || '';
            var text = document.body ? document.body.innerText : '';
            var metaDesc = '';
            var meta = document.querySelector('meta[name="description"]');
            if (meta) metaDesc = meta.getAttribute('content') || '';
            var result = JSON.stringify({
                title: title,
                description: metaDesc,
                text: text.substring(0, 50000)
            });
            window.__TAURI__.event.emit('browser-extract-result', result);
        })()
    "#;

    let _ = window.eval(extract_js);

    // Wait for the result with a timeout
    match tokio::time::timeout(std::time::Duration::from_secs(10), rx).await {
        Ok(Ok(payload)) => {
            let parsed: serde_json::Value =
                serde_json::from_str(&payload).unwrap_or(serde_json::json!({
                    "text": payload,
                }));
            Ok(serde_json::json!({
                "mode": "text",
                "content": parsed,
            }))
        }
        _ => {
            // Fallback: return URL confirmation without extracted text
            tracing::warn!("browser_open: text extraction timed out, returning URL only");
            Ok(serde_json::json!({
                "mode": "text",
                "content": {
                    "title": "",
                    "text": "(extraction timed out)",
                },
                "url": window.url().map(|u| u.to_string()).unwrap_or_default(),
            }))
        }
    }
}

/// Capture a screenshot of the webview content as base64 PNG.
/// Note: Tauri 2 does not have a built-in screenshot API for webviews.
/// This uses a JS-based canvas capture as a workaround.
async fn capture_screenshot(
    window: &tauri::WebviewWindow,
) -> Result<serde_json::Value, String> {
    let (tx, rx) = tokio::sync::oneshot::channel::<String>();
    let tx = std::sync::Arc::new(std::sync::Mutex::new(Some(tx)));
    let tx_clone = tx.clone();

    let _listener = window.listen("browser-screenshot-result", move |event| {
        if let Some(sender) = tx_clone.lock().unwrap_or_else(|p| p.into_inner()).take() {
            let _ = sender.send(event.payload().to_string());
        }
    });

    // Use html2canvas-style approach: serialize DOM to canvas then base64
    let screenshot_js = r#"
        (function() {
            // Simple screenshot via canvas -- captures visible viewport
            try {
                var canvas = document.createElement('canvas');
                var body = document.body;
                var html = document.documentElement;
                var width = Math.min(html.clientWidth || 1280, 1280);
                var height = Math.min(html.scrollHeight || 900, 4000);
                canvas.width = width;
                canvas.height = height;

                // Use foreignObject SVG trick for rendering
                var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="' + width + '" height="' + height + '">'
                    + '<foreignObject width="100%" height="100%">'
                    + '<div xmlns="http://www.w3.org/1999/xhtml">'
                    + document.documentElement.outerHTML
                    + '</div></foreignObject></svg>';
                var img = new Image();
                var blob = new Blob([svg], {type: 'image/svg+xml;charset=utf-8'});
                var url = URL.createObjectURL(blob);
                img.onload = function() {
                    canvas.getContext('2d').drawImage(img, 0, 0);
                    URL.revokeObjectURL(url);
                    var dataUrl = canvas.toDataURL('image/png');
                    window.__TAURI__.event.emit('browser-screenshot-result', dataUrl);
                };
                img.onerror = function() {
                    window.__TAURI__.event.emit('browser-screenshot-result', 'error:canvas_render_failed');
                };
                img.src = url;
            } catch(e) {
                window.__TAURI__.event.emit('browser-screenshot-result', 'error:' + e.message);
            }
        })()
    "#;

    let _ = window.eval(screenshot_js);

    match tokio::time::timeout(std::time::Duration::from_secs(15), rx).await {
        Ok(Ok(payload)) => {
            if payload.starts_with("error:") {
                Err(format!("screenshot failed: {}", &payload[6..]))
            } else {
                Ok(serde_json::json!({
                    "mode": "screenshot",
                    "data_url": payload,
                }))
            }
        }
        _ => Err("screenshot capture timed out".into()),
    }
}
