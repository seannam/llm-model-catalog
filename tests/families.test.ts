import { afterEach, describe, expect, it } from 'vitest';
import { defineFamily, inferFamily, __resetUserFamilies } from '../src/families.js';

describe('inferFamily', () => {
  afterEach(() => {
    __resetUserFamilies();
  });

  it('maps Claude Haiku variants', () => {
    expect(inferFamily('claude-haiku-4-5')).toBe('claude-haiku');
    expect(inferFamily('claude-3-5-haiku-20250123')).toBe('claude-haiku');
    expect(inferFamily('anthropic/claude-haiku-4-5')).toBe('claude-haiku');
  });

  it('maps Claude Sonnet variants', () => {
    expect(inferFamily('claude-sonnet-4-5')).toBe('claude-sonnet');
    expect(inferFamily('anthropic/claude-sonnet-4.5')).toBe('claude-sonnet');
  });

  it('maps Claude Opus variants', () => {
    expect(inferFamily('claude-opus-4-5')).toBe('claude-opus');
    expect(inferFamily('anthropic/claude-opus-4-5')).toBe('claude-opus');
  });

  it('prefers gpt-4o-mini over gpt-4o when both would match', () => {
    expect(inferFamily('gpt-4o-mini')).toBe('gpt-4o-mini');
    expect(inferFamily('gpt-4o-2024-11-20')).toBe('gpt-4o');
  });

  it('maps Qwen coder', () => {
    expect(inferFamily('qwen2.5-coder:32b')).toBe('qwen-coder');
  });

  it('maps stub provider', () => {
    expect(inferFamily('stub-canned')).toBe('stub');
  });

  it('returns unknown for unmatched ids', () => {
    expect(inferFamily('gemini-2-pro')).toBe('unknown');
  });

  it('defineFamily takes precedence over defaults', () => {
    defineFamily(/claude-sonnet-4-5/, 'claude-opus');
    expect(inferFamily('claude-sonnet-4-5')).toBe('claude-opus');
  });

  it('defineFamily adds new rules for unmatched ids', () => {
    defineFamily(/gemini-.*pro/i, 'claude-opus');
    expect(inferFamily('gemini-2.0-pro')).toBe('claude-opus');
  });
});
