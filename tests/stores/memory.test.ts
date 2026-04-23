import { describe, expect, it } from 'vitest';
import { createMemoryStore } from '../../src/stores/memory.js';

describe('createMemoryStore', () => {
  it('upserts new rows and lists them', async () => {
    const store = createMemoryStore();
    const now = new Date('2026-04-22T00:00:00Z');
    await store.upsert(
      [
        { provider: 'straico', modelId: 'a', family: 'claude-sonnet', displayName: 'A' },
        { provider: 'openrouter', modelId: 'b', family: 'claude-haiku', displayName: 'B' },
      ],
      now,
    );
    const all = await store.list();
    expect(all).toHaveLength(2);
    const byProvider = await store.listByProvider('straico');
    expect(byProvider).toHaveLength(1);
    expect(byProvider[0]!.firstSeenAt).toEqual(now);
  });

  it('preserves firstSeenAt across upserts and resets deprecatedAt', async () => {
    const store = createMemoryStore();
    const first = new Date('2026-04-22T00:00:00Z');
    const later = new Date('2026-04-22T06:00:00Z');
    await store.upsert(
      [{ provider: 'straico', modelId: 'x', family: 'claude-sonnet', displayName: 'X' }],
      first,
    );
    await store.markDeprecated([{ provider: 'straico', modelId: 'x' }], later);
    let rows = await store.list();
    expect(rows[0]!.deprecatedAt).toEqual(later);

    await store.upsert(
      [{ provider: 'straico', modelId: 'x', family: 'claude-sonnet', displayName: 'X2' }],
      later,
    );
    rows = await store.list();
    expect(rows[0]!.firstSeenAt).toEqual(first);
    expect(rows[0]!.lastSeenAt).toEqual(later);
    expect(rows[0]!.deprecatedAt).toBeNull();
    expect(rows[0]!.displayName).toBe('X2');
  });

  it('markDeprecated is a no-op for already-deprecated rows', async () => {
    const store = createMemoryStore();
    const first = new Date('2026-04-22T00:00:00Z');
    const later = new Date('2026-04-23T00:00:00Z');
    const evenLater = new Date('2026-04-24T00:00:00Z');
    await store.upsert(
      [{ provider: 'straico', modelId: 'x', family: 'claude-sonnet', displayName: null }],
      first,
    );
    await store.markDeprecated([{ provider: 'straico', modelId: 'x' }], later);
    await store.markDeprecated([{ provider: 'straico', modelId: 'x' }], evenLater);
    const rows = await store.list();
    expect(rows[0]!.deprecatedAt).toEqual(later);
  });

  it('seed rows are returned as copies', async () => {
    const seeded = createMemoryStore([
      {
        provider: 'straico',
        modelId: 'a',
        family: 'claude-sonnet',
        displayName: 'A',
        firstSeenAt: new Date(),
        lastSeenAt: new Date(),
        deprecatedAt: null,
      },
    ]);
    const rows = await seeded.list();
    rows[0]!.modelId = 'mutated';
    const rowsAgain = await seeded.list();
    expect(rowsAgain[0]!.modelId).toBe('a');
  });
});
