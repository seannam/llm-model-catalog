import { describe, expect, it } from 'vitest';
import { resolveModel } from '../src/resolve.js';
import type { CatalogEntry } from '../src/types.js';

const now = new Date('2026-04-22T00:00:00Z');

function entry(
  provider: string,
  modelId: string,
  family: string,
  deprecated: boolean = false,
): CatalogEntry {
  return {
    provider,
    modelId,
    family,
    displayName: modelId,
    firstSeenAt: now,
    lastSeenAt: now,
    deprecatedAt: deprecated ? now : null,
  };
}

describe('resolveModel', () => {
  it('returns null on empty catalog', () => {
    const res = resolveModel({
      provider: 'straico',
      catalog: [],
      preferences: ['claude-sonnet'],
    });
    expect(res).toBeNull();
  });

  it('honors a valid env hint', () => {
    const res = resolveModel({
      provider: 'straico',
      catalog: [
        entry('straico', 'anthropic/claude-haiku-4-5', 'claude-haiku'),
        entry('straico', 'anthropic/claude-sonnet-4-5', 'claude-sonnet'),
      ],
      preferences: ['claude-sonnet'],
      envHint: 'anthropic/claude-haiku-4-5',
    });
    expect(res?.modelId).toBe('anthropic/claude-haiku-4-5');
    expect(res?.source).toBe('env-hint');
  });

  it('ignores an env hint that is not in the catalog', () => {
    const res = resolveModel({
      provider: 'straico',
      catalog: [entry('straico', 'anthropic/claude-sonnet-4-5', 'claude-sonnet')],
      preferences: ['claude-sonnet'],
      envHint: 'anthropic/claude-opus-4-5',
    });
    expect(res?.modelId).toBe('anthropic/claude-sonnet-4-5');
    expect(res?.source).toBe('preference');
  });

  it('ignores an env hint that points at a deprecated row', () => {
    const res = resolveModel({
      provider: 'straico',
      catalog: [
        entry('straico', 'anthropic/claude-haiku-4-5', 'claude-haiku', true),
        entry('straico', 'anthropic/claude-sonnet-4-5', 'claude-sonnet'),
      ],
      preferences: ['claude-sonnet'],
      envHint: 'anthropic/claude-haiku-4-5',
    });
    expect(res?.modelId).toBe('anthropic/claude-sonnet-4-5');
  });

  it('walks preferences in order', () => {
    const res = resolveModel({
      provider: 'straico',
      catalog: [
        entry('straico', 'anthropic/claude-haiku-4-5', 'claude-haiku'),
        entry('straico', 'anthropic/claude-sonnet-4-5', 'claude-sonnet'),
      ],
      preferences: ['claude-opus', 'claude-sonnet', 'claude-haiku'],
    });
    expect(res?.family).toBe('claude-sonnet');
  });

  it('skips deprecated rows in the preference walk', () => {
    const res = resolveModel({
      provider: 'straico',
      catalog: [
        entry('straico', 'anthropic/claude-sonnet-4-5', 'claude-sonnet', true),
        entry('straico', 'anthropic/claude-haiku-4-5', 'claude-haiku'),
      ],
      preferences: ['claude-sonnet', 'claude-haiku'],
    });
    expect(res?.family).toBe('claude-haiku');
  });

  it('falls back to the first live row when nothing matches preferences', () => {
    const res = resolveModel({
      provider: 'straico',
      catalog: [entry('straico', 'deepseek-r1', 'unknown')],
      preferences: ['claude-sonnet'],
    });
    expect(res?.modelId).toBe('deepseek-r1');
    expect(res?.source).toBe('fallback');
  });

  it('filters rows by the requested provider', () => {
    const res = resolveModel({
      provider: 'straico',
      catalog: [
        entry('openrouter', 'anthropic/claude-sonnet-4.5', 'claude-sonnet'),
      ],
      preferences: ['claude-sonnet'],
    });
    expect(res).toBeNull();
  });

  it('blank env hint is ignored', () => {
    const res = resolveModel({
      provider: 'straico',
      catalog: [entry('straico', 'anthropic/claude-sonnet-4-5', 'claude-sonnet')],
      preferences: ['claude-sonnet'],
      envHint: '   ',
    });
    expect(res?.source).toBe('preference');
  });
});
