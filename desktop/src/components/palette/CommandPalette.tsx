// ɳClaw Desktop — Command Palette (Cmd-K)

import React, { useEffect, useState } from 'react';
import { Command } from 'cmdk';
import {
  PaletteResult,
  STATIC_COMMANDS,
  paletteSearch,
} from '../../lib/palette-actions';

interface CommandPaletteProps {
  open: boolean;
  onClose: () => void;
  onSelect?: (result: PaletteResult) => void;
}

export function CommandPalette({
  open,
  onClose,
  onSelect,
}: CommandPaletteProps) {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<PaletteResult[]>([]);
  const [recentConversations, setRecentConversations] = useState<
    PaletteResult[]
  >([]);

  // Load recent conversations on mount (stub — real data wires in S17)
  useEffect(() => {
    setRecentConversations([
      {
        kind: 'conversation',
        id: '1',
        label: 'Debugging Auth Flow',
        description: 'TypeScript auth integration',
      },
      {
        kind: 'conversation',
        id: '2',
        label: 'Design System Colors',
        description: 'Tailwind palette review',
      },
      {
        kind: 'conversation',
        id: '3',
        label: 'API Schema Discussion',
        description: 'GraphQL types',
      },
      {
        kind: 'conversation',
        id: '4',
        label: 'Performance Tuning',
        description: 'React optimization notes',
      },
      {
        kind: 'conversation',
        id: '5',
        label: 'Deployment Strategy',
        description: 'CI/CD pipeline',
      },
    ]);
  }, []);

  // Search on query change
  useEffect(() => {
    if (!query) {
      setResults([]);
      return;
    }

    const search = async () => {
      try {
        const response = await paletteSearch(query);
        setResults(response);
      } catch (error) {
        console.error('palette_search failed:', error);
        setResults([]);
      }
    };

    search();
  }, [query]);

  const handleSelect = (result: PaletteResult) => {
    onSelect?.(result);
    onClose();
  };

  return (
    <Command.Dialog open={open} onOpenChange={onClose}>
      <Command.Input
        placeholder="Search topics, conversations, settings…"
        value={query}
        onValueChange={setQuery}
      />
      <Command.List>
        {!query ? (
          <>
            {/* Show recent conversations when no search query */}
            <Command.Group heading="Recent">
              {recentConversations.map((conv) => (
                <Command.Item
                  key={conv.id}
                  value={conv.id}
                  onSelect={() => handleSelect(conv)}
                >
                  <span>{conv.label}</span>
                  {conv.description && (
                    <span className="ml-2 text-xs text-gray-500">
                      {conv.description}
                    </span>
                  )}
                </Command.Item>
              ))}
            </Command.Group>

            {/* Show commands without search */}
            <Command.Group heading="Commands">
              {STATIC_COMMANDS.map((cmd) => (
                <Command.Item
                  key={cmd.id}
                  value={cmd.id}
                  onSelect={() => handleSelect(cmd)}
                >
                  <span>{cmd.label}</span>
                  {cmd.shortcut && (
                    <span className="ml-auto text-xs text-gray-400">
                      {cmd.shortcut}
                    </span>
                  )}
                </Command.Item>
              ))}
            </Command.Group>
          </>
        ) : results.length > 0 ? (
          <>
            {/* Topics */}
            {results.some((r) => r.kind === 'topic') && (
              <Command.Group heading="Topics">
                {results
                  .filter((r) => r.kind === 'topic')
                  .map((topic) => (
                    <Command.Item
                      key={topic.id}
                      value={topic.id}
                      onSelect={() => handleSelect(topic)}
                    >
                      {topic.label}
                    </Command.Item>
                  ))}
              </Command.Group>
            )}

            {/* Conversations */}
            {results.some((r) => r.kind === 'conversation') && (
              <Command.Group heading="Conversations">
                {results
                  .filter((r) => r.kind === 'conversation')
                  .map((conv) => (
                    <Command.Item
                      key={conv.id}
                      value={conv.id}
                      onSelect={() => handleSelect(conv)}
                    >
                      <span>{conv.label}</span>
                      {conv.description && (
                        <span className="ml-2 text-xs text-gray-500">
                          {conv.description}
                        </span>
                      )}
                    </Command.Item>
                  ))}
              </Command.Group>
            )}

            {/* Commands */}
            {results.some((r) => r.kind === 'command') && (
              <Command.Group heading="Commands">
                {results
                  .filter((r) => r.kind === 'command')
                  .map((cmd) => (
                    <Command.Item
                      key={cmd.id}
                      value={cmd.id}
                      onSelect={() => handleSelect(cmd)}
                    >
                      <span>{cmd.label}</span>
                      {cmd.shortcut && (
                        <span className="ml-auto text-xs text-gray-400">
                          {cmd.shortcut}
                        </span>
                      )}
                    </Command.Item>
                  ))}
              </Command.Group>
            )}
          </>
        ) : (
          <Command.Empty>No results found.</Command.Empty>
        )}
      </Command.List>
    </Command.Dialog>
  );
}
