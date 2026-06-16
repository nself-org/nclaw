/**
 * ApiClient — HTTP client for all claw-web ↔ backend communication.
 *
 * Purpose: Centralise all fetch calls; return Result<T, ClawError> from every
 *          public method so callers never encounter surprise runtime throws.
 *          Streaming endpoints (sendMessageRaw) return Result<ReadableStream> and
 *          never re-throw either.
 *
 * Inputs:  Per-method typed request shapes.
 * Outputs: Result<T, ClawError> for every fallible operation (see lib/result.ts).
 *
 * Constraints:
 *   - No `throw` statements in this file (grep enforced in CI / CR-A).
 *   - sendMessage (EventSource) is a fire-and-forget legacy path — avoid in new code.
 *   - setToken() is NOT async and MUST be called synchronously before any request.
 *
 * SPORT: REGISTRY-WEB-SURFACES.md — nclaw claw-web: typed errors
 */

import type {
  AuthTokens,
  Conversation,
  KnowledgeItem,
  Message,
  ModelSelection,
  OllamaModel,
  Page,
  PoolAccount,
  SendMessageRequest,
  SettingsData,
  StreamChunk,
  SystemInfo,
  Topic,
  User,
  VoiceCallSession,
} from '@/types';
import {
  type ClawError,
  type Result,
  err,
  httpError,
  networkError,
  ok,
} from '@/lib/result';

const BASE_URL =
  process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:8080/api';

class ApiClient {
  private accessToken: string | null = null;

  setToken(token: string | null) {
    this.accessToken = token;
  }

  private headers(extra?: Record<string, string>): HeadersInit {
    const h: Record<string, string> = {
      'Content-Type': 'application/json',
      ...extra,
    };
    if (this.accessToken) h['Authorization'] = `Bearer ${this.accessToken}`;
    return h;
  }

  /**
   * Core fetch wrapper — returns Result<T, ClawError>. Never throws.
   */
  private async request<T>(
    path: string,
    init: RequestInit = {}
  ): Promise<Result<T, ClawError>> {
    let res: Response;
    try {
      res = await fetch(`${BASE_URL}${path}`, {
        ...init,
        headers: {
          ...this.headers(),
          ...(init.headers as Record<string, string> | undefined),
        },
      });
    } catch (cause) {
      return err(networkError(cause));
    }

    if (!res.ok) {
      const body = await res
        .json()
        .catch(() => ({ message: res.statusText })) as {
          message?: string;
          code?: string;
          retryAfter?: number;
        };
      return err(httpError(res.status, body));
    }

    try {
      const data = (await res.json()) as T;
      return ok(data);
    } catch (cause) {
      return err(networkError(cause));
    }
  }

  // ─── Auth ────────────────────────────────────────────────────────────────

  async signIn(email: string, password: string): Promise<Result<AuthTokens, ClawError>> {
    return this.request('/auth/signin', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    });
  }

  async refreshToken(refreshToken: string): Promise<Result<AuthTokens, ClawError>> {
    return this.request('/auth/refresh', {
      method: 'POST',
      body: JSON.stringify({ refreshToken }),
    });
  }

  async signOut(): Promise<Result<void, ClawError>> {
    return this.request('/auth/signout', { method: 'POST' });
  }

  // ─── User ────────────────────────────────────────────────────────────────

  async getMe(): Promise<Result<User, ClawError>> {
    return this.request('/users/me');
  }

  async updateMe(
    updates: Partial<Pick<User, 'displayName' | 'bio' | 'avatarUrl'>>
  ): Promise<Result<User, ClawError>> {
    return this.request('/users/me', {
      method: 'PATCH',
      body: JSON.stringify(updates),
    });
  }

  // ─── Settings ────────────────────────────────────────────────────────────

  async getSettings(): Promise<Result<SettingsData, ClawError>> {
    return this.request('/settings');
  }

  async updateSettings(
    updates: Partial<SettingsData>
  ): Promise<Result<SettingsData, ClawError>> {
    return this.request('/settings', {
      method: 'PATCH',
      body: JSON.stringify(updates),
    });
  }

  // ─── Conversations (sessions) ─────────────────────────────────────────────

  async listConversations(
    page = 1,
    pageSize = 50
  ): Promise<Result<Page<Conversation>, ClawError>> {
    return this.request(
      `/claw/conversations?page=${page}&pageSize=${pageSize}`
    );
  }

  async getConversation(
    id: string
  ): Promise<Result<Conversation, ClawError>> {
    return this.request(`/claw/conversations/${id}`);
  }

  async createConversation(
    topicId?: string
  ): Promise<Result<Conversation, ClawError>> {
    return this.request('/claw/conversations', {
      method: 'POST',
      body: JSON.stringify({ topicId: topicId ?? null }),
    });
  }

  async deleteConversation(id: string): Promise<Result<void, ClawError>> {
    return this.request(`/claw/conversations/${id}`, { method: 'DELETE' });
  }

  async generateTitle(
    id: string
  ): Promise<Result<{ title: string }, ClawError>> {
    return this.request(`/claw/conversations/${id}/generate-title`, {
      method: 'POST',
    });
  }

  async backfillUntitledTitles(): Promise<
    Result<{ updated: number; skipped: number }, ClawError>
  > {
    return this.request('/claw/conversations/backfill-titles', {
      method: 'POST',
    });
  }

  // ─── Messages ────────────────────────────────────────────────────────────

  async listMessages(
    conversationId: string
  ): Promise<Result<Page<Message>, ClawError>> {
    return this.request(
      `/claw/conversations/${conversationId}/messages?pageSize=200`
    );
  }

  /**
   * sendMessage — legacy EventSource path (fire-and-forget).
   * Prefer sendMessageResult for new call sites.
   */
  sendMessage(req: SendMessageRequest): EventSource {
    const url = new URL(`${BASE_URL}/claw/chat/stream`);
    if (this.accessToken) url.searchParams.set('token', this.accessToken);
    const es = new EventSource(url.toString());
    void fetch(`${BASE_URL}/claw/chat/stream`, {
      method: 'POST',
      headers: this.headers(),
      body: JSON.stringify(req),
    });
    return es;
  }

  /**
   * sendMessageRaw — streaming chat; returns Result<ReadableStream, ClawError>.
   * Never throws. On non-OK response or missing body, returns Err.
   */
  async sendMessageRaw(
    req: SendMessageRequest
  ): Promise<Result<ReadableStream<StreamChunk>, ClawError>> {
    let res: Response;
    try {
      res = await fetch(`${BASE_URL}/claw/chat/stream`, {
        method: 'POST',
        headers: this.headers(),
        body: JSON.stringify(req),
      });
    } catch (cause) {
      return err(networkError(cause));
    }

    if (!res.ok) {
      const body = await res
        .json()
        .catch(() => ({ message: res.statusText })) as {
          message?: string;
          code?: string;
          retryAfter?: number;
        };
      return err(httpError(res.status, body));
    }

    if (!res.body) {
      return err({
        type: 'network',
        message: 'Stream body is null',
        retryable: true,
      });
    }

    const reader = res.body.getReader();
    const decoder = new TextDecoder();

    return ok(
      new ReadableStream<StreamChunk>({
        async pull(controller) {
          const { done, value } = await reader.read();
          if (done) {
            controller.close();
            return;
          }
          const text = decoder.decode(value);
          for (const line of text.split('\n')) {
            if (line.startsWith('data: ')) {
              const chunk = JSON.parse(line.slice(6)) as StreamChunk;
              controller.enqueue(chunk);
            }
          }
        },
      })
    );
  }

  // ─── Topics ───────────────────────────────────────────────────────────────

  async listTopics(): Promise<Result<Topic[], ClawError>> {
    return this.request('/claw/topics');
  }

  async getTopicTree(): Promise<Result<Topic[], ClawError>> {
    return this.request('/claw/topics/tree');
  }

  // ─── Models ───────────────────────────────────────────────────────────────

  async listModels(): Promise<Result<OllamaModel[], ClawError>> {
    return this.request('/claw/models');
  }

  async getSystemInfo(): Promise<Result<SystemInfo, ClawError>> {
    return this.request('/claw/system-info');
  }

  async getModelSelection(): Promise<Result<ModelSelection, ClawError>> {
    return this.request('/claw/models/selection');
  }

  async setModelSelection(
    sel: ModelSelection
  ): Promise<Result<ModelSelection, ClawError>> {
    return this.request('/claw/models/selection', {
      method: 'PUT',
      body: JSON.stringify(sel),
    });
  }

  async pullModel(
    modelId: string
  ): Promise<Result<{ taskId: string }, ClawError>> {
    return this.request('/claw/models/pull', {
      method: 'POST',
      body: JSON.stringify({ modelId }),
    });
  }

  // ─── Pool accounts ────────────────────────────────────────────────────────

  async listPoolAccounts(): Promise<Result<PoolAccount[], ClawError>> {
    return this.request('/claw/pool');
  }

  async addPoolAccount(
    provider: PoolAccount['provider']
  ): Promise<Result<{ oauthUrl: string }, ClawError>> {
    return this.request('/claw/pool', {
      method: 'POST',
      body: JSON.stringify({ provider }),
    });
  }

  async removePoolAccount(id: string): Promise<Result<void, ClawError>> {
    return this.request(`/claw/pool/${id}`, { method: 'DELETE' });
  }

  async refreshPoolAccount(
    id: string
  ): Promise<Result<PoolAccount, ClawError>> {
    return this.request(`/claw/pool/${id}/refresh`, { method: 'POST' });
  }

  // ─── Voice call (LiveKit) ─────────────────────────────────────────────────

  async startVoiceCall(): Promise<Result<VoiceCallSession, ClawError>> {
    return this.request('/claw/voice/call/start', { method: 'POST' });
  }

  async endVoiceCall(
    roomName: string,
    transcript: string
  ): Promise<Result<{ memoryId: string }, ClawError>> {
    return this.request('/claw/voice/call/end', {
      method: 'POST',
      body: JSON.stringify({ roomName, transcript }),
    });
  }

  // ─── Knowledge ingest (PDF / audio / video) ───────────────────────────────

  /**
   * ingestFile — multipart upload via XHR (supports progress reporting).
   * Returns Result<KnowledgeItem, ClawError>; never rejects.
   */
  ingestFile(
    type: 'pdf' | 'audio' | 'video',
    file: File,
    onProgress?: (pct: number) => void
  ): Promise<Result<KnowledgeItem, ClawError>> {
    return new Promise((resolve) => {
      const formData = new FormData();
      formData.append('file', file);

      const xhr = new XMLHttpRequest();
      xhr.open('POST', `${BASE_URL}/claw/ingest/${type}`);
      if (this.accessToken)
        xhr.setRequestHeader('Authorization', `Bearer ${this.accessToken}`);

      xhr.upload.onprogress = (evt) => {
        if (evt.lengthComputable && onProgress) {
          onProgress(Math.round((evt.loaded / evt.total) * 100));
        }
      };

      xhr.onload = () => {
        if (xhr.status >= 200 && xhr.status < 300) {
          resolve(ok(JSON.parse(xhr.responseText) as KnowledgeItem));
        } else {
          const body = JSON.parse(xhr.responseText) as {
            message?: string;
            code?: string;
          } | null;
          resolve(
            err(
              httpError(xhr.status, {
                message: body?.message ?? `Ingest failed: ${xhr.status}`,
                code: body?.code,
              })
            )
          );
        }
      };

      xhr.onerror = () =>
        resolve(err(networkError(new Error('Network error during upload'))));

      xhr.send(formData);
    });
  }

  // ─── Knowledge items ──────────────────────────────────────────────────────

  async listKnowledge(
    page = 1,
    pageSize = 50
  ): Promise<Result<Page<KnowledgeItem>, ClawError>> {
    return this.request(`/claw/knowledge?page=${page}&pageSize=${pageSize}`);
  }
}

export const api = new ApiClient();
export default api;
