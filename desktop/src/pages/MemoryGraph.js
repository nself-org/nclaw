import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { lazy, Suspense, useState } from 'react';
import { buildMockGraph } from '@/lib/graph-mock';
const CytoscapeView = lazy(() => import('@/components/graph/CytoscapeView').then((m) => ({
    default: m.CytoscapeView,
})));
export function MemoryGraph() {
    const [graph] = useState(() => buildMockGraph());
    const [selected, setSelected] = useState(null);
    const selectedNode = graph.nodes.find((n) => n.id === selected);
    return (_jsxs("div", { className: "flex flex-col h-screen bg-slate-950 text-slate-100", children: [_jsxs("div", { className: "bg-amber-500/10 border-b border-amber-500/30 px-4 py-2 text-sm text-amber-300 flex items-center gap-2", children: [_jsx("span", { className: "inline-block w-2 h-2 bg-amber-400 rounded-full animate-pulse" }), "Memory Graph (Preview) \u2014 full implementation in v1.2.0"] }), _jsxs("div", { className: "flex-1 flex overflow-hidden", children: [_jsx("div", { className: "flex-1", children: _jsx(Suspense, { fallback: _jsx("div", { className: "flex items-center justify-center h-full", children: _jsx("div", { className: "text-slate-400", children: "Loading graph\u2026" }) }), children: _jsx(CytoscapeView, { nodes: graph.nodes, edges: graph.edges, onNodeClick: setSelected }) }) }), selected && selectedNode && (_jsx("aside", { className: "w-80 border-l border-slate-800 bg-slate-900/50 p-4 overflow-y-auto", children: _jsxs("div", { className: "space-y-4", children: [_jsxs("div", { children: [_jsx("h3", { className: "font-semibold text-lg mb-1", children: selectedNode.label }), _jsxs("div", { className: "text-xs text-slate-500", children: ["ID: ", selectedNode.id] })] }), _jsxs("div", { children: [_jsx("label", { className: "text-xs font-semibold text-slate-400 uppercase tracking-wide", children: "Type" }), _jsx("div", { className: "mt-1 px-2 py-1 bg-slate-800 rounded text-sm capitalize", children: selectedNode.kind })] }), _jsxs("div", { children: [_jsx("label", { className: "text-xs font-semibold text-slate-400 uppercase tracking-wide", children: "Connections" }), _jsx("div", { className: "mt-2 space-y-1", children: graph.edges
                                                .filter((e) => e.source === selected || e.target === selected)
                                                .slice(0, 5)
                                                .map((e) => {
                                                const other = e.source === selected ? e.target : e.source;
                                                return (_jsxs("div", { className: "text-xs text-slate-300 p-1 bg-slate-800/50 rounded flex items-center justify-between", children: [_jsx("span", { children: other }), _jsx("span", { className: "text-slate-500 text-xs", children: e.label })] }, e.id));
                                            }) })] }), _jsx("div", { className: "text-xs text-slate-500 border-t border-slate-800 pt-3", children: "Click nodes to explore connections" })] }) }))] })] }));
}
