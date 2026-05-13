import React from "react";

function App(): React.ReactElement {
  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        height: "100vh",
        fontFamily: "system-ui, sans-serif",
        backgroundColor: "#030712",
        color: "#f9fafb",
      }}
    >
      <h1 style={{ fontSize: "2.5rem", margin: 0 }}>ɳClaw</h1>
      <div style={{ marginTop: "0.5rem", color: "#6b7280", fontSize: "0.875rem" }}>
        v1.1.1
      </div>
    </div>
  );
}

export default App;
