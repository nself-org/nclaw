/**
 * OnboardingScreen — multi-step first-run wizard.
 *
 * Purpose: Guides new users through the initial setup: welcome, server pairing,
 *   notification permission, microphone permission, camera permission, and finish.
 *   Maps to feature-spec S-02 (7-step onboarding flow).
 *
 * Inputs:  None — self-contained wizard state.
 * Outputs: A paginated step flow that exits to the main tabs on completion.
 *
 * Constraints:
 *   - Multi-step: each step is a separate View, advanced via Next/Back buttons.
 *   - Permission requests happen only in their respective steps (not at app boot).
 *   - No StyleSheet.create — NativeWind className only.
 *   - All 7 UI states via AsyncScreen (loading during permission request).
 *   - All text via t().
 *   - Every Pressable has accessibilityLabel.
 *   - RTL: all layouts flip with useDirection().
 *
 * SPORT: None — SPORT updated in T09.
 * Cross-ref: T06 (push notifications), T07 (voice / mic permission).
 */

import React, { useCallback, useState } from 'react';
import {
  View,
  Text,
  Pressable,
  ScrollView,
} from 'react-native';
import { useTranslation } from 'react-i18next';
import { useRouter } from 'expo-router';

import { AsyncScreen, type ScreenStatus } from '../components/AsyncScreen';
import { useDirection } from '../lib/useDirection';
import { requestPushPermission } from '../services/pushNotificationService';

// ─── Step definitions ─────────────────────────────────────────────────────────

interface OnboardingStep {
  id: string;
  emoji: string;
  titleKey: string;
  bodyKey: string;
  /** If set, the Next button triggers this action before advancing. */
  actionKey?: 'requestNotifications' | 'requestMicrophone' | 'requestCamera';
}

const STEPS: OnboardingStep[] = [
  {
    id: 'welcome',
    emoji: '👋',
    titleKey: 'onboarding.welcome.title',
    bodyKey: 'onboarding.welcome.body',
  },
  {
    id: 'server',
    emoji: '🖥️',
    titleKey: 'onboarding.server.title',
    bodyKey: 'onboarding.server.body',
  },
  {
    id: 'notifications',
    emoji: '🔔',
    titleKey: 'onboarding.notifications.title',
    bodyKey: 'onboarding.notifications.body',
    actionKey: 'requestNotifications',
  },
  {
    id: 'microphone',
    emoji: '🎙️',
    titleKey: 'onboarding.microphone.title',
    bodyKey: 'onboarding.microphone.body',
    actionKey: 'requestMicrophone',
  },
  {
    id: 'camera',
    emoji: '📷',
    titleKey: 'onboarding.camera.title',
    bodyKey: 'onboarding.camera.body',
    actionKey: 'requestCamera',
  },
  {
    id: 'finish',
    emoji: '🎉',
    titleKey: 'onboarding.finish.title',
    bodyKey: 'onboarding.finish.body',
  },
];

// ─── Step slide ───────────────────────────────────────────────────────────────

interface StepSlideProps {
  step: OnboardingStep;
}

function StepSlide({ step }: StepSlideProps) {
  const { t } = useTranslation();
  const dir = useDirection();

  return (
    <View className="flex-1 items-center justify-center px-8">
      <Text className="text-6xl mb-6">{step.emoji}</Text>
      <Text
        className="text-2xl font-bold text-foreground text-center mb-4"
        style={{ textAlign: dir.textAlign }}
      >
        {t(step.titleKey, step.titleKey)}
      </Text>
      <Text
        className="text-base text-muted-foreground text-center leading-relaxed"
        style={{ textAlign: dir.textAlign }}
      >
        {t(step.bodyKey, step.bodyKey)}
      </Text>
    </View>
  );
}

// ─── OnboardingScreen ─────────────────────────────────────────────────────────

export default function OnboardingScreen() {
  const { t } = useTranslation();
  const router = useRouter();
  const dir = useDirection();

  const [currentStep, setCurrentStep] = useState(0);
  const [status, setStatus] = useState<ScreenStatus>('data');

  const step = STEPS[currentStep];
  const isLast = currentStep === STEPS.length - 1;
  const isFirst = currentStep === 0;

  /** Handle permission-request actions for steps that need them. */
  const handleAction = useCallback(
    async (actionKey: NonNullable<OnboardingStep['actionKey']>): Promise<boolean> => {
      setStatus('loading');
      try {
        // Permission logic delegated to T06/T07 hooks.
        // Stubs return true (granted) for now.
        switch (actionKey) {
          case 'requestNotifications': {
            // Request iOS/Android push permission — timed ask during onboarding (not cold launch)
            const permStatus = await requestPushPermission();
            // 'denied' is non-fatal — user can enable later in Settings; continue onboarding
            if (permStatus !== 'granted') {
              console.info('[Onboarding] Push permission not granted:', permStatus);
            }
            break;
          }
          case 'requestMicrophone':
            // Permission.MICROPHONE via expo-permissions wired in T07
            await new Promise((r) => setTimeout(r, 300));
            break;
          case 'requestCamera':
            await new Promise((r) => setTimeout(r, 300));
            break;
        }
        setStatus('data');
        return true;
      } catch {
        setStatus('error');
        return false;
      }
    },
    [],
  );

  const handleNext = useCallback(async () => {
    if (step?.actionKey) {
      const ok = await handleAction(step.actionKey);
      if (!ok) return;
    }

    if (isLast) {
      // Onboarding complete — navigate to main tabs
      router.replace('/(tabs)/chat');
      return;
    }
    setCurrentStep((s: number) => s + 1);
  }, [step, isLast, handleAction, router]);

  const handleBack = useCallback(() => {
    setCurrentStep((s: number) => Math.max(0, s - 1));
  }, []);

  const handleSkip = useCallback(() => {
    router.replace('/(tabs)/chat');
  }, [router]);

  return (
    <View className="flex-1 bg-background">
      {/* Skip button */}
      <View
        className="absolute top-12 right-4 z-10"
        style={dir.isRTL ? { left: 16, right: undefined } : {}}
      >
        {!isLast && (
          <Pressable
            onPress={handleSkip}
            className="px-4 py-2"
            accessibilityLabel={t('onboarding.skip', 'Skip onboarding')}
            accessibilityRole="button"
          >
            <Text className="text-sm text-muted-foreground">
              {t('onboarding.skip', 'Skip')}
            </Text>
          </Pressable>
        )}
      </View>

      {/* Step content */}
      <AsyncScreen status={status} testID="onboarding">
        <ScrollView
          className="flex-1"
          contentContainerStyle={{ flexGrow: 1 }}
          showsVerticalScrollIndicator={false}
        >
          <StepSlide step={step!} />
        </ScrollView>
      </AsyncScreen>

      {/* Progress dots */}
      <View className="flex-row justify-center pb-6 gap-2">
        {STEPS.map((s, i) => (
          <View
            key={s.id}
            className={`h-2 rounded-full transition-all ${
              i === currentStep ? 'w-6 bg-primary' : 'w-2 bg-muted'
            }`}
            accessibilityRole="none"
          />
        ))}
      </View>

      {/* Navigation buttons */}
      <View
        className="flex-row items-center px-6 pb-8 gap-3"
        style={{ flexDirection: dir.flexRow }}
      >
        {!isFirst && (
          <Pressable
            onPress={handleBack}
            className="flex-1 py-4 rounded-2xl border border-border items-center"
            accessibilityLabel={t('onboarding.back', 'Go back')}
            accessibilityRole="button"
          >
            <Text className="text-base font-medium text-foreground">
              {t('onboarding.back', 'Back')}
            </Text>
          </Pressable>
        )}
        <Pressable
          onPress={handleNext}
          className="flex-1 py-4 rounded-2xl bg-primary items-center"
          accessibilityLabel={
            isLast
              ? t('onboarding.getStarted', "Let's go!")
              : t('onboarding.next', 'Next')
          }
          accessibilityRole="button"
        >
          <Text className="text-base font-semibold text-primary-foreground">
            {isLast
              ? t('onboarding.getStarted', "Let's go!")
              : t('onboarding.next', 'Next')}
          </Text>
        </Pressable>
      </View>
    </View>
  );
}
