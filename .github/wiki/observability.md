# ɳClaw Web Observability & Error Tracking

## Overview

ɳClaw web uses **Sentry** for error tracking and performance monitoring in production. The integration is optional and only activates if `NEXT_PUBLIC_SENTRY_DSN` environment variable is set.

## Architecture

```
App
  ├─ Sentry.init() in ClawWebProvider
  ├─ ErrorBoundaryWrapper (catches React errors)
  │  └─ Sentry.ErrorBoundary (reports to Sentry)
  └─ unhandledrejection listener (catches Promise rejections)
```

## Setup

### 1. Get a Sentry DSN

Visit [sentry.io](https://sentry.io) and create a new project for ɳClaw web:

1. Create account (if not already done)
2. Create new project → select React
3. Copy your **DSN** (looks like: `https://examplePublicKey@o0.ingest.sentry.io/0`)

### 2. Configure Environment Variable

Add to `.env.local` (development) or deployment settings (production):

```bash
NEXT_PUBLIC_SENTRY_DSN=https://your-dsn-here@o0.ingest.sentry.io/0
```

Note: Must be prefixed with `NEXT_PUBLIC_` to be available in browser.

### 3. Deploy

Sentry will automatically initialize on app load. Errors will start appearing in your Sentry dashboard within seconds.

## Usage

### Automatic Error Capture

The following are automatically captured without any code changes:

1. **React component errors** — caught by error boundary, reported with stack trace
2. **Unhandled promise rejections** — async errors caught by global listener
3. **Network errors** — TanStack Query errors via Sentry integration
4. **Performance metrics** — page load, API requests, long tasks (via BrowserTracing)

### Manual Error Reporting

For specific errors you want to report:

```tsx
import { captureException, captureMessage } from '@/lib/sentry';

try {
  await riskyOperation();
} catch (error) {
  if (error instanceof Error) {
    captureException(error, { context: 'riskyOperation' });
  }
}

// Log important events
captureMessage('User initiated export', 'info');
```

### Adding Context to Errors

Attach additional data to help debugging:

```tsx
import { captureException } from '@/lib/sentry';

try {
  await sendMessage(content);
} catch (error) {
  captureException(error, {
    messageLength: content.length,
    conversationId: activeConversation?.id,
    timestamp: new Date().toISOString(),
  });
}
```

### Performance Monitoring

Sentry automatically tracks:
- **Page navigation** timing
- **API request** duration
- **Long tasks** (>50ms)
- **Interaction to next paint** (INP)

No code needed — it's automatic via `BrowserTracing` integration.

### Custom Performance Tracking

For custom operations:

```tsx
import * as Sentry from '@sentry/react';

const transaction = Sentry.startTransaction({
  name: 'Large Import',
  op: 'task',
});

try {
  await importLargeDataset();
} finally {
  transaction.finish();
}
```

## Error Boundary Fallback UI

When an error is caught, users see a friendly fallback screen with:
- Clear error message
- Option to see error details (technical)
- "Try Again" button to reload

This is defined in `src/components/error-boundary.tsx`.

## Viewing Errors

1. Go to [sentry.io dashboard](https://sentry.io)
2. Select your ɳClaw project
3. Errors appear in real-time
4. Click any error to see:
   - Full stack trace
   - User context (browser, OS, etc.)
   - Associated events
   - Error rate over time

## Configuration

### Sampling Rate

Currently set to 10% (`tracesSampleRate: 0.1`) for performance monitoring. This captures 10% of page loads to avoid exceeding quota.

Adjust in `src/lib/sentry.ts`:
```tsx
tracesSampleRate: 0.1, // Change to 1.0 for 100%, 0.01 for 1%, etc.
```

### Breadcrumbs

Sentry captures up to 50 breadcrumbs (user actions, network requests, console logs) per error for context.

## Disabling Sentry

Sentry is disabled if:
- `NEXT_PUBLIC_SENTRY_DSN` is not set
- Invalid DSN format
- Network error during initialization

In these cases, the app continues to function normally without error reporting.

## Privacy & GDPR

Before enabling Sentry:

1. **Update privacy policy** — mention error tracking in Sentry
2. **User consent** — consider requiring user opt-in for error tracking
3. **PII redaction** — configure Sentry to redact sensitive data (emails, tokens, etc.)

Sentry allows filtering rules to automatically redact PII. Configure in Sentry project settings → Data & Privacy → Redaction.

## Testing

To verify Sentry is working in development:

```tsx
// In a component
import { captureException } from '@/lib/sentry';

<button onClick={() => captureException(new Error('Test error'))}>
  Send Test Error to Sentry
</button>
```

## Troubleshooting

### Errors not appearing in Sentry

1. Check DSN is correct in `.env.local`
2. Verify Sentry project is selected in dashboard
3. Check browser console for initialization errors
4. Ensure network isn't blocked (check browser DevTools → Network tab)

### Too many errors being reported

1. Increase sampling rate or reduce it:
   ```tsx
   tracesSampleRate: 0.05, // 5% instead of 10%
   ```
2. Add error filtering in Sentry project settings

### Sensitive data being sent to Sentry

1. Configure PII redaction in Sentry project settings
2. Use context parameter with sanitized data only:
   ```tsx
   captureException(error, { userId: user.id }); // NOT user.email
   ```

## References

- [Sentry React Documentation](https://docs.sentry.io/platforms/javascript/guides/react/)
- [Sentry Performance Monitoring](https://docs.sentry.io/product/performance/)
- [Sentry Security & Privacy](https://docs.sentry.io/security-and-privacy/)
