import { describe, it, expect } from 'vitest'
import { cn } from './utils'

describe('cn', () => {
  it('returns empty string with no args', () => {
    expect(cn()).toBe('')
  })

  it('joins two plain classes', () => {
    expect(cn('a', 'b')).toBe('a b')
  })

  it('joins multiple plain classes', () => {
    expect(cn('a', 'b', 'c')).toBe('a b c')
  })

  it('ignores falsy values — undefined', () => {
    expect(cn('a', undefined, 'b')).toBe('a b')
  })

  it('ignores falsy values — null', () => {
    expect(cn('a', null, 'b')).toBe('a b')
  })

  it('ignores falsy values — false', () => {
    expect(cn('a', false, 'b')).toBe('a b')
  })

  it('resolves tailwind-merge conflicts — last padding wins', () => {
    // tailwind-merge de-dups conflicting utility classes
    expect(cn('p-4', 'p-2')).toBe('p-2')
  })

  it('resolves tailwind-merge conflicts — last color wins', () => {
    expect(cn('text-red-500', 'text-blue-500')).toBe('text-blue-500')
  })

  it('resolves tailwind-merge conflicts — last bg wins', () => {
    expect(cn('bg-white', 'bg-gray-100')).toBe('bg-gray-100')
  })

  it('passes through non-conflicting tailwind classes', () => {
    expect(cn('p-4', 'm-2')).toBe('p-4 m-2')
  })

  it('handles conditional class via object syntax', () => {
    expect(cn({ 'font-bold': true, italic: false })).toBe('font-bold')
  })

  it('handles array of classes', () => {
    expect(cn(['a', 'b'])).toBe('a b')
  })

  it('handles deeply conditional usage — typical component pattern', () => {
    const isActive = true
    const isDisabled = false
    expect(cn('base', isActive && 'active', isDisabled && 'disabled')).toBe('base active')
  })

  it('handles empty string input', () => {
    expect(cn('')).toBe('')
  })
})
