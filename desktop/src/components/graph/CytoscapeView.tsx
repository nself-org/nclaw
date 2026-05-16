/* cytoscape canvas — not shadcn-portable */
// eslint-disable-next-line @typescript-eslint/ban-ts-comment
// @ts-expect-error react-cytoscapejs has no bundled types; @types/react-cytoscapejs covers only v1.x
import CytoscapeComponent from 'react-cytoscapejs';
import cytoscape from 'cytoscape';
// @ts-expect-error cytoscape-cola has no @types package available on npm
import cola from 'cytoscape-cola';
import type { GraphNode, GraphEdge } from '@/lib/graph-mock';
import { useMemo } from 'react';

cytoscape.use(cola);

interface Props {
  nodes: GraphNode[];
  edges: GraphEdge[];
  onNodeClick?: (id: string) => void;
}

export function CytoscapeView({ nodes, edges, onNodeClick }: Props) {
  const elements = useMemo(
    () => [
      ...nodes.map((n) => ({
        data: { id: n.id, label: n.label, kind: n.kind },
      })),
      ...edges.map((e) => ({
        data: { id: e.id, source: e.source, target: e.target, label: e.label },
      })),
    ],
    [nodes, edges]
  );

  // cytoscape.StylesheetStyle uses the `style` key (vs StylesheetCSS which uses `css`).
  const stylesheet: cytoscape.StylesheetStyle[] = [
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
        // 'edge-text-rotation' is a valid cytoscape CSS property missing from @types/cytoscape
        'edge-text-rotation': 'autorotate' as string,
      } as cytoscape.Css.Edge,
    },
    {
      selector: 'node:selected',
      style: {
        'border-width': 3,
        'border-color': '#fbbf24',
      },
    },
  ];

  return (
    <CytoscapeComponent
      elements={elements}
      stylesheet={stylesheet}
      layout={{
        name: 'cola',
        animate: true,
        randomize: false,
        maxSimulationTime: 3000,
        nodeSpacing: 10,
        edgeLength: 50,
      }}
      cy={(c: cytoscape.Core) => {
        c.on('tap', 'node', (evt: cytoscape.EventObject) => {
          onNodeClick?.(evt.target.id());
        });
      }}
      style={{ width: '100%', height: '100%', backgroundColor: '#0f172a' }}
    />
  );
}
