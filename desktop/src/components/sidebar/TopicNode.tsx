import { useState, useRef } from 'react';
import { useSortable } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { TreeNode, useTopics } from '../../lib/topic-store';
import { TopicTree } from './TopicTree';

interface TopicNodeProps {
  node: TreeNode;
  depth: number;
  highlightIds: Set<string>;
}

type MenuAction = 'new-subtopic' | 'rename' | 'archive' | 'delete' | 'export';

const MENU_ITEMS: { action: MenuAction; label: string }[] = [
  { action: 'new-subtopic', label: 'New Subtopic' },
  { action: 'rename', label: 'Rename' },
  { action: 'archive', label: 'Archive' },
  { action: 'delete', label: 'Delete' },
  { action: 'export', label: 'Export' },
];

export function TopicNode({ node, depth, highlightIds }: TopicNodeProps) {
  const { topic, children } = node;
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: topic.id,
  });
  const active = useTopics((s) => s.active);
  const expanded = useTopics((s) => s.expanded.has(topic.id));
  const toggleExpand = useTopics((s) => s.toggleExpand);
  const setActive = useTopics((s) => s.setActive);
  const menuRef = useRef<HTMLDetailsElement>(null);

  const isActive = active === topic.id;
  const isHighlighted = highlightIds.has(topic.id);
  const hasChildren = children.length > 0;

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.4 : 1,
  };

  function handleMenuAction(action: MenuAction) {
    menuRef.current?.removeAttribute('open');
    // Stub — real implementations land when backend commands are wired in S17.
    console.info('[TopicNode] menu action', action, topic.id);
  }

  return (
    <li
      ref={setNodeRef}
      style={style}
      className="list-none"
      role="treeitem"
      aria-expanded={hasChildren ? expanded : undefined}
      aria-selected={isActive}
    >
      <div
        className={[
          'group flex items-center gap-1 rounded-md px-2 py-1 text-sm cursor-pointer select-none',
          isActive ? 'bg-sky-500/20 text-sky-300' : isHighlighted ? 'bg-yellow-500/10 text-yellow-200' : 'text-gray-300 hover:bg-gray-700/50',
        ].join(' ')}
        style={{ paddingLeft: `${8 + depth * 16}px` }}
        onClick={() => setActive(topic.id)}
      >
        {/* Indent guide */}
        {depth > 0 && (
          <span
            className="absolute left-0 border-l border-gray-700"
            style={{ left: `${depth * 16}px`, top: 0, bottom: 0 }}
            aria-hidden="true"
          />
        )}

        {/* Expand/collapse chevron */}
        <button
          aria-label={expanded ? 'Collapse' : 'Expand'}
          onClick={(e) => { e.stopPropagation(); if (hasChildren) toggleExpand(topic.id); }}
          className={['h-4 w-4 flex-shrink-0 text-gray-500 transition-transform', expanded ? 'rotate-90' : '', !hasChildren ? 'invisible' : ''].join(' ')}
        >
          <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
            <path fillRule="evenodd" d="M7.21 14.77a.75.75 0 01.02-1.06L11.168 10 7.23 6.29a.75.75 0 111.04-1.08l4.5 4.25a.75.75 0 010 1.08l-4.5 4.25a.75.75 0 01-1.06-.02z" clipRule="evenodd" />
          </svg>
        </button>

        {/* Drag handle */}
        <span
          {...listeners}
          {...attributes}
          aria-label="Drag to reorder"
          className="h-4 w-4 flex-shrink-0 cursor-grab text-gray-600 opacity-0 group-hover:opacity-100"
        >
          <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
            <path d="M7 2a2 2 0 11-4 0 2 2 0 014 0zM7 8a2 2 0 11-4 0 2 2 0 014 0zM7 14a2 2 0 11-4 0 2 2 0 014 0zM17 2a2 2 0 11-4 0 2 2 0 014 0zM17 8a2 2 0 11-4 0 2 2 0 014 0zM17 14a2 2 0 11-4 0 2 2 0 014 0z" />
          </svg>
        </span>

        {/* Topic name */}
        <span className="flex-1 truncate">{topic.name}</span>

        {/* Context menu */}
        <details ref={menuRef} className="relative ml-auto" onClick={(e) => e.stopPropagation()}>
          <summary
            aria-label="Topic options"
            className="list-none cursor-pointer rounded p-0.5 text-gray-500 opacity-0 group-hover:opacity-100 hover:bg-gray-600 hover:text-gray-200"
          >
            <svg className="h-4 w-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
              <path d="M10 3a1.5 1.5 0 110 3 1.5 1.5 0 010-3zM10 8.5a1.5 1.5 0 110 3 1.5 1.5 0 010-3zM11.5 15.5a1.5 1.5 0 10-3 0 1.5 1.5 0 003 0z" />
            </svg>
          </summary>
          <ul className="absolute right-0 z-50 mt-1 w-36 rounded-md border border-gray-700 bg-gray-900 py-1 shadow-xl" role="menu">
            {MENU_ITEMS.map(({ action, label }) => (
              <li key={action} role="none">
                <button
                  role="menuitem"
                  onClick={() => handleMenuAction(action)}
                  className={[
                    'w-full px-3 py-1.5 text-left text-sm',
                    action === 'delete' ? 'text-red-400 hover:bg-red-500/10' : 'text-gray-300 hover:bg-gray-700',
                  ].join(' ')}
                >
                  {label}
                </button>
              </li>
            ))}
          </ul>
        </details>
      </div>

      {/* Children */}
      {hasChildren && expanded && (
        <TopicTree nodes={children} depth={depth + 1} highlightIds={highlightIds} />
      )}
    </li>
  );
}
