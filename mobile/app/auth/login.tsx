/**
 * nclaw/mobile — Login screen.
 *
 * Purpose: Email + password sign-in form using @nself/auth-core NativeAuthStrategy.
 *          JWT stored in expo-secure-store on success (handled by NativeAuthStrategy).
 *          On success, root index redirects to /(tabs)/chat via AuthState change.
 * Inputs:  Email and password from user input.
 * Outputs: AuthState change triggers redirect via root index.tsx.
 * Constraints:
 *   - expo-secure-store stores JWT — never AsyncStorage for auth tokens.
 *   - Never log email/password or accessToken.
 *   - authStrategy.login() returns AuthState; check status field.
 * SPORT: F08-SERVICE-INVENTORY.md (nclaw-mobile-rn)
 */

import { useAuthStrategy } from '@nself/auth-core';
import { useState } from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  Text,
  TextInput,
  View,
} from 'react-native';

export default function LoginScreen(): React.JSX.Element {
  const strategy = useAuthStrategy();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const handleLogin = async (): Promise<void> => {
    if (!email.trim() || !password.trim()) {
      setErrorMessage('Email and password are required.');
      return;
    }

    setIsLoading(true);
    setErrorMessage(null);

    try {
      const result = await strategy.login(email.trim(), password);

      if (result.status === 'error') {
        setErrorMessage(result.error.message ?? 'Sign-in failed. Please try again.');
      }
      // On 'authenticated': root index.tsx receives AuthState update and redirects
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <KeyboardAvoidingView
      className='flex-1 justify-center px-8 bg-surface'
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
    >
      <Text className='text-3xl font-bold text-white mb-2'>ɳClaw</Text>
      <Text className='text-base text-slate-400 mb-8'>
        Sign in to your nSelf server
      </Text>

      <TextInput
        className='bg-surface-elevated text-white rounded-xl px-4 py-3 mb-4 border border-slate-700 text-base'
        placeholder='Email'
        placeholderTextColor='#64748b'
        autoCapitalize='none'
        autoCorrect={false}
        keyboardType='email-address'
        textContentType='emailAddress'
        value={email}
        onChangeText={setEmail}
        editable={!isLoading}
      />

      <TextInput
        className='bg-surface-elevated text-white rounded-xl px-4 py-3 mb-4 border border-slate-700 text-base'
        placeholder='Password'
        placeholderTextColor='#64748b'
        secureTextEntry
        textContentType='password'
        value={password}
        onChangeText={setPassword}
        editable={!isLoading}
        onSubmitEditing={handleLogin}
      />

      {errorMessage !== null && (
        <Text className='text-red-400 text-sm mb-4'>{errorMessage}</Text>
      )}

      <Pressable
        className='bg-brand rounded-xl py-4 items-center'
        onPress={handleLogin}
        disabled={isLoading}
      >
        {isLoading ? (
          <ActivityIndicator color='#ffffff' />
        ) : (
          <Text className='text-white font-semibold text-base'>Sign In</Text>
        )}
      </Pressable>
    </KeyboardAvoidingView>
  );
}
