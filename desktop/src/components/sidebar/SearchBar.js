import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState, useEffect, useRef } from 'react';
import { useTopics } from '../../lib/topic-store';
export function SearchBar({ onResult }) {
    const [query, setQuery] = useState('');
    const search = useTopics((s) => s.search);
    const timerRef = useRef(null);
    useEffect(() => {
        if (timerRef.current)
            clearTimeout(timerRef.current);
        if (!query.trim()) {
            onResult(null);
            return;
        }
        timerRef.current = setTimeout(async () => {
            const result = await search(query.trim());
            onResult(result);
        }, 200);
        return () => {
            if (timerRef.current)
                clearTimeout(timerRef.current);
        };
    }, [query, search, onResult]);
    return (_jsx("div", { className: "px-3 py-2", children: _jsxs("div", { className: "flex items-center gap-2 rounded-md bg-gray-800 px-3 py-1.5 ring-1 ring-gray-700 focus-within:ring-sky-500", children: [_jsx("svg", { className: "h-3.5 w-3.5 flex-shrink-0 text-gray-400", viewBox: "0 0 20 20", fill: "currentColor", "aria-hidden": "true", children: _jsx("path", { fillRule: "evenodd", d: "M9 3.5a5.5 5.5 0 100 11 5.5 5.5 0 000-11zM2 9a7 7 0 1112.452 4.391l3.328 3.329a.75.75 0 11-1.06 1.06l-3.329-3.328A7 7 0 012 9z", clipRule: "evenodd" }) }), _jsx("input", { type: "text", value: query, onChange: (e) => setQuery(e.target.value), placeholder: "Search topics...", "aria-label": "Search topics", className: "w-full bg-transparent text-sm text-gray-200 placeholder-gray-500 outline-none" }), query && (_jsx("button", { onClick: () => setQuery(''), "aria-label": "Clear search", className: "text-gray-500 hover:text-gray-300", children: _jsx("svg", { className: "h-3.5 w-3.5", viewBox: "0 0 20 20", fill: "currentColor", "aria-hidden": "true", children: _jsx("path", { d: "M6.28 5.22a.75.75 0 00-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 101.06 1.06L10 11.06l3.72 3.72a.75.75 0 101.06-1.06L11.06 10l3.72-3.72a.75.75 0 00-1.06-1.06L10 8.94 6.28 5.22z" }) }) }))] }) }));
}
