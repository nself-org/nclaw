/**
 * nclaw/mobile — Auth route group layout.
 *
 * Purpose: Unauthenticated surface layout. Redirects to /(tabs) if user is
 *          already authenticated (guards against back-navigation to login).
 * Inputs:  useAuth hook state (AuthState from @nself/auth-core).
 * Outputs: Slot for auth screens, or redirect.
 * Constraints: No auth-gated content here — this group is the un-authed shell.
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 */

import { useAuth } from '@nself/auth-core';
import { Redirect, Slot } from 'expo-router';
import { View } from 'react-native';

export default function AuthLayout(): React.JSX.Element {
  const auth = useAuth();

  if (auth.status === 'authenticated') {
    return <Redirect href='/(tabs)/chat' />;
  }

  return (
    <View className='flex-1 bg-surface'>
      <Slot />
    </View>
  );
}
