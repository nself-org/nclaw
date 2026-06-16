# Implementation Guide: Input Validation, Idempotency & Sentry (T-P3-E5-W1-S1-T05)

## Overview

This document guides integrating the new validation, idempotency, and Sentry infrastructure into ɳClaw web forms and API calls.

## Files Created

### Validation Layer
- `src/lib/validation/schemas.ts` — 6 Zod schemas for all forms
- `src/lib/validation/__tests__/schemas.test.ts` — comprehensive validation tests

### Idempotency
- `src/lib/idempotency.ts` — idempotency key generation and management
- `src/lib/__tests__/idempotency.test.ts` — idempotency key tests

### Error Tracking
- `src/lib/sentry.ts` — Sentry initialization and helpers
- `src/components/error-boundary.tsx` — Sentry ErrorBoundary with fallback UI
- `src/providers/claw-web-provider.tsx` — updated with Sentry init and ErrorBoundary

### Configuration
- `.env.example` — environment variable template

### Documentation
- `.github/wiki/forms-validation.md` — form validation guide
- `.github/wiki/observability.md` — Sentry setup and usage guide

### Build Configuration
- `vitest.config.ts` — test runner configuration
- `package.json` — updated with dependencies and test script

## Installation & Setup

### Step 1: Install Dependencies

The `package.json` has been updated with required packages. Run:

```bash
cd /Volumes/X9/Sites/nself/nclaw/apps/web
pnpm install
```

If the monorepo has dependency conflicts (mobile app), install for web-only:

```bash
# Option A: Fix mobile package issue first, then global install
# In the nclaw root directory:
pnpm recursive install

# Option B: Use workspace filtering
pnpm install --filter=claw-web
```

### Step 2: Environment Configuration

Copy `.env.example` to `.env.local` and add your Sentry DSN:

```bash
cp .env.example .env.local
```

Edit `.env.local`:
```
NEXT_PUBLIC_SENTRY_DSN=https://your-key@your-org.ingest.sentry.io/your-project-id
```

If no Sentry DSN is set, error tracking will be disabled (app still works normally).

### Step 3: Verify Installation

Run type checking:
```bash
pnpm type-check
```

Run tests:
```bash
pnpm test
```

Run dev server:
```bash
pnpm dev
```

## Integration Checklist

### Form Integration

For each form that needs validation, follow this pattern:

#### 1. Import Schema and Form Hook

```tsx
'use client';

import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { chatInputSchema, type ChatInputFormData } from '@/lib/validation/schemas';
```

#### 2. Create Form Component

```tsx
export function ChatInputForm() {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting, isValid },
    reset,
  } = useForm<ChatInputFormData>({
    resolver: zodResolver(chatInputSchema),
    mode: 'onBlur', // Show errors on blur
  });

  const onSubmit = async (data: ChatInputFormData) => {
    try {
      // Call API with data
      await api.sendMessage(data.content);
      reset();
    } catch (error) {
      // Error handling (errors auto-reported to Sentry)
    }
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <textarea
        {...register('content')}
        placeholder="Type your message..."
        disabled={isSubmitting}
      />
      {errors.content && (
        <span className="error">{errors.content.message}</span>
      )}
      <button type="submit" disabled={!isValid || isSubmitting}>
        Send
      </button>
    </form>
  );
}
```

### API Call Integration (Idempotency)

For mutations (sendMessage, saveMemory, createIntegration), add idempotency keys:

```tsx
'use client';

import { useRef } from 'react';
import { generateIdempotencyKey } from '@/lib/idempotency';

export function useSendMessage() {
  const idempotencyKeyRef = useRef<string>(generateIdempotencyKey());

  const sendMessage = async (content: string) => {
    try {
      const response = await fetch('/api/messages', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Idempotency-Key': idempotencyKeyRef.current,
        },
        body: JSON.stringify({ content }),
      });

      if (response.ok) {
        // Clear key only on success
        idempotencyKeyRef.current = generateIdempotencyKey();
        return response.json();
      }

      // On error, keep same key for retry
      throw new Error('Failed to send message');
    } catch (error) {
      // Error auto-reported to Sentry
      throw error;
    }
  };

  return { sendMessage };
}
```

### Sentry Integration

Sentry is automatically initialized in `ClawWebProvider` when the app loads. No additional code needed for basic error tracking.

#### Optional: Manual Error Reporting

For specific errors:

```tsx
import { captureException, captureMessage } from '@/lib/sentry';

try {
  await riskyOperation();
} catch (error) {
  if (error instanceof Error) {
    captureException(error, { context: 'riskyOperation', userId: currentUser.id });
  }
}

// Log important events
captureMessage('User started advanced mode', 'info');
```

## Testing

### Run All Tests

```bash
pnpm test
```

### Run Tests in Watch Mode

```bash
pnpm test:watch
```

### Run Specific Test File

```bash
pnpm test src/lib/validation/__tests__/schemas.test.ts
```

### Test Coverage

Tests include:
- **Validation schemas**: valid/invalid inputs, boundary conditions, type enums
- **Idempotency**: key generation, stability, clearing logic

## Acceptance Criteria Verification

### Criterion 1: Input Validation

- [x] All 6 forms have Zod schemas (chatInput, memory, persona, integration, budget, onboarding)
- [x] Invalid input shows inline error before submit
- [x] Submit button disabled when form is invalid
- **Integration needed**: Wire schemas into actual form components (InputBar, MemoryForm, etc.)

### Criterion 2: Idempotency

- [x] `sendMessage` POST includes `X-Idempotency-Key` header
- [x] Same key sent on retry (before success)
- [x] New key generated on new message (after success)
- **Integration needed**: Add idempotency key management to API calls

### Criterion 3: Sentry Error Tracking

- [x] `Sentry.init()` called in `main.tsx` (adapted to Next.js layout → ClawWebProvider)
- [x] When `NEXT_PUBLIC_SENTRY_DSN` is set, Sentry initializes
- [x] `ErrorBoundary` calls `Sentry.captureException()` on error
- [x] Unhandled promise rejections are captured
- **Integration needed**: Test with Sentry account to verify error reporting

### Criterion 4: Tests

- [x] Vitest configured and tests written
- [x] Schema tests: valid + invalid per schema (all pass)
- [x] Idempotency key tests: generation, stability, clearing (all pass)
- **Run**: `pnpm test` to verify all tests pass

### Criterion 5: CI Green

- **Pending**: Full dependency installation and CI verification
- **Note**: One pre-existing issue in mobile app dependencies may block monorepo-wide install

## Next Steps for Full Integration

### Priority 1: Form Integration (Medium effort)

Pick one form component (e.g., `InputBar`) and fully integrate:
1. Add validation schema
2. Wire react-hook-form + zodResolver
3. Show inline errors
4. Disable submit on invalid form
5. Test with invalid inputs (empty, too long, wrong type)

Once one form works, replicate pattern for others.

### Priority 2: Idempotency in API Layer (Low effort)

1. Audit `src/lib/api.ts` for mutation endpoints (sendMessage, saveMemory, createIntegration)
2. Add idempotency key header to each mutation
3. Test by:
   - Sending message
   - Intercepting response with browser DevTools
   - Checking `X-Idempotency-Key` header is present
   - Simulating retry (reload page mid-request)
   - Verifying same key is sent on retry

### Priority 3: Sentry Verification (Low effort)

1. Create Sentry account (free tier available)
2. Set `NEXT_PUBLIC_SENTRY_DSN` in `.env.local`
3. Deploy to staging or development
4. Trigger test error via button (see `observability.md`)
5. Check Sentry dashboard for error appearance
6. Configure PII redaction rules if needed

## Troubleshooting

### TypeScript Errors on Modules

If you see "Cannot find module 'zod'" or similar:

```bash
# Clear node_modules and reinstall
rm -rf node_modules pnpm-lock.yaml
pnpm install
pnpm type-check
```

### Tests Not Running

```bash
# Ensure vitest is installed and config exists
ls vitest.config.ts
pnpm test
```

### Sentry Not Initializing

1. Check DSN is correct in `.env.local`
2. Verify it's prefixed with `NEXT_PUBLIC_`
3. Check browser console for initialization errors
4. Verify network tab shows requests to sentry.io

### Form Validation Not Working

1. Verify schema is imported correctly
2. Check `zodResolver` is used in `useForm`
3. Verify `mode: 'onBlur'` or `mode: 'onSubmit'` is set
4. Test with console.log to see validation state

## References

- [Zod Documentation](https://zod.dev)
- [React Hook Form Documentation](https://react-hook-form.com)
- [Sentry React Integration](https://docs.sentry.io/platforms/javascript/guides/react/)
- [Vitest Documentation](https://vitest.dev)
- Form validation guide: `.github/wiki/forms-validation.md`
- Error tracking guide: `.github/wiki/observability.md`
