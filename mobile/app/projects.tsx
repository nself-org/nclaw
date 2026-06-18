/**
 * ProjectListScreen — multi-project switcher.
 *
 * Purpose: List of the user's projects (feature-spec §1a row "Project list").
 *   Each project groups conversations/threads. Tapping a project filters history;
 *   a FAB creates a new project. Reached from the chat/history surface.
 *
 * Inputs:  Projects via PROJECT_LIST query; create via PROJECT_CREATE mutation
 *          (documented Hasura nclaw_projects contract).
 * Outputs: Project list with conversation counts + create FAB.
 *
 * Constraints:
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen.
 *   - All text via t() with inline defaults.
 *   - RTL: layouts flip with useDirection().
 *
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 * Cross-ref: (tabs)/history.tsx, Hasura nclaw_projects.
 */

import React, { useCallback, useState } from 'react';
import { View, Text, FlatList, Pressable, TextInput } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import { gql, useQuery, useMutation } from 'urql';

import { AsyncScreen, type ScreenStatus } from '../components/AsyncScreen';
import { useDirection } from '../lib/useDirection';

/** PROJECT_LIST — all projects with conversation counts. */
const PROJECT_LIST = gql`
  query ProjectList {
    nclaw_projects(order_by: { updated_at: desc }) {
      id
      name
      conversation_count
      updated_at
    }
  }
`;

/** PROJECT_CREATE — create a new project. */
const PROJECT_CREATE = gql`
  mutation ProjectCreate($name: String!) {
    insert_nclaw_projects_one(object: { name: $name }) {
      id
      name
    }
  }
`;

interface ProjectRow {
  id: string;
  name: string;
  conversation_count: number;
  updated_at: string;
}

interface ProjectListData {
  nclaw_projects: ProjectRow[];
}

export default function ProjectListScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();

  const [result, refetch] = useQuery<ProjectListData>({ query: PROJECT_LIST });
  const [, createProject] = useMutation(PROJECT_CREATE);
  const [isCreating, setIsCreating] = useState(false);
  const [newName, setNewName] = useState('');

  const projects = result.data?.nclaw_projects ?? [];

  const status: ScreenStatus = result.fetching
    ? 'loading'
    : result.error
      ? 'error'
      : projects.length === 0
        ? 'empty'
        : 'data';

  const handleCreate = useCallback(async () => {
    const name = newName.trim();
    if (!name) return;
    await createProject({ name });
    setNewName('');
    setIsCreating(false);
    refetch({ requestPolicy: 'network-only' });
  }, [newName, createProject, refetch]);

  const handleOpen = useCallback(
    (projectId: string) => {
      router.push({ pathname: '/(tabs)/history', params: { projectId } });
    },
    [router],
  );

  return (
    <View className="flex-1 bg-background">
      <View
        className="px-4 pt-4 pb-2 border-b border-border"
        style={{ flexDirection: dir.flexRow, alignItems: 'center' }}
      >
        <Pressable
          onPress={() => router.back()}
          className="p-2 mr-2"
          accessibilityLabel={t('common.back', 'Go back')}
          accessibilityRole="button"
        >
          <Text style={{ fontSize: 18 }}>{dir.isRTL ? '→' : '←'}</Text>
        </Pressable>
        <Text className="flex-1 text-xl font-bold text-foreground" style={{ textAlign: dir.textAlign }}>
          {t('projects.title', 'Projects')}
        </Text>
        <Pressable
          onPress={() => setIsCreating(true)}
          className="p-2"
          accessibilityLabel={t('projects.create', 'Create project')}
          accessibilityRole="button"
        >
          <Text style={{ fontSize: 20 }}>+</Text>
        </Pressable>
      </View>

      {/* Create form */}
      {isCreating && (
        <View className="px-4 py-3 bg-muted border-b border-border flex-row items-center gap-2" style={{ flexDirection: dir.flexRow }}>
          <TextInput
            value={newName}
            onChangeText={setNewName}
            placeholder={t('projects.namePlaceholder', 'Project name')}
            placeholderTextColor="#888"
            className="flex-1 bg-background rounded-xl px-4 py-2 text-base text-foreground border border-border"
            style={{ textAlign: dir.textAlign }}
            accessibilityLabel={t('projects.namePlaceholder', 'Project name')}
            autoFocus
            returnKeyType="done"
            onSubmitEditing={handleCreate}
          />
          <Pressable
            onPress={handleCreate}
            className="px-4 py-2 bg-primary rounded-xl"
            accessibilityLabel={t('projects.create', 'Create')}
            accessibilityRole="button"
          >
            <Text className="text-primary-foreground font-medium">{t('projects.create', 'Create')}</Text>
          </Pressable>
        </View>
      )}

      <AsyncScreen
        status={status}
        error={result.error ?? null}
        onRetry={() => refetch({ requestPolicy: 'network-only' })}
        onReAuth={() => router.push('/auth/login')}
        testID="projects"
        emptyMessage={t('projects.empty', 'No projects yet')}
      >
        <FlatList
          data={projects}
          keyExtractor={(p) => p.id}
          renderItem={({ item }) => (
            <Pressable
              onPress={() => handleOpen(item.id)}
              className="flex-row items-center px-4 py-4 border-b border-border bg-background"
              accessibilityLabel={`${item.name} — ${item.conversation_count} ${t('projects.conversations', 'conversations')}`}
              accessibilityRole="button"
              style={{ flexDirection: dir.flexRow }}
            >
              <Text className="mr-3">📁</Text>
              <Text className="flex-1 text-base text-foreground" style={{ textAlign: dir.textAlign }}>{item.name}</Text>
              <Text className="text-sm text-muted-foreground">{item.conversation_count}</Text>
            </Pressable>
          )}
          showsVerticalScrollIndicator={false}
          accessibilityLabel={t('projects.listLabel', 'Project list')}
        />
      </AsyncScreen>
    </View>
  );
}
