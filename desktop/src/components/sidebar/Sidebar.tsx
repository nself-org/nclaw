import { useEffect, useMemo, useCallback, useState } from 'react';
import { useTopics, buildTree, SearchResult } from '../../lib/topic-store';
import { SearchBar } from './SearchBar';
import { TopicTree } from './TopicTree';

const COLLAPSED_WIDTH = 56;
const EXPANDED_WIDTH = 280;

export function Sidebar() {
  const load = useTopics((s) => s.load);
  const topics = useTopics((s) => s.topics);
  const collapsed = useTopics((s) => s.collapsed);
  const setCollapsed = useTopics((s) => s.setCollapsed);

  const [searchResult, setSearchResult] = useState<SearchResult | null>(null);

  useEffect(() => {
    load();
  }, [load]);

  const tree = useMemo(() => buildTree(topics), [topics]);

  const highlightIds = useMemo<Set<string>>(() => {
    if (!searchResult) return new Set();
    const ids = searchResult.topics.map((t) => t.id);
    return new Set([...ids, ...searchResult.matched_message_topics]);
  }, [searchResult]);

  // When searching, filter root nodes to those with matching ids or children with matching ids.
  const visibleTree = useMemo(() => {
    if (!searchResult) return tree;
    const matchSet = new Set([
      ...searchResult.topics.map((t) => t.id),
      ...searchResult.matched_message_topics,
    ]);
    return tree.filter((node) => {
      function hasMatch(n: typeof node): boolean {
        return matchSet.has(n.topic.id) || n.children.some(hasMatch);
      }
      return hasMatch(node);
    });
  }, [tree, searchResult]);

  const handleSearchResult = useCallback((result: SearchResult | null) => {
    setSearchResult(result);
  }, []);

  const isEmpty = topics.length === 0;

  return (
    <aside
      aria-label="Topics sidebar"
      style={{ width: collapsed ? COLLAPSED_WIDTH : EXPANDED_WIDTH }}
      className="relative flex h-full flex-col border-r border-gray-800 bg-gray-950 transition-all duration-200"
    >
      {/* Toggle button */}
      <button
        aria-label={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
        onClick={() => setCollapsed(!collapsed)}
        className="absolute -right-3 top-4 z-10 flex h-6 w-6 items-center justify-center rounded-full border border-gray-700 bg-gray-900 text-gray-400 shadow hover:bg-gray-800 hover:text-gray-200"
      >
        <svg
          className={['h-3.5 w-3.5 transition-transform', collapsed ? '' : 'rotate-180'].join(' ')}
          viewBox="0 0 20 20"
          fill="currentColor"
          aria-hidden="true"
        >
          <path fillRule="evenodd" d="M12.79 5.23a.75.75 0 01-.02 1.06L8.832 10l3.938 3.71a.75.75 0 11-1.04 1.08l-4.5-4.25a.75.75 0 010-1.08l4.5-4.25a.75.75 0 011.06.02z" clipRule="evenodd" />
        </svg>
      </button>

      {collapsed ? (
        /* Icon-rail mode */
        <div className="flex flex-col items-center gap-2 pt-10 px-2">
          <button
            aria-label="Expand sidebar to see topics"
            onClick={() => setCollapsed(false)}
            className="rounded-md p-2 text-gray-400 hover:bg-gray-800 hover:text-sky-400"
          >
            <svg className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
              <path fillRule="evenodd" d="M2 4.75A.75.75 0 012.75 4h14.5a.75.75 0 010 1.5H2.75A.75.75 0 012 4.75zm0 10.5a.75.75 0 01.75-.75h7.5a.75.75 0 010 1.5h-7.5a.75.75 0 01-.75-.75zM2 10a.75.75 0 01.75-.75h14.5a.75.75 0 010 1.5H2.75A.75.75 0 012 10z" clipRule="evenodd" />
            </svg>
          </button>
        </div>
      ) : (
        <>
          {/* Search bar */}
          <div className="flex-shrink-0 pt-3">
            <SearchBar onResult={handleSearchResult} />
          </div>

          {/* Topic tree */}
          <nav
            aria-label="Topic navigation"
            className="flex-1 overflow-y-auto overflow-x-hidden py-2"
          >
            {isEmpty ? (
              <div className="flex h-full items-center justify-center px-6 text-center">
                <p className="text-sm text-gray-500">
                  Your topics will appear here as you talk to ɳClaw.
                </p>
              </div>
            ) : (
              <TopicTree nodes={visibleTree} depth={0} highlightIds={highlightIds} />
            )}
          </nav>

          {/* Footer */}
          <div className="flex-shrink-0 border-t border-gray-800 px-3 py-2">
            <div className="flex items-center gap-2 rounded-md px-2 py-1.5 text-xs text-gray-500 hover:bg-gray-800 hover:text-gray-300 cursor-pointer">
              <svg className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-5.5-2.5a2.5 2.5 0 11-5 0 2.5 2.5 0 015 0zM10 12a5.99 5.99 0 00-4.793 2.39A6.483 6.483 0 0010 16.5a6.483 6.483 0 004.793-2.11A5.99 5.99 0 0010 12z" clipRule="evenodd" />
              </svg>
              <span className="truncate">Account</span>
            </div>
          </div>
        </>
      )}
    </aside>
  );
}
