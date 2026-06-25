/**
 * Purpose: urql GraphQL client factory for ɳClaw desktop.
 *          Uses @nself/graphql-client NselfGraphqlClient with auth exchange from
 *          @nself/auth-core to attach Bearer tokens on every request.
 * Inputs:  authStrategy singleton from lib/auth.ts.
 * Outputs: graphqlClient (urql Client) consumed by urql Provider in main.tsx.
 * Constraints:
 *   - Client is created once at module level; never re-created on re-render.
 *   - VITE_NSELF_GRAPHQL_URL must be set in .env or .env.local for the Hasura endpoint.
 *   - createAuthExchange returns an Exchange; NselfGraphqlClient accepts it via authExchangeFn
 *     (typed as AuthExchangeFn but cast to Exchange internally in buildExchanges).
 * SPORT: F13-CROSS-REPO-DEPS.md — nclaw-desktop @nself/graphql-client
 */

import { NselfGraphqlClient, type AuthExchangeFn } from '@nself/graphql-client';
import { createAuthExchange } from '@nself/auth-core';
import { authStrategy } from './auth';

/** Singleton urql client with Bearer auth. Consumed by urql Provider in main.tsx. */
export const graphqlClient = NselfGraphqlClient({
  url: import.meta.env.VITE_NSELF_GRAPHQL_URL ?? 'https://api.nself.org/v1/graphql',
  // createAuthExchange returns an Exchange; cast satisfies the loose AuthExchangeFn type.
  authExchangeFn: createAuthExchange(authStrategy) as unknown as AuthExchangeFn,
});
