/**
 * Share Composer Screen — RN version
 *
 * Mini composer UI for share sheet reception.
 * Displays preview of shared content (text, URL, image),
 * topic picker, optional note, and save button.
 */

import React, { useState, useEffect } from 'react';
import {
  View,
  ScrollView,
  TouchableOpacity,
  Image,
  TextInput,
  ActivityIndicator,
  useColorScheme,
  Text,
} from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { AsyncScreen } from '../components/AsyncScreen';
import { useDirection } from '@nself/i18n';
import { useTheme } from '@nself/ui/theme';

interface ShareParams {
  text?: string;
  url?: string;
  title?: string;
  imageUri?: string;
  mimeType?: string;
}

export default function ShareComposerScreen() {
  const params = useLocalSearchParams() as ShareParams;
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const colorScheme = useColorScheme();
  const direction = useDirection();
  const { colors } = useTheme();

  const [selectedTopicId, setSelectedTopicId] = useState<string | null>(null);
  const [note, setNote] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Prepare shared content
  const sharedContent = params?.text || params?.url || '';
  const sharedTitle = params?.title;
  const imageUri = params?.imageUri;

  /**
   * Save shared content to memory via GraphQL mutation.
   * POST to /memory/quick-add with topicId, content, imageUri, note.
   */
  const handleSave = async () => {
    if (!sharedContent.trim()) {
      setError('No content to save');
      return;
    }

    setSaving(true);
    setError(null);

    try {
      // TODO: Integrate with GraphQL client to call memory.quickAdd mutation
      // This would save the shared content + note to the selected topic
      // For now, placeholder implementation
      console.log('[ShareComposer] Saving:', {
        topicId: selectedTopicId,
        content: sharedContent,
        title: sharedTitle,
        note,
        imageUri,
      });

      // After successful save, close the screen
      router.back();
    } catch (err: any) {
      setError(err?.message || 'Failed to save');
    } finally {
      setSaving(false);
    }
  };

  /**
   * Close the share composer without saving.
   */
  const handleClose = () => {
    router.back();
  };

  return (
    <AsyncScreen
      state="data"
      onRetry={() => {}}
      style={{
        flex: 1,
        paddingTop: insets.top,
        paddingBottom: insets.bottom,
        backgroundColor: colors.background,
      }}
    >
      <ScrollView
        className="flex-1 px-4 py-4"
        contentContainerStyle={{ paddingHorizontal: 16, paddingVertical: 16 }}
      >
        {/* Header */}
        <View className="flex-row justify-between items-center mb-6">
          <Text className="text-xl font-bold">Save to ɳClaw</Text>
          <TouchableOpacity
            onPress={handleClose}
            className="p-2 rounded-full active:bg-gray-200"
            accessibilityLabel="Close"
          >
            <Text className="text-gray-600 text-lg">✕</Text>
          </TouchableOpacity>
        </View>

        {/* Content Preview Card */}
        <View
          className="bg-gray-50 border border-gray-200 rounded-lg p-4 mb-4"
          style={{
            backgroundColor: colors.surface,
            borderColor: colors.border,
          }}
        >
          {/* Title */}
          {sharedTitle && (
            <Text
              className="text-base font-semibold mb-2"
              style={{ color: colors.text }}
              numberOfLines={2}
            >
              {sharedTitle}
            </Text>
          )}

          {/* Content Preview */}
          <Text
            className="text-sm text-gray-600 mb-2"
            style={{ color: colors.textSecondary }}
            numberOfLines={5}
          >
            {sharedContent}
          </Text>

          {/* Character Count */}
          {sharedContent.length > 200 && (
            <Text
              className="text-xs text-gray-500"
              style={{ color: colors.textTertiary }}
            >
              {sharedContent.length} characters
            </Text>
          )}

          {/* Image Preview */}
          {imageUri && (
            <View className="mt-4">
              <Image
                source={{ uri: imageUri }}
                style={{
                  width: '100%',
                  height: 200,
                  borderRadius: 8,
                  backgroundColor: colors.border,
                }}
                onError={(e) => console.warn('[ShareComposer] Image load error:', e)}
              />
            </View>
          )}
        </View>

        {/* Topic Picker */}
        <View className="mb-4">
          <Text
            className="text-sm font-semibold mb-2"
            style={{ color: colors.text }}
          >
            Topic
          </Text>
          <TouchableOpacity
            className="border border-gray-300 rounded-lg px-4 py-3"
            style={{ borderColor: colors.border }}
            // TODO: Open topic picker modal
          >
            <Text style={{ color: colors.text }}>
              {selectedTopicId ? 'Selected topic' : 'Default (last used)'}
            </Text>
          </TouchableOpacity>
        </View>

        {/* Note Input */}
        <View className="mb-4">
          <Text
            className="text-sm font-semibold mb-2"
            style={{ color: colors.text }}
          >
            Add a note (optional)
          </Text>
          {/* TODO: Replace with @nself/ui TextInput */}
          <TextInput
            style={{
              borderColor: colors.border,
              borderWidth: 1,
              borderRadius: 8,
              padding: 12,
              color: colors.text,
              minHeight: 80,
              textAlignVertical: 'top',
            }}
            placeholder="Add a note..."
            placeholderTextColor={colors.textSecondary}
            multiline
            value={note}
            onChangeText={setNote}
          />
        </View>

        {/* Error Message */}
        {error && (
          <View className="mb-4 bg-red-100 p-3 rounded-lg">
            <Text style={{ color: '#dc2626' }}>{error}</Text>
          </View>
        )}

        {/* Save Button */}
        <TouchableOpacity
          onPress={handleSave}
          disabled={saving}
          className="bg-blue-600 rounded-lg py-3 flex-row justify-center items-center"
          style={{
            backgroundColor: saving ? colors.disabled : colors.primary,
            opacity: saving ? 0.6 : 1,
          }}
          accessibilityLabel="Save to memory"
          accessibilityRole="button"
        >
          {saving && <ActivityIndicator size="small" color="white" />}
          <Text className="text-white font-semibold ml-2">
            {saving ? 'Saving...' : 'Save to memory'}
          </Text>
        </TouchableOpacity>
      </ScrollView>
    </AsyncScreen>
  );
}
