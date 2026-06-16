/**
 * nclaw/mobile — Root index route.
 *
 * Purpose: Auth gate — redirect to /(tabs)/chat if authenticated, to /auth/login if not.
 * Inputs:  useAuth hook from @nself/auth-core (returns AuthState).
 * Outputs: Redirect only — no visual output.
 * Constraints:
 *   - Must not render any UI itself; delegate to tab or auth layout.
 *   - AuthState.status: 'loading' | 'authenticated' | 'unauthenticated' | 'error'
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 */

import { useAuth } from '@nself/auth-core';
import { Redirect } from 'expo-router';
import { View } from 'react-native';

export default function Index(): React.JSX.Element {
  const auth = useAuth();

  if (auth.status === 'loading') {
    // Splash still visible — no flicker
    return <View />;
  }

  if (auth.status === 'authenticated') {
    return <Redirect href='/(tabs)/chat' />;
  }

  return <Redirect href='/auth/login' />;
}
