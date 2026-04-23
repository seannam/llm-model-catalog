import { describe, expect, it } from 'vitest';
import { anthropicFetcher } from '../../src/fetchers/anthropic.js';
import { ANTHROPIC_STATIC_MODELS } from '../../src/fetchers/anthropic-models.js';

describe('anthropicFetcher', () => {
  it('returns the default static list', async () => {
    const entries = await anthropicFetcher().fetchModels();
    expect(entries.length).toBe(ANTHROPIC_STATIC_MODELS.length);
    const ids = entries.map((e) => e.modelId);
    expect(ids).toContain('claude-sonnet-4-5');
  });

  it('respects an injected model list', async () => {
    const entries = await anthropicFetcher({
      models: [{ id: 'claude-sonnet-5-0', displayName: 'Claude Sonnet 5' }],
    }).fetchModels();
    expect(entries).toHaveLength(1);
    expect(entries[0]!.family).toBe('claude-sonnet');
  });

  it('honors an overridden provider name', async () => {
    const entries = await anthropicFetcher({ provider: 'anthropic-alt' }).fetchModels();
    expect(entries.every((e) => e.provider === 'anthropic-alt')).toBe(true);
  });
});
