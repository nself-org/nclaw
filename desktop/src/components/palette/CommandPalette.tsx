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
import { useConversationStore } from '../../stores/conversationStore';

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

  // Load recent conversations from embedded-PG backend via pglite IPC client.
  // Returns [] gracefully when the backend is not yet available (S17 / NotImplemented).
  const { loadRecentConversations, toPaletteResults } = useConversationStore();
  const recentConversations = toPaletteResults();

  useEffect(() => {
    loadRecentConversations();
  }, [loadRecentConversations]);

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
