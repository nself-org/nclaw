import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
// ɳClaw Desktop — Command Palette (Cmd-K)
import { useEffect, useState } from 'react';
import { Command } from 'cmdk';
import { STATIC_COMMANDS, paletteSearch, } from '../../lib/palette-actions';
export function CommandPalette({ open, onClose, onSelect, }) {
    const [query, setQuery] = useState('');
    const [results, setResults] = useState([]);
    const [recentConversations, setRecentConversations] = useState([]);
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
            }
            catch (error) {
                console.error('palette_search failed:', error);
                setResults([]);
            }
        };
        search();
    }, [query]);
    const handleSelect = (result) => {
        onSelect?.(result);
        onClose();
    };
    return (_jsxs(Command.Dialog, { open: open, onOpenChange: onClose, children: [_jsx(Command.Input, { placeholder: "Search topics, conversations, settings\u2026", value: query, onValueChange: setQuery }), _jsx(Command.List, { children: !query ? (_jsxs(_Fragment, { children: [_jsx(Command.Group, { heading: "Recent", children: recentConversations.map((conv) => (_jsxs(Command.Item, { value: conv.id, onSelect: () => handleSelect(conv), children: [_jsx("span", { children: conv.label }), conv.description && (_jsx("span", { className: "ml-2 text-xs text-gray-500", children: conv.description }))] }, conv.id))) }), _jsx(Command.Group, { heading: "Commands", children: STATIC_COMMANDS.map((cmd) => (_jsxs(Command.Item, { value: cmd.id, onSelect: () => handleSelect(cmd), children: [_jsx("span", { children: cmd.label }), cmd.shortcut && (_jsx("span", { className: "ml-auto text-xs text-gray-400", children: cmd.shortcut }))] }, cmd.id))) })] })) : results.length > 0 ? (_jsxs(_Fragment, { children: [results.some((r) => r.kind === 'topic') && (_jsx(Command.Group, { heading: "Topics", children: results
                                .filter((r) => r.kind === 'topic')
                                .map((topic) => (_jsx(Command.Item, { value: topic.id, onSelect: () => handleSelect(topic), children: topic.label }, topic.id))) })), results.some((r) => r.kind === 'conversation') && (_jsx(Command.Group, { heading: "Conversations", children: results
                                .filter((r) => r.kind === 'conversation')
                                .map((conv) => (_jsxs(Command.Item, { value: conv.id, onSelect: () => handleSelect(conv), children: [_jsx("span", { children: conv.label }), conv.description && (_jsx("span", { className: "ml-2 text-xs text-gray-500", children: conv.description }))] }, conv.id))) })), results.some((r) => r.kind === 'command') && (_jsx(Command.Group, { heading: "Commands", children: results
                                .filter((r) => r.kind === 'command')
                                .map((cmd) => (_jsxs(Command.Item, { value: cmd.id, onSelect: () => handleSelect(cmd), children: [_jsx("span", { children: cmd.label }), cmd.shortcut && (_jsx("span", { className: "ml-auto text-xs text-gray-400", children: cmd.shortcut }))] }, cmd.id))) }))] })) : (_jsx(Command.Empty, { children: "No results found." })) })] }));
}
