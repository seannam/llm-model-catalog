import { describe, expect, it } from 'vitest';
import { openRouterFetcher } from '../../src/fetchers/openrouter.js';
import type { FetchLike } from '../../src/types.js';

function makeFetch(
  json: unknown,
  options: { ok?: boolean; status?: number } = {},
): FetchLike {
  return async () => ({
    ok: options.ok ?? true,
    status: options.status ?? 200,
    async json() {
      return json;
    },
    async text() {
      return JSON.stringify(json);
    },
  });
}

describe('openRouterFetcher', () => {
  it('parses { data: [{ id, name }] }', async () => {
    const fetcher = openRouterFetcher({ apiKey: 'k' });
    const entries = await fetcher.fetchModels({
      fetchImpl: makeFetch({
        data: [
          { id: 'anthropic/claude-sonnet-4.5', name: 'Claude Sonnet 4.5' },
          { id: 'openai/gpt-4o-mini', name: 'GPT-4o Mini' },
        ],
      }),
    });
    expect(entries).toHaveLength(2);
    expect(entries[0]!.family).toBe('claude-sonnet');
    expect(entries[1]!.family).toBe('gpt-4o-mini');
  });

  it('throws on HTTP failure', async () => {
    const fetcher = openRouterFetcher({ apiKey: 'k' });
    await expect(
      fetcher.fetchModels({
        fetchImpl: makeFetch({ err: 'down' }, { ok: false, status: 502 }),
      }),
    ).rejects.toThrow(/openrouter \/models request failed: 502/);
  });
});
