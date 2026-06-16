/** Authenticated user record returned by the nSelf auth service. */
export interface User {
  id: string;
  email: string;
  displayName: string | null;
  avatarUrl: string | null;
  bio: string | null;
  createdAt: string;
}

/** A conversation thread in ɳClaw. */
export interface Conversation {
  id: string;
  title: string;
  topicId: string | null;
  createdAt: string;
  updatedAt: string;
  messageCount: number;
  lastMessageAt: string | null;
}

/** A single chat message. */
export interface Message {
  id: string;
  conversationId: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  createdAt: string;
  tokens: number | null;
}

/** A memory topic extracted by the claw plugin. */
export interface Topic {
  id: string;
  name: string;
  slug: string;
  parentId: string | null;
  conversationCount: number;
  updatedAt: string;
  children?: Topic[];
}

/** A memory entity (fact, decision, person, etc.) */
export interface MemoryEntity {
  id: string;
  type: 'fact' | 'decision' | 'person' | 'place' | 'event' | 'preference';
  content: string;
  confidence: number;
  topicIds: string[];
  sourceConversationId: string | null;
  createdAt: string;
  updatedAt: string;
}

/** API error shape. */
export interface ApiError {
  message: string;
  code: string;
  status: number;
}

/** Paginated response wrapper. */
export interface Page<T> {
  data: T[];
  total: number;
  page: number;
  pageSize: number;
  hasMore: boolean;
}

/** Auth token pair. */
export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
}

/** Send-message request body. */
export interface SendMessageRequest {
  conversationId: string | null;
  content: string;
  topicId?: string | null;
  modelId?: string | null;
}

/** Stream chunk from the AI response. */
export interface StreamChunk {
  type: 'delta' | 'done' | 'error';
  content?: string;
  conversationId?: string;
  messageId?: string;
  error?: string;
}

/** Ollama model with hardware requirements. */
export interface OllamaModel {
  id: string;
  name: string;
  displayName: string;
  family: string;
  parameterCount: string;
  ramRequiredGb: number;
  quantization: string;
  isInstalled: boolean;
  isRunning: boolean;
  sizeOnDiskGb: number | null;
}

/** Current model selection config. */
export interface ModelSelection {
  mode: 'auto' | 'manual';
  modelId: string | null;
  autoStrategy: 'fastest' | 'balanced' | 'best';
}

/** Pool account for OAuth provider integration. */
export interface PoolAccount {
  id: string;
  provider: 'google' | 'microsoft' | 'github' | 'custom';
  email: string;
  displayName: string | null;
  scopes: string[];
  isActive: boolean;
  lastUsedAt: string | null;
  expiresAt: string | null;
  createdAt: string;
}

/** Settings data blob. */
export interface SettingsData {
  displayName: string | null;
  bio: string | null;
  avatarUrl: string | null;
  modelSelection: ModelSelection;
  notificationsEnabled: boolean;
  compactMode: boolean;
  language: string;
  timezone: string;
  dataRetentionDays: number | null;
  autoTitleSessions: boolean;
  emailDigestEnabled: boolean;
}

/** Onboarding wizard step IDs. */
export type OnboardingStepId =
  | 'welcome'
  | 'server'
  | 'oauth'
  | 'model'
  | 'profile'
  | 'preview'
  | 'done';

/** System RAM info returned by backend. */
export interface SystemInfo {
  totalRamGb: number;
  availableRamGb: number;
  gpuName: string | null;
  gpuVramGb: number | null;
}

/** Empty state variant. */
export type EmptyStateVariant =
  | 'firstTime'
  | 'error'
  | 'offline'
  | 'noResults'
  | 'loading'
  | 'forbidden'
  | 'searchEmpty';

/** LiveKit voice call session returned by POST /claw/voice/call/start. */
export interface VoiceCallSession {
  /** LiveKit server URL, e.g. wss://livekit.example.com */
  livekitUrl: string;
  /** Short-lived participant token scoped to this room. */
  participantToken: string;
  /** Unique room identifier. */
  roomName: string;
}

/** A knowledge item created by an ingest flow. */
export interface KnowledgeItem {
  id: string;
  type: 'pdf' | 'audio' | 'video' | 'text';
  title: string;
  summary: string | null;
  sourceFilename: string;
  sizeBytes: number;
  createdAt: string;
}

/** Progress steps used by ProgressIngest component. */
export type IngestStep = 'uploading' | 'processing' | 'indexing' | 'done';

/**
 * Cursor-paginated page result used by usePagination hook.
 * nextCursor is null when no further pages exist.
 */
export interface FetchPageResult<T> {
  items: T[];
  nextCursor: string | null;
}

/** Offline-cache conversation row stored in IndexedDB. */
export interface CachedConversation {
  id: string;
  title: string;
  topicId: string | null;
  updatedAt: string;
  lastMessageAt: string | null;
  messageCount: number;
  messages: Message[];
  cachedAt: number; // Date.now() when cached
}
