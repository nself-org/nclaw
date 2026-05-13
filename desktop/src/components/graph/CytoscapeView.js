import { jsx as _jsx } from "react/jsx-runtime";
import CytoscapeComponent from 'react-cytoscapejs';
import cytoscape from 'cytoscape';
import cola from 'cytoscape-cola';
import { useMemo, useState } from 'react';
cytoscape.use(cola);
export function CytoscapeView({ nodes, edges, onNodeClick }) {
    const elements = useMemo(() => [
        ...nodes.map((n) => ({
            data: { id: n.id, label: n.label, kind: n.kind },
        })),
        ...edges.map((e) => ({
            data: { id: e.id, source: e.source, target: e.target, label: e.label },
        })),
    ], [nodes, edges]);
    const stylesheet = [
        {
            selector: 'node[kind = "topic"]',
            style: {
                'background-color': '#0ea5e9',
                shape: 'round-rectangle',
                label: 'data(label)',
                color: '#f1f5f9',
                'font-size': 10,
                'text-valign': 'center',
                'text-halign': 'center',
                padding: '6px',
            },
        },
        {
            selector: 'node[kind = "fact"]',
            style: {
                'background-color': '#22c55e',
                shape: 'ellipse',
                label: 'data(label)',
                color: '#f1f5f9',
                'font-size': 10,
                'text-valign': 'center',
                'text-halign': 'center',
                padding: '6px',
            },
        },
        {
            selector: 'node[kind = "entity"]',
            style: {
                'background-color': '#a855f7',
                shape: 'diamond',
                label: 'data(label)',
                color: '#f1f5f9',
                'font-size': 10,
                'text-valign': 'center',
                'text-halign': 'center',
                padding: '6px',
            },
        },
        {
            selector: 'edge',
            style: {
                width: 2,
                'line-color': '#475569',
                'target-arrow-color': '#475569',
                'target-arrow-shape': 'triangle',
                'curve-style': 'bezier',
                label: 'data(label)',
                'font-size': 8,
                color: '#94a3b8',
                'edge-text-rotation': 'autorotate',
            },
        },
        {
            selector: 'node:selected',
            style: {
                'border-width': 3,
                'border-color': '#fbbf24',
            },
        },
    ];
    const [cy, setCy] = useState(null);
    return (_jsx(CytoscapeComponent, { elements: elements, stylesheet: stylesheet, layout: {
            name: 'cola',
            animate: true,
            randomize: false,
            maxSimulationTime: 3000,
            nodeSpacing: 10,
            edgeLength: 50,
        }, cy: (c) => {
            setCy(c);
            c.on('tap', 'node', (evt) => {
                onNodeClick?.(evt.target.id());
            });
        }, style: { width: '100%', height: '100%', backgroundColor: '#0f172a' } }));
}
