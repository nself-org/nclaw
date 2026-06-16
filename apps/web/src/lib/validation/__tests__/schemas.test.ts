/**
 * Test suite for Zod validation schemas.
 * Validates: correct inputs pass, invalid inputs fail with appropriate errors.
 */

import { describe, it, expect } from 'vitest';
import {
  chatInputSchema,
  memorySchema,
  personaSchema,
  integrationSchema,
  budgetSchema,
  onboardingSchema,
  type ChatInputFormData,
  type MemoryFormData,
  type PersonaFormData,
  type IntegrationFormData,
  type BudgetFormData,
  type OnboardingFormData,
} from '../schemas';

describe('chatInputSchema', () => {
  it('accepts valid message', () => {
    const data = { content: 'Hello, world!' };
    const result = chatInputSchema.safeParse(data);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.content).toBe('Hello, world!');
    }
  });

  it('rejects empty message', () => {
    const result = chatInputSchema.safeParse({ content: '' });
    expect(result.success).toBe(false);
  });

  it('rejects whitespace-only message', () => {
    const result = chatInputSchema.safeParse({ content: '   ' });
    expect(result.success).toBe(false);
  });

  it('rejects message exceeding 8000 chars', () => {
    const longMessage = 'a'.repeat(8001);
    const result = chatInputSchema.safeParse({ content: longMessage });
    expect(result.success).toBe(false);
  });

  it('accepts message at 8000 char boundary', () => {
    const maxMessage = 'a'.repeat(8000);
    const result = chatInputSchema.safeParse({ content: maxMessage });
    expect(result.success).toBe(true);
  });
});

describe('memorySchema', () => {
  it('accepts valid memory with all fields', () => {
    const data: MemoryFormData = {
      content: 'User likes coffee',
      type: 'preference',
      confidence: 0.9,
    };
    const result = memorySchema.safeParse(data);
    expect(result.success).toBe(true);
  });

  it('rejects empty content', () => {
    const data = {
      content: '',
      type: 'fact',
      confidence: 0.5,
    };
    const result = memorySchema.safeParse(data);
    expect(result.success).toBe(false);
  });

  it('rejects invalid memory type', () => {
    const data = {
      content: 'Some memory',
      type: 'invalid_type',
      confidence: 0.5,
    };
    const result = memorySchema.safeParse(data);
    expect(result.success).toBe(false);
  });

  it('rejects confidence > 1', () => {
    const data = {
      content: 'Valid content',
      type: 'fact',
      confidence: 1.5,
    };
    const result = memorySchema.safeParse(data);
    expect(result.success).toBe(false);
  });

  it('rejects confidence < 0', () => {
    const data = {
      content: 'Valid content',
      type: 'fact',
      confidence: -0.1,
    };
    const result = memorySchema.safeParse(data);
    expect(result.success).toBe(false);
  });

  it('accepts confidence at boundaries (0 and 1)', () => {
    expect(memorySchema.safeParse({
      content: 'test',
      type: 'fact',
      confidence: 0,
    }).success).toBe(true);

    expect(memorySchema.safeParse({
      content: 'test',
      type: 'fact',
      confidence: 1,
    }).success).toBe(true);
  });
});

describe('personaSchema', () => {
  it('accepts valid persona with name only', () => {
    const data: PersonaFormData = {
      name: 'Assistant',
      description: '',
      instructions: '',
    };
    const result = personaSchema.safeParse(data);
    expect(result.success).toBe(true);
  });

  it('accepts persona with all fields', () => {
    const data: PersonaFormData = {
      name: 'Expert Assistant',
      description: 'A helpful assistant',
      instructions: 'Be concise and accurate',
    };
    const result = personaSchema.safeParse(data);
    expect(result.success).toBe(true);
  });

  it('rejects empty name', () => {
    const result = personaSchema.safeParse({ name: '' });
    expect(result.success).toBe(false);
  });

  it('rejects name exceeding 50 chars', () => {
    const longName = 'a'.repeat(51);
    const result = personaSchema.safeParse({ name: longName });
    expect(result.success).toBe(false);
  });

  it('accepts name at 50 char boundary', () => {
    const maxName = 'a'.repeat(50);
    const result = personaSchema.safeParse({ name: maxName });
    expect(result.success).toBe(true);
  });

  it('rejects description exceeding 500 chars', () => {
    const longDesc = 'a'.repeat(501);
    const result = personaSchema.safeParse({ name: 'Test', description: longDesc });
    expect(result.success).toBe(false);
  });

  it('rejects instructions exceeding 2000 chars', () => {
    const longInstructions = 'a'.repeat(2001);
    const result = personaSchema.safeParse({
      name: 'Test',
      instructions: longInstructions,
    });
    expect(result.success).toBe(false);
  });
});

describe('integrationSchema', () => {
  it('accepts valid integration', () => {
    const data: IntegrationFormData = {
      name: 'GitHub API',
      base_url: 'https://api.github.com',
      tools: ['repos', 'issues'],
      auth_type: 'bearer',
    };
    const result = integrationSchema.safeParse(data);
    expect(result.success).toBe(true);
  });

  it('rejects empty name', () => {
    const result = integrationSchema.safeParse({
      name: '',
      base_url: 'https://example.com',
      tools: ['test'],
    });
    expect(result.success).toBe(false);
  });

  it('rejects invalid URL', () => {
    const result = integrationSchema.safeParse({
      name: 'Invalid',
      base_url: 'not-a-url',
      tools: ['test'],
    });
    expect(result.success).toBe(false);
  });

  it('rejects empty tools array', () => {
    const result = integrationSchema.safeParse({
      name: 'Test',
      base_url: 'https://example.com',
      tools: [],
    });
    expect(result.success).toBe(false);
  });

  it('rejects duplicate tools', () => {
    const result = integrationSchema.safeParse({
      name: 'Test',
      base_url: 'https://example.com',
      tools: ['test', 'test'],
    });
    expect(result.success).toBe(false);
  });

  it('accepts valid auth types', () => {
    const baseData = {
      name: 'Test',
      base_url: 'https://example.com',
      tools: ['test'],
    };

    expect(integrationSchema.safeParse({ ...baseData, auth_type: 'none' }).success).toBe(true);
    expect(integrationSchema.safeParse({ ...baseData, auth_type: 'bearer' }).success).toBe(true);
    expect(integrationSchema.safeParse({ ...baseData, auth_type: 'api_key' }).success).toBe(true);
    expect(integrationSchema.safeParse({ ...baseData, auth_type: 'oauth2' }).success).toBe(true);
  });
});

describe('budgetSchema', () => {
  it('accepts valid budget', () => {
    const data: BudgetFormData = {
      amount: 10.5,
      period: 'monthly',
      currency: 'USD',
    };
    const result = budgetSchema.safeParse(data);
    expect(result.success).toBe(true);
  });

  it('rejects zero amount', () => {
    const result = budgetSchema.safeParse({
      amount: 0,
      period: 'monthly',
    });
    expect(result.success).toBe(false);
  });

  it('rejects negative amount', () => {
    const result = budgetSchema.safeParse({
      amount: -5,
      period: 'monthly',
    });
    expect(result.success).toBe(false);
  });

  it('rejects invalid period', () => {
    const result = budgetSchema.safeParse({
      amount: 10,
      period: 'weekly',
    });
    expect(result.success).toBe(false);
  });

  it('accepts valid periods', () => {
    expect(budgetSchema.safeParse({
      amount: 10,
      period: 'daily',
    }).success).toBe(true);

    expect(budgetSchema.safeParse({
      amount: 10,
      period: 'monthly',
    }).success).toBe(true);

    expect(budgetSchema.safeParse({
      amount: 10,
      period: 'yearly',
    }).success).toBe(true);
  });
});

describe('onboardingSchema', () => {
  it('accepts valid onboarding responses', () => {
    const data: OnboardingFormData = {
      responses: [
        {
          question_id: 'q1',
          answer: 'Yes, I like AI',
        },
      ],
    };
    const result = onboardingSchema.safeParse(data);
    expect(result.success).toBe(true);
  });

  it('rejects empty responses array', () => {
    const result = onboardingSchema.safeParse({
      responses: [],
    });
    expect(result.success).toBe(false);
  });

  it('rejects empty answer', () => {
    const result = onboardingSchema.safeParse({
      responses: [
        {
          question_id: 'q1',
          answer: '',
        },
      ],
    });
    expect(result.success).toBe(false);
  });

  it('rejects missing question_id', () => {
    const result = onboardingSchema.safeParse({
      responses: [
        {
          question_id: '',
          answer: 'Test answer',
        },
      ],
    });
    expect(result.success).toBe(false);
  });
});
