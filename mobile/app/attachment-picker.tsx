/**
 * AttachmentPickerScreen — image/document picker for chat file attachments.
 *
 * Purpose: Presents a modal-style picker for choosing files to attach to
 *   a chat message. Uses expo-document-picker for documents and
 *   expo-image-picker for photos. Returns the picked file to the chat screen
 *   via router params / shared state (wired in T08).
 *
 * Inputs:  None — picker is self-contained.
 * Outputs: Picked file metadata returned to the calling screen.
 *
 * Constraints:
 *   - expo-document-picker: DocumentPicker.getDocumentAsync().
 *   - expo-image-picker: ImagePicker.launchImageLibraryAsync().
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen.
 *   - All text via t().
 *   - Every Pressable has accessibilityLabel.
 *   - RTL: all layouts flip with useDirection().
 *
 * SPORT: None — SPORT updated in T09.
 * Cross-ref: T08 (file attachment backend wiring).
 */

import React, { useCallback, useState } from 'react';
import {
  View,
  Text,
  Pressable,
  FlatList,
} from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';
import * as DocumentPicker from 'expo-document-picker';
import * as ImagePicker from 'expo-image-picker';

import { AsyncScreen, type ScreenStatus } from '../components/AsyncScreen';
import { useDirection } from '../lib/useDirection';
import type { PickedFile } from '../types/chat';

// ─── Attachment option ────────────────────────────────────────────────────────

interface AttachmentOption {
  id: string;
  emoji: string;
  titleKey: string;
  descriptionKey: string;
  onSelect: () => Promise<PickedFile | null>;
}

// ─── AttachmentPickerScreen ───────────────────────────────────────────────────

export default function AttachmentPickerScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();

  const [status, setStatus] = useState<ScreenStatus>('data');
  const [pickedFiles, setPickedFiles] = useState<PickedFile[]>([]);

  /** Pick a document using expo-document-picker. */
  const pickDocument = useCallback(async (): Promise<PickedFile | null> => {
    try {
      const result = await DocumentPicker.getDocumentAsync({
        type: '*/*',
        copyToCacheDirectory: true,
        multiple: false,
      });
      if (result.canceled || !result.assets?.[0]) return null;
      const asset = result.assets[0];
      return {
        uri: asset.uri,
        name: asset.name,
        mimeType: asset.mimeType ?? 'application/octet-stream',
        size: asset.size ?? 0,
      };
    } catch {
      return null;
    }
  }, []);

  /** Pick an image from the device photo library. */
  const pickImage = useCallback(async (): Promise<PickedFile | null> => {
    const { status: permStatus } =
      await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (permStatus !== 'granted') return null;

    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      allowsMultipleSelection: false,
      quality: 0.85,
    });
    if (result.canceled || !result.assets?.[0]) return null;
    const asset = result.assets[0];
    return {
      uri: asset.uri,
      name: asset.fileName ?? `image_${Date.now()}.jpg`,
      mimeType: asset.mimeType ?? 'image/jpeg',
      size: asset.fileSize ?? 0,
    };
  }, []);

  /** Pick a photo using the camera. */
  const capturePhoto = useCallback(async (): Promise<PickedFile | null> => {
    const { status: permStatus } =
      await ImagePicker.requestCameraPermissionsAsync();
    if (permStatus !== 'granted') return null;

    const result = await ImagePicker.launchCameraAsync({
      mediaTypes: ImagePicker.MediaTypeOptions.Images,
      quality: 0.85,
    });
    if (result.canceled || !result.assets?.[0]) return null;
    const asset = result.assets[0];
    return {
      uri: asset.uri,
      name: `photo_${Date.now()}.jpg`,
      mimeType: 'image/jpeg',
      size: asset.fileSize ?? 0,
    };
  }, []);

  const handleOption = useCallback(
    async (picker: () => Promise<PickedFile | null>) => {
      setStatus('loading');
      try {
        const file = await picker();
        if (file) {
          setPickedFiles((prev: PickedFile[]) => [...prev, file]);
          setStatus('data');
          // Pass picked file back to chat screen — wired in T08
          // router.back() with params
        } else {
          setStatus('data');
        }
      } catch {
        setStatus('error');
      }
    },
    [],
  );

  const ATTACHMENT_OPTIONS: AttachmentOption[] = [
    {
      id: 'document',
      emoji: '📄',
      titleKey: 'attach.document',
      descriptionKey: 'attach.documentHint',
      onSelect: pickDocument,
    },
    {
      id: 'photo',
      emoji: '🖼️',
      titleKey: 'attach.photo',
      descriptionKey: 'attach.photoHint',
      onSelect: pickImage,
    },
    {
      id: 'camera',
      emoji: '📷',
      titleKey: 'attach.camera',
      descriptionKey: 'attach.cameraHint',
      onSelect: capturePhoto,
    },
  ];

  return (
    <View className="flex-1 bg-background">
      {/* Header */}
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
        <Text
          className="flex-1 text-xl font-bold text-foreground"
          style={{ textAlign: dir.textAlign }}
        >
          {t('attach.title', 'Add Attachment')}
        </Text>
        {pickedFiles.length > 0 && (
          <Pressable
            onPress={() => router.back()}
            className="px-3 py-1 bg-primary rounded-xl"
            accessibilityLabel={`${t('attach.send', 'Send')} ${pickedFiles.length} ${t('attach.files', 'files')}`}
            accessibilityRole="button"
          >
            <Text className="text-primary-foreground text-sm font-medium">
              {t('attach.send', 'Send')} ({pickedFiles.length})
            </Text>
          </Pressable>
        )}
      </View>

      <AsyncScreen
        status={status}
        testID="attachment-picker"
        onRetry={() => setStatus('data')}
      >
        <View className="px-4 pt-6">
          {/* Options */}
          <View className="rounded-xl overflow-hidden border border-border mb-6">
            {ATTACHMENT_OPTIONS.map((option, index) => (
              <Pressable
                key={option.id}
                onPress={() => handleOption(option.onSelect)}
                className={`flex-row items-center px-4 py-4 bg-card ${
                  index < ATTACHMENT_OPTIONS.length - 1 ? 'border-b border-border' : ''
                }`}
                accessibilityLabel={t(option.titleKey, option.id)}
                accessibilityRole="button"
                style={{ flexDirection: dir.flexRow }}
              >
                <Text style={{ fontSize: 24 }} className="mr-3">
                  {option.emoji}
                </Text>
                <View className="flex-1">
                  <Text
                    className="text-base font-medium text-foreground"
                    style={{ textAlign: dir.textAlign }}
                  >
                    {t(option.titleKey, option.id)}
                  </Text>
                  <Text
                    className="text-sm text-muted-foreground"
                    style={{ textAlign: dir.textAlign }}
                  >
                    {t(option.descriptionKey, option.id)}
                  </Text>
                </View>
                <Text className="text-muted-foreground">
                  {dir.isRTL ? '‹' : '›'}
                </Text>
              </Pressable>
            ))}
          </View>

          {/* Picked files preview */}
          {pickedFiles.length > 0 && (
            <View>
              <Text
                className="text-sm font-semibold text-foreground mb-3"
                style={{ textAlign: dir.textAlign }}
              >
                {t('attach.selected', 'Selected files')} ({pickedFiles.length})
              </Text>
              <FlatList<PickedFile>
                data={pickedFiles}
                keyExtractor={(item: PickedFile, index: number) => `${item.uri}-${index}`}
                renderItem={({ item, index }: { item: PickedFile; index: number }) => (
                  <View
                    className="flex-row items-center bg-card rounded-xl px-4 py-3 mb-2 border border-border"
                    style={{ flexDirection: dir.flexRow }}
                    accessibilityRole="none"
                  >
                    <Text style={{ fontSize: 20 }} className="mr-3">
                      {item.mimeType.startsWith('image/') ? '🖼️' : '📄'}
                    </Text>
                    <View className="flex-1">
                      <Text
                        className="text-sm font-medium text-foreground"
                        style={{ textAlign: dir.textAlign }}
                        numberOfLines={1}
                      >
                        {item.name}
                      </Text>
                      <Text className="text-xs text-muted-foreground">
                        {(item.size / 1024).toFixed(1)} KB
                      </Text>
                    </View>
                    <Pressable
                      onPress={() =>
                        setPickedFiles((prev: PickedFile[]) => prev.filter((_: PickedFile, i: number) => i !== index))
                      }
                      className="p-2"
                      accessibilityLabel={`${t('attach.remove', 'Remove')} ${item.name}`}
                      accessibilityRole="button"
                    >
                      <Text className="text-destructive text-lg">✕</Text>
                    </Pressable>
                  </View>
                )}
                scrollEnabled={false}
              />
            </View>
          )}
        </View>
      </AsyncScreen>
    </View>
  );
}
