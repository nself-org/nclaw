import { jsx as _jsx } from "react/jsx-runtime";
import { DndContext, closestCenter, PointerSensor, useSensor, useSensors, } from '@dnd-kit/core';
import { SortableContext, verticalListSortingStrategy } from '@dnd-kit/sortable';
import { useTopics } from '../../lib/topic-store';
import { TopicNode } from './TopicNode';
export function TopicTree({ nodes, depth = 0, highlightIds = new Set() }) {
    const move = useTopics((s) => s.move);
    const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 8 } }));
    async function handleDragEnd(event) {
        const { active, over } = event;
        if (!over || active.id === over.id)
            return;
        // Determine target parent path — drop onto a sibling means same parent group.
        const overId = String(over.id);
        const overNode = nodes.find((n) => n.topic.id === overId);
        const toParentPath = overNode
            ? overNode.topic.path.split('.').slice(0, -1).join('.')
            : '';
        await move(String(active.id), toParentPath);
    }
    const ids = nodes.map((n) => n.topic.id);
    return (_jsx(DndContext, { sensors: sensors, collisionDetection: closestCenter, onDragEnd: handleDragEnd, children: _jsx(SortableContext, { items: ids, strategy: verticalListSortingStrategy, children: _jsx("ul", { role: "group", className: "relative", children: nodes.map((node) => (_jsx(TopicNode, { node: node, depth: depth, highlightIds: highlightIds }, node.topic.id))) }) }) }));
}
