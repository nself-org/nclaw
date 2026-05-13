export interface GraphNode {
  id: string;
  label: string;
  kind: 'topic' | 'fact' | 'entity';
}

export interface GraphEdge {
  id: string;
  source: string;
  target: string;
  label: 'relates-to' | 'mentioned-in' | 'decided-on';
}

export function buildMockGraph(): { nodes: GraphNode[]; edges: GraphEdge[] } {
  const nodes: GraphNode[] = [];
  const edges: GraphEdge[] = [];

  // 20 topics
  for (let i = 0; i < 20; i++) {
    nodes.push({ id: `t${i}`, label: `Topic ${i}`, kind: 'topic' });
  }

  // 20 facts
  for (let i = 0; i < 20; i++) {
    nodes.push({ id: `f${i}`, label: `Fact ${i}`, kind: 'fact' });
  }

  // 10 entities
  for (let i = 0; i < 10; i++) {
    nodes.push({ id: `e${i}`, label: `Entity ${i}`, kind: 'entity' });
  }

  // 80 edges with mixed labels
  let edgeId = 0;
  const labels: GraphEdge['label'][] = ['relates-to', 'mentioned-in', 'decided-on'];

  for (let i = 0; i < 80; i++) {
    const src = nodes[Math.floor(Math.random() * nodes.length)].id;
    let dst = nodes[Math.floor(Math.random() * nodes.length)].id;

    // Avoid self-loops
    if (dst === src) {
      dst = nodes[(Math.floor(Math.random() * (nodes.length - 1)) + 1) % nodes.length].id;
    }

    edges.push({
      id: `r${edgeId++}`,
      source: src,
      target: dst,
      label: labels[i % labels.length],
    });
  }

  return { nodes, edges };
}
