/**
 * Share Target Service — Handle incoming shares from iOS/Android
 *
 * Purpose: Parse share intent data and prepare for ShareComposerScreen.
 * Inputs: Native platform data (iOS UserDefaults via App Group, Android intent extras).
 * Outputs: Typed SharedItem{type, text, url, imageUri} for UI consumption.
 * Constraints: Must handle cold-launch (app not in memory) and hot-launch cases.
 */

import { Platform, NativeModules } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as FileSystem from 'expo-file-system';

const { ShareTargetModule } = NativeModules;

/**
 * Represents a single shared item (text, URL, or image).
 */
export interface SharedItem {
  type: 'text' | 'url' | 'image';
  text?: string;
  url?: string;
  title?: string;
  imageUri?: string;
  mimeType?: string;
}

/**
 * Retrieve shared content from platform-specific storage.
 *
 * iOS: Reads from App Group UserDefaults (written by ShareExtension).
 * Android: Reads from intent extras (handled by MainActivity).
 *
 * Returns null if no share was received.
 */
export async function getSharedContent(): Promise<SharedItem | null> {
  try {
    if (Platform.OS === 'ios') {
      return await _getIOSSharedContent();
    } else if (Platform.OS === 'android') {
      return await _getAndroidSharedContent();
    }
  } catch (error) {
    console.warn('[ShareTargetService] Error retrieving shared content:', error);
  }
  return null;
}

/**
 * iOS: Read from App Group UserDefaults.
 * ShareExtension writes JSON to UserDefaults under key 'SharedContent'.
 */
async function _getIOSSharedContent(): Promise<SharedItem | null> {
  // Retrieve from AsyncStorage (bridged from UserDefaults via native module)
  const stored = await AsyncStorage.getItem('NCLAW_SHARED_CONTENT');
  if (!stored) {
    return null;
  }

  try {
    const data = JSON.parse(stored);
    const item: SharedItem = {
      type: data.type || 'text',
      text: data.text,
      url: data.url,
      title: data.title,
      imageUri: data.imageUri,
      mimeType: data.mimeType,
    };
    return item;
  } catch (e) {
    console.warn('[ShareTargetService] Failed to parse iOS shared content:', e);
    return null;
  }
}

/**
 * Android: Read from intent extras via native module.
 * ShareTargetModule extracts SEND/SEND_MULTIPLE intent extras,
 * storing them in SharedPreferences for React consumption.
 */
async function _getAndroidSharedContent(): Promise<SharedItem | null> {
  try {
    // Call native module to extract intent extras
    if (ShareTargetModule && ShareTargetModule.getSharedData) {
      const data = await ShareTargetModule.getSharedData();
      if (!data) {
        return null;
      }

      const item: SharedItem = {
        type: data.type || 'text',
        text: data.text,
        url: data.url,
        title: data.title,
        imageUri: data.imageUri,
        mimeType: data.mimeType,
      };
      return item;
    }
  } catch (e) {
    console.warn('[ShareTargetService] Failed to get Android shared data:', e);
  }

  // Fallback: check AsyncStorage (for testing or if native module unavailable)
  try {
    const stored = await AsyncStorage.getItem('NCLAW_SHARED_CONTENT');
    if (stored) {
      const data = JSON.parse(stored);
      const item: SharedItem = {
        type: data.type || 'text',
        text: data.text,
        url: data.url,
        title: data.title,
        imageUri: data.imageUri,
        mimeType: data.mimeType,
      };
      return item;
    }
  } catch (e) {
    console.warn('[ShareTargetService] Fallback AsyncStorage parse failed:', e);
  }

  return null;
}

/**
 * Clear shared content after processing.
 * Called after SharedItem is consumed by ShareComposerScreen.
 */
export async function clearSharedContent(): Promise<void> {
  try {
    await AsyncStorage.removeItem('NCLAW_SHARED_CONTENT');
  } catch (e) {
    console.warn('[ShareTargetService] Error clearing shared content:', e);
  }
}

/**
 * Resolve a shared image URI to a local file path.
 *
 * If the image is remote, download it to temp directory.
 * If local (file://), return as-is.
 *
 * Returns: Local file:// URI or null if unavailable.
 */
export async function resolveImageUri(uri: string | undefined): Promise<string | null> {
  if (!uri) {
    return null;
  }

  if (uri.startsWith('file://')) {
    return uri;
  }

  // Remote image: download to temp
  try {
    const filename = `shared_image_${Date.now()}.jpg`;
    const target = `${FileSystem.cacheDirectory}${filename}`;
    const result = await FileSystem.downloadAsync(uri, target);
    return result.uri;
  } catch (e) {
    console.warn('[ShareTargetService] Failed to download shared image:', e);
    return null;
  }
}

/**
 * Navigate to share composer with pre-filled shared data.
 *
 * Intended for use in app initialization (e.g., in +layout.tsx or _layout.tsx).
 * Routes to app/share-composer passing shared data.
 */
export function buildShareDeepLink(item: SharedItem): string {
  const params = new URLSearchParams();
  if (item.text) params.append('text', item.text);
  if (item.url) params.append('url', item.url);
  if (item.title) params.append('title', item.title);
  if (item.imageUri) params.append('imageUri', item.imageUri);
  if (item.mimeType) params.append('mimeType', item.mimeType);

  return `nclaw://share?${params.toString()}`;
}
