import React from "react";
import ReactDOM from "react-dom/client";
import "./index.css";
import App from "./App";

// Ensure the page body is visible before React mounts. In a real Tauri
// webview the native runtime may briefly set visibility:hidden on the body
// before the window is ready. In browser-only environments (Playwright,
// dev server) we want the body visible immediately so tests can assert on
// content without waiting for a Tauri "ready" event that never fires.
document.body.style.visibility = "visible";

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
