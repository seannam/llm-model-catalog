import { describe, expect, it } from 'vitest';
import { straicoFetcher } from '../../src/fetchers/straico.js';
import type { FetchLike } from '../../src/types.js';

function makeFetch(
  json: unknown,
  options: { ok?: boolean; status?: number } = {},
): FetchLike {
  const ok = options.ok ?? true;
  const status = options.status ?? 200;
  return async () => ({
    ok,
    status,
    async json() {
      return json;
    },
    async text() {
      return JSON.stringify(json);
    },
  });
}

describe('straicoFetcher', () => {
  it('parses the { data: [...] } envelope', async () => {
    const fetcher = straicoFetcher({ apiKey: 'k' });
    const entries = await fetcher.fetchModels({
      fetchImpl: makeFetch({
        data: [
          { id: 'anthropic/claude-sonnet-4-5', name: 'Claude Sonnet 4.5' },
          { id: 'anthropic/claude-haiku-4-5', name: 'Claude Haiku 4.5' },
        ],
      }),
    });
    expect(entries).toHaveLength(2);
    expect(entries[0]).toMatchObject({
      provider: 'straico',
      modelId: 'anthropic/claude-sonnet-4-5',
      family: 'claude-sonnet',
      displayName: 'Claude Sonnet 4.5',
    });
    expect(entries[1]!.family).toBe('claude-haiku');
  });

  it('parses a bare-array response', async () => {
    const fetcher = straicoFetcher({ apiKey: 'k' });
    const entries = await fetcher.fetchModels({
      fetchImpl: makeFetch([{ id: 'anthropic/claude-opus-4-5' }]),
    });
    expect(entries).toHaveLength(1);
    expect(entries[0]!.family).toBe('claude-opus');
  });

  it('throws when /models returns non-2xx', async () => {
    const fetcher = straicoFetcher({ apiKey: 'k' });
    await expect(
      fetcher.fetchModels({
        fetchImpl: makeFetch({ error: 'unauthorized' }, { ok: false, status: 401 }),
      }),
    ).rejects.toThrow(/straico \/models request failed: 401/);
  });

  it('skips rows without a usable id', async () => {
    const fetcher = straicoFetcher({ apiKey: 'k' });
    const entries = await fetcher.fetchModels({
      fetchImpl: makeFetch({ data: [{ name: 'no-id' }, { id: '' }, { id: 'valid' }] }),
    });
    expect(entries).toHaveLength(1);
    expect(entries[0]!.modelId).toBe('valid');
  });
});
