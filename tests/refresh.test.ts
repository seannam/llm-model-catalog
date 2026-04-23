import { describe, expect, it } from 'vitest';
import { refreshCatalog } from '../src/refresh.js';
import { createMemoryStore } from '../src/stores/memory.js';
import type { ProviderFetcher } from '../src/types.js';

function staticFetcher(
  provider: string,
  ids: string[],
  family = 'claude-sonnet',
): ProviderFetcher {
  return {
    provider,
    async fetchModels() {
      return ids.map((id) => ({
        provider,
        modelId: id,
        family,
        displayName: id,
      }));
    },
  };
}

function brokenFetcher(provider: string, err: string): ProviderFetcher {
  return {
    provider,
    async fetchModels() {
      throw new Error(err);
    },
  };
}

describe('refreshCatalog', () => {
  it('upserts fresh rows into an empty store', async () => {
    const store = createMemoryStore();
    const result = await refreshCatalog({
      store,
      fetchers: [staticFetcher('straico', ['sonnet-4-5'])],
    });
    expect(result.fetched['straico']).toBe(1);
    expect(result.errors).toEqual({});
    const rows = await store.list();
    expect(rows).toHaveLength(1);
    expect(rows[0]!.modelId).toBe('sonnet-4-5');
  });

  it('continues after one fetcher fails', async () => {
    const store = createMemoryStore();
    const result = await refreshCatalog({
      store,
      fetchers: [
        brokenFetcher('straico', 'boom'),
        staticFetcher('openrouter', ['sonnet-4.5']),
      ],
    });
    expect(result.fetched['straico']).toBe(0);
    expect(result.fetched['openrouter']).toBe(1);
    expect(result.errors['straico']).toContain('boom');
    const rows = await store.listByProvider('openrouter');
    expect(rows).toHaveLength(1);
  });

  it('marks rows missing on the second pass as deprecated', async () => {
    const store = createMemoryStore();
    let now = new Date('2026-04-22T00:00:00Z');
    const clock = () => now;

    await refreshCatalog({
      store,
      fetchers: [staticFetcher('straico', ['a', 'b', 'c'])],
      now: clock,
    });
    expect((await store.list()).length).toBe(3);

    now = new Date('2026-04-22T06:00:00Z');
    await refreshCatalog({
      store,
      fetchers: [staticFetcher('straico', ['a', 'b'])],
      now: clock,
    });

    const all = await store.list();
    const byId = new Map(all.map((r) => [r.modelId, r]));
    expect(byId.get('a')!.deprecatedAt).toBeNull();
    expect(byId.get('b')!.deprecatedAt).toBeNull();
    expect(byId.get('c')!.deprecatedAt).not.toBeNull();
  });

  it('does not deprecate rows from a failing provider', async () => {
    const store = createMemoryStore();
    let now = new Date('2026-04-22T00:00:00Z');
    const clock = () => now;

    await refreshCatalog({
      store,
      fetchers: [staticFetcher('straico', ['a'])],
      now: clock,
    });

    now = new Date('2026-04-22T06:00:00Z');
    await refreshCatalog({
      store,
      fetchers: [brokenFetcher('straico', 'timeout')],
      now: clock,
    });

    const rows = await store.listByProvider('straico');
    expect(rows).toHaveLength(1);
    expect(rows[0]!.deprecatedAt).toBeNull();
  });

  it('does not cross-deprecate between providers', async () => {
    const store = createMemoryStore();
    let now = new Date('2026-04-22T00:00:00Z');
    const clock = () => now;

    await refreshCatalog({
      store,
      fetchers: [
        staticFetcher('straico', ['s1']),
        staticFetcher('openrouter', ['o1']),
      ],
      now: clock,
    });

    now = new Date('2026-04-22T06:00:00Z');
    await refreshCatalog({
      store,
      fetchers: [staticFetcher('straico', ['s1'])],
      now: clock,
    });

    const openrouterRows = await store.listByProvider('openrouter');
    expect(openrouterRows[0]!.deprecatedAt).toBeNull();
  });
});
