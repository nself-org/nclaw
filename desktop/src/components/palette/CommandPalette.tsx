// ɳClaw Desktop — Command Palette (Cmd-K)

import { useEffect, useState } from 'react';
import {
  CommandDialog,
  CommandInput,
  CommandList,
  CommandEmpty,
  CommandGroup,
  CommandItem,
  CommandShortcut,
} from '@/components/ui/command';
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
    <CommandDialog open={open} onOpenChange={onClose}>
      <CommandInput
        placeholder="Search topics, conversations, settings…"
        value={query}
        onValueChange={setQuery}
      />
      <CommandList>
        {!query ? (
          <>
            {/* Show recent conversations when no search query */}
            <CommandGroup heading="Recent">
              {recentConversations.map((conv) => (
                <CommandItem
                  key={conv.id}
                  value={conv.id}
                  onSelect={() => handleSelect(conv)}
                >
                  <span>{conv.label}</span>
                  {conv.description && (
                    <span className="ml-2 text-xs text-muted-foreground">
                      {conv.description}
                    </span>
                  )}
                </CommandItem>
              ))}
            </CommandGroup>

            {/* Show commands without search */}
            <CommandGroup heading="Commands">
              {STATIC_COMMANDS.map((cmd) => (
                <CommandItem
                  key={cmd.id}
                  value={cmd.id}
                  onSelect={() => handleSelect(cmd)}
                >
                  <span>{cmd.label}</span>
                  {cmd.shortcut && (
                    <CommandShortcut>{cmd.shortcut}</CommandShortcut>
                  )}
                </CommandItem>
              ))}
            </CommandGroup>
          </>
        ) : results.length > 0 ? (
          <>
            {/* Topics */}
            {results.some((r) => r.kind === 'topic') && (
              <CommandGroup heading="Topics">
                {results
                  .filter((r) => r.kind === 'topic')
                  .map((topic) => (
                    <CommandItem
                      key={topic.id}
                      value={topic.id}
                      onSelect={() => handleSelect(topic)}
                    >
                      {topic.label}
                    </CommandItem>
                  ))}
              </CommandGroup>
            )}

            {/* Conversations */}
            {results.some((r) => r.kind === 'conversation') && (
              <CommandGroup heading="Conversations">
                {results
                  .filter((r) => r.kind === 'conversation')
                  .map((conv) => (
                    <CommandItem
                      key={conv.id}
                      value={conv.id}
                      onSelect={() => handleSelect(conv)}
                    >
                      <span>{conv.label}</span>
                      {conv.description && (
                        <span className="ml-2 text-xs text-muted-foreground">
                          {conv.description}
                        </span>
                      )}
                    </CommandItem>
                  ))}
              </CommandGroup>
            )}

            {/* Commands */}
            {results.some((r) => r.kind === 'command') && (
              <CommandGroup heading="Commands">
                {results
                  .filter((r) => r.kind === 'command')
                  .map((cmd) => (
                    <CommandItem
                      key={cmd.id}
                      value={cmd.id}
                      onSelect={() => handleSelect(cmd)}
                    >
                      <span>{cmd.label}</span>
                      {cmd.shortcut && (
                        <CommandShortcut>{cmd.shortcut}</CommandShortcut>
                      )}
                    </CommandItem>
                  ))}
              </CommandGroup>
            )}
          </>
        ) : (
          <CommandEmpty>No results found.</CommandEmpty>
        )}
      </CommandList>
    </CommandDialog>
  );
}
