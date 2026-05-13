import { lazy, Suspense, useState } from 'react';
import { buildMockGraph } from '@/lib/graph-mock';

const CytoscapeView = lazy(() =>
  import('@/components/graph/CytoscapeView').then((m) => ({
    default: m.CytoscapeView,
  }))
);

export function MemoryGraph() {
  const [graph] = useState(() => buildMockGraph());
  const [selected, setSelected] = useState<string | null>(null);
  const selectedNode = graph.nodes.find((n) => n.id === selected);

  return (
    <div className="flex flex-col h-screen bg-slate-950 text-slate-100">
      <div className="bg-amber-500/10 border-b border-amber-500/30 px-4 py-2 text-sm text-amber-300 flex items-center gap-2">
        <span className="inline-block w-2 h-2 bg-amber-400 rounded-full animate-pulse"></span>
        Memory Graph (Preview) — full implementation in v1.2.0
      </div>

      <div className="flex-1 flex overflow-hidden">
        <div className="flex-1">
          <Suspense
            fallback={
              <div className="flex items-center justify-center h-full">
                <div className="text-slate-400">Loading graph…</div>
              </div>
            }
          >
            <CytoscapeView
              nodes={graph.nodes}
              edges={graph.edges}
              onNodeClick={setSelected}
            />
          </Suspense>
        </div>

        {selected && selectedNode && (
          <aside className="w-80 border-l border-slate-800 bg-slate-900/50 p-4 overflow-y-auto">
            <div className="space-y-4">
              <div>
                <h3 className="font-semibold text-lg mb-1">{selectedNode.label}</h3>
                <div className="text-xs text-slate-500">ID: {selectedNode.id}</div>
              </div>

              <div>
                <label className="text-xs font-semibold text-slate-400 uppercase tracking-wide">
                  Type
                </label>
                <div className="mt-1 px-2 py-1 bg-slate-800 rounded text-sm capitalize">
                  {selectedNode.kind}
                </div>
              </div>

              <div>
                <label className="text-xs font-semibold text-slate-400 uppercase tracking-wide">
                  Connections
                </label>
                <div className="mt-2 space-y-1">
                  {graph.edges
                    .filter((e) => e.source === selected || e.target === selected)
                    .slice(0, 5)
                    .map((e) => {
                      const other = e.source === selected ? e.target : e.source;
                      return (
                        <div
                          key={e.id}
                          className="text-xs text-slate-300 p-1 bg-slate-800/50 rounded flex items-center justify-between"
                        >
                          <span>{other}</span>
                          <span className="text-slate-500 text-xs">{e.label}</span>
                        </div>
                      );
                    })}
                </div>
              </div>

              <div className="text-xs text-slate-500 border-t border-slate-800 pt-3">
                Click nodes to explore connections
              </div>
            </div>
          </aside>
        )}
      </div>
    </div>
  );
}
