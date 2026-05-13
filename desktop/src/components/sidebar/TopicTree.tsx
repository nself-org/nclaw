import {
  DndContext,
  closestCenter,
  PointerSensor,
  useSensor,
  useSensors,
  DragEndEvent,
} from '@dnd-kit/core';
import { SortableContext, verticalListSortingStrategy } from '@dnd-kit/sortable';
import { TreeNode, useTopics } from '../../lib/topic-store';
import { TopicNode } from './TopicNode';

interface TopicTreeProps {
  nodes: TreeNode[];
  depth?: number;
  highlightIds?: Set<string>;
}

export function TopicTree({ nodes, depth = 0, highlightIds = new Set() }: TopicTreeProps) {
  const move = useTopics((s) => s.move);
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 8 } }));

  async function handleDragEnd(event: DragEndEvent) {
    const { active, over } = event;
    if (!over || active.id === over.id) return;

    // Determine target parent path — drop onto a sibling means same parent group.
    const overId = String(over.id);
    const overNode = nodes.find((n) => n.topic.id === overId);
    const toParentPath = overNode
      ? overNode.topic.path.split('.').slice(0, -1).join('.')
      : '';

    await move(String(active.id), toParentPath);
  }

  const ids = nodes.map((n) => n.topic.id);

  return (
    <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
      <SortableContext items={ids} strategy={verticalListSortingStrategy}>
        <ul role="group" className="relative">
          {nodes.map((node) => (
            <TopicNode
              key={node.topic.id}
              node={node}
              depth={depth}
              highlightIds={highlightIds}
            />
          ))}
        </ul>
      </SortableContext>
    </DndContext>
  );
}
