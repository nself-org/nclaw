/**
 * Purpose: Zod schemas for all forms in ɳClaw web.
 * Inputs:  Form data from user inputs
 * Outputs: Validated and typed form data
 * Constraints: All schemas must allow empty fields initially, show errors only on blur/submit.
 *              Message length: 1-8000 chars. Names: 1-50 chars. URLs must be valid.
 * SPORT: T-P3-E5-W1-S1-T05 — form validation
 */

import { z } from 'zod';

/**
 * Chat message input schema.
 * - Content: 1-8000 characters, non-empty after trim
 */
export const chatInputSchema = z.object({
  content: z
    .string()
    .min(1, 'Message cannot be empty')
    .max(8000, 'Message cannot exceed 8000 characters')
    .refine((val: string) => val.trim().length > 0, 'Message cannot be empty or whitespace only'),
});

export type ChatInputFormData = z.infer<typeof chatInputSchema>;

/**
 * Memory save form schema.
 * - content: >=1 char, non-empty
 * - type: enum of memory types (context, fact, preference, goal, rule)
 * - confidence: 0-1 scale
 */
export const memorySchema = z.object({
  content: z
    .string()
    .min(1, 'Memory content cannot be empty')
    .refine((val: string) => val.trim().length > 0, 'Memory content cannot be empty or whitespace only'),
  type: z.enum(['context', 'fact', 'preference', 'goal', 'rule'], {
    errorMap: () => ({ message: 'Please select a memory type' }),
  }),
  confidence: z
    .number()
    .min(0, 'Confidence must be between 0 and 1')
    .max(1, 'Confidence must be between 0 and 1'),
});

export type MemoryFormData = z.infer<typeof memorySchema>;

/**
 * Persona creation schema.
 * - name: 1-50 characters, non-empty
 * - description: optional, max 500 chars
 * - instructions: optional, max 2000 chars
 */
export const personaSchema = z.object({
  name: z
    .string()
    .min(1, 'Persona name cannot be empty')
    .max(50, 'Persona name cannot exceed 50 characters')
    .refine((val: string) => val.trim().length > 0, 'Persona name cannot be empty or whitespace only'),
  description: z
    .string()
    .max(500, 'Description cannot exceed 500 characters')
    .optional()
    .or(z.literal('')),
  instructions: z
    .string()
    .max(2000, 'Instructions cannot exceed 2000 characters')
    .optional()
    .or(z.literal('')),
});

export type PersonaFormData = z.infer<typeof personaSchema>;

/**
 * Integration addition schema.
 * - name: 1-100 characters, non-empty
 * - base_url: must be valid URL
 * - tools: array of tool names, at least one required
 * - auth_type: optional, enum of auth methods
 */
export const integrationSchema = z.object({
  name: z
    .string()
    .min(1, 'Integration name cannot be empty')
    .max(100, 'Integration name cannot exceed 100 characters')
    .refine((val: string) => val.trim().length > 0, 'Integration name cannot be empty'),
  base_url: z
    .string()
    .min(1, 'Base URL cannot be empty')
    .url('Please enter a valid URL'),
  tools: z
    .array(z.string())
    .min(1, 'Please select at least one tool')
    .refine((tools: string[]) => new Set(tools).size === tools.length, 'Duplicate tools selected'),
  auth_type: z
    .enum(['none', 'bearer', 'api_key', 'oauth2'], {
      errorMap: () => ({ message: 'Please select an authentication type' }),
    })
    .optional(),
});

export type IntegrationFormData = z.infer<typeof integrationSchema>;

/**
 * Budget/spend limit form schema.
 * - amount: must be > 0
 * - period: daily, monthly, or yearly
 * - currency: optional, defaults to USD
 */
export const budgetSchema = z.object({
  amount: z
    .number()
    .gt(0, 'Amount must be greater than 0')
    .refine((val: number) => !isNaN(val), 'Amount must be a valid number'),
  period: z.enum(['daily', 'monthly', 'yearly'], {
    errorMap: () => ({ message: 'Please select a billing period' }),
  }),
  currency: z.enum(['USD', 'EUR', 'GBP', 'JPY']).optional(),
});

export type BudgetFormData = z.infer<typeof budgetSchema>;

/**
 * Onboarding questions schema.
 * - Array of question responses with question_id and answer text
 */
export const onboardingResponseSchema = z.object({
  question_id: z.string().min(1, 'Question ID required'),
  answer: z
    .string()
    .min(1, 'Please provide an answer')
    .refine((val) => val.trim().length > 0, 'Answer cannot be empty or whitespace only'),
});

export const onboardingSchema = z.object({
  responses: z
    .array(onboardingResponseSchema)
    .min(1, 'Please answer at least one question'),
});

export type OnboardingFormData = z.infer<typeof onboardingSchema>;
