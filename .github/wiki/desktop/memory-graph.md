# Memory Graph View (Preview)

## Overview

The Memory Graph is a visual exploration interface for your infinite memory store. It displays topics, facts, and entities as an interactive graph where you can discover connections and navigate your knowledge base.

## Features (v1.1.1)

- **Interactive graph visualization** powered by cytoscape.js with force-directed (Cola) layout
- **Node types**: Topics (blue), Facts (green), Entities (purple)
- **Edge labels**: "relates-to", "mentioned-in", "decided-on"
- **Click to explore**: Select any node to see its connections in a side panel
- **Auto-layout**: Graph automatically positions nodes for clarity

## How It Works

Click the Graph icon in the sidebar or use `/memory-graph` to open the visualization. Each node represents a distinct entity in your memory. Click any node to see related items in the right panel.

## Status

**Preview** — The full implementation with real data from your Postgres memory store is planned for v1.2.0. v1.1.1 ships with a mock 50-node graph for UX validation.

## Next Steps

- Integrate with live Postgres queries (v1.2.0)
- Add search and filtering (v1.2.0)
- Support custom layouts (v1.3.0)
- Export as image or data (v1.3.0)

---

**Last updated:** 2026-05-13
