# ɳClaw Web Forms Validation

## Overview

All forms in the ɳClaw web application use **Zod** schemas for runtime validation combined with **react-hook-form** for form state management and error display.

## Architecture

```
Form Component
  └─ useForm (react-hook-form)
     └─ zodResolver (validates with Zod schema)
        └─ ZodSchema (src/lib/validation/schemas.ts)
```

The validation happens at:
1. **Field blur** — show errors as user leaves a field
2. **Form submit** — validate all fields before submission
3. **Client-side only** — full validation before API call (prevents invalid requests)

## Available Schemas

### `chatInputSchema`

Validates message input for the chat interface.

**Fields:**
- `content`: string, 1-8000 characters, cannot be blank/whitespace-only

**Example:**
```tsx
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { chatInputSchema } from '@/lib/validation/schemas';

export function ChatForm() {
  const { register, formState: { errors, isValid } } = useForm({
    resolver: zodResolver(chatInputSchema),
    defaultValues: { content: '' },
  });

  return (
    <form>
      <textarea {...register('content')} />
      {errors.content && <span>{errors.content.message}</span>}
      <button disabled={!isValid}>Send</button>
    </form>
  );
}
```

### `memorySchema`

Validates memory save form data.

**Fields:**
- `content`: string, ≥1 character, non-empty
- `type`: enum of `'context' | 'fact' | 'preference' | 'goal' | 'rule'`
- `confidence`: number, 0-1 range

**Example:**
```tsx
const { register } = useForm({
  resolver: zodResolver(memorySchema),
});

return (
  <>
    <textarea {...register('content')} placeholder="What to remember?" />
    <select {...register('type')}>
      <option value="fact">Fact</option>
      <option value="preference">Preference</option>
      <option value="goal">Goal</option>
      <option value="rule">Rule</option>
      <option value="context">Context</option>
    </select>
    <input type="range" {...register('confidence', { valueAsNumber: true })} min="0" max="1" step="0.1" />
  </>
);
```

### `personaSchema`

Validates AI persona creation form.

**Fields:**
- `name`: string, 1-50 characters
- `description`: optional string, max 500 characters
- `instructions`: optional string, max 2000 characters

### `integrationSchema`

Validates third-party service integration setup.

**Fields:**
- `name`: string, 1-100 characters
- `base_url`: valid URL
- `tools`: array of tool names, at least one required, no duplicates
- `auth_type`: optional enum of `'none' | 'bearer' | 'api_key' | 'oauth2'`

### `budgetSchema`

Validates spending limit form.

**Fields:**
- `amount`: number > 0
- `period`: enum of `'daily' | 'monthly' | 'yearly'`
- `currency`: optional, enum of `'USD' | 'EUR' | 'GBP' | 'JPY'`

### `onboardingSchema`

Validates user onboarding question responses.

**Fields:**
- `responses`: array of objects with:
  - `question_id`: string, non-empty
  - `answer`: string, ≥1 character, non-empty

## Usage Patterns

### Basic Form Validation

```tsx
'use client';

import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { chatInputSchema, type ChatInputFormData } from '@/lib/validation/schemas';

export function MyForm() {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting, isValid },
  } = useForm<ChatInputFormData>({
    resolver: zodResolver(chatInputSchema),
    mode: 'onBlur', // Show errors on field blur
  });

  const onSubmit = async (data: ChatInputFormData) => {
    // At this point, data is guaranteed to be valid
    await sendMessage(data.content);
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <input
        {...register('content')}
        placeholder="Type your message..."
        disabled={isSubmitting}
      />
      {errors.content && (
        <span className="text-red-500 text-sm">{errors.content.message}</span>
      )}
      <button type="submit" disabled={!isValid || isSubmitting}>
        {isSubmitting ? 'Sending...' : 'Send'}
      </button>
    </form>
  );
}
```

### Showing Inline Field Errors

```tsx
<div>
  <label>Email</label>
  <input {...register('email')} />
  {errors.email && (
    <p className="error">{errors.email.message}</p>
  )}
</div>
```

### Disabling Submit Button on Invalid Form

```tsx
const { formState: { isValid } } = useForm({
  resolver: zodResolver(mySchema),
});

<button type="submit" disabled={!isValid}>
  Submit
</button>
```

## Testing Validation Schemas

Each schema has a test file in `src/lib/validation/__tests__/`. Run tests:

```bash
npm run test
```

Tests validate:
- Valid inputs pass validation
- Invalid inputs fail with appropriate error messages
- Boundary conditions (empty strings, max lengths, enum values)
- Type coercion and number ranges

## Best Practices

1. **Always import types** alongside schemas for TypeScript safety:
   ```tsx
   import { chatInputSchema, type ChatInputFormData } from '@/lib/validation/schemas';
   ```

2. **Use `mode: 'onBlur'`** for better UX — shows errors only after user interacts with field

3. **Disable submit button** until form is valid:
   ```tsx
   disabled={!isValid || isSubmitting}
   ```

4. **Handle validation errors gracefully** — show inline messages per field

5. **Never bypass validation** — always resolve Zod schema through zodResolver

## Error Handling

All validation errors are caught at form level and displayed inline. No validation errors should reach the API layer (validation is client-side, but idempotency keys prevent duplicates if retried).

See `observability.md` for error reporting to Sentry.
