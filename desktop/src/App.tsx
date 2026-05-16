import React, { useState, useEffect } from "react";
import { Sidebar } from "./components/sidebar/Sidebar";
import { CommandPalette } from "./components/palette/CommandPalette";
import { ChatContainer } from "./components/chat/ChatContainer";
import { Settings } from "./pages/Settings";
import { PaletteResult } from "./lib/palette-actions";
import { applyTheme, loadThemeFromStorage } from "./lib/theme";
import { useTopics } from "./lib/topic-store";

type ActiveView = "chat" | "settings";

function App(): React.ReactElement {
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [activeView, setActiveView] = useState<ActiveView>("chat");
  const setActiveTopic = useTopics((s) => s.setActive);

  // Apply persisted theme at mount — prevents FOUC
  useEffect(() => {
    const { mode, accentHex } = loadThemeFromStorage();
    applyTheme(mode, accentHex);
  }, []);

  // Keyboard shortcuts: Cmd+K / Ctrl+K → palette; Cmd+, / Ctrl+, → settings
  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault();
        setPaletteOpen((v) => !v);
      }
      if ((e.metaKey || e.ctrlKey) && e.key === ",") {
        e.preventDefault();
        setActiveView("settings");
      }
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  function handlePaletteSelect(result: PaletteResult) {
    if (result.kind === "command" && result.id === "open-settings") {
      setActiveView("settings");
      return;
    }
    if (result.kind === "topic" || result.kind === "conversation") {
      setActiveTopic(result.id);
      setActiveView("chat");
      return;
    }
    if (result.kind === "setting") {
      setActiveView("settings");
      return;
    }
    // default: stay on chat view
    setActiveView("chat");
  }

  return (
    <div
      data-testid="app-root"
      style={{
        display: "flex",
        height: "100vh",
        fontFamily: "system-ui, sans-serif",
        backgroundColor: "#030712",
        color: "#f9fafb",
        position: "relative",
        overflow: "hidden",
      }}
    >
      {/* Accessible brand heading — visually hidden, provides semantic role for a11y + tests */}
      <h1 className="sr-only">ɳClaw</h1>
      <Sidebar />

      {/* Chat view — always mounted so conversation state is preserved */}
      <main
        data-testid="main-content"
        style={{
          flex: 1,
          display: "flex",
          flexDirection: "column",
          overflow: "hidden",
          visibility: activeView === "chat" ? "visible" : "hidden",
        }}
      >
        <div data-testid="chat-view" style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
          <ChatContainer />
        </div>
      </main>

      {/* Settings view — full-screen overlay, rendered when active */}
      {activeView === "settings" && (
        <div
          data-testid="settings-view"
          style={{ position: "absolute", inset: 0, zIndex: 50 }}
          onKeyDown={(e) => {
            if (e.key === "Escape") {
              e.stopPropagation();
              setActiveView("chat");
            }
          }}
        >
          <Settings />
        </div>
      )}

      <CommandPalette
        open={paletteOpen}
        onClose={() => setPaletteOpen(false)}
        onSelect={handlePaletteSelect}
      />
    </div>
  );
}

export default App;
