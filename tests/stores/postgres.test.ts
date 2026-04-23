import { describe, expect, it } from 'vitest';
import { createPostgresStore } from '../../src/stores/postgres.js';

interface Call {
  sql: string;
  values?: unknown[];
}

function createFakePool(responses: Record<string, Record<string, unknown>[]> = {}) {
  const calls: Call[] = [];
  const pool = {
    async query(sql: string, values?: unknown[]) {
      calls.push({ sql, values });
      for (const [pattern, rows] of Object.entries(responses)) {
        if (sql.includes(pattern)) return { rows };
      }
      return { rows: [] };
    },
  };
  return { pool, calls };
}

describe('createPostgresStore', () => {
  it('validates schema and table identifiers', () => {
    const { pool } = createFakePool();
    expect(() =>
      createPostgresStore({ pool, schema: 'bad-schema' }),
    ).toThrow(/bare SQL identifier/);
    expect(() =>
      createPostgresStore({ pool, schema: 'public', tableName: '; drop table' }),
    ).toThrow(/bare SQL identifier/);
  });

  it('targets the fully-qualified table in every query', async () => {
    const { pool, calls } = createFakePool();
    const store = createPostgresStore({
      pool,
      schema: 'buildlog',
      tableName: 'llm_model_catalog',
    });
    await store.list();
    await store.listByProvider('straico');
    await store.upsert(
      [
        {
          provider: 'straico',
          modelId: 'a',
          family: 'claude-sonnet',
          displayName: 'A',
        },
      ],
      new Date('2026-04-22T00:00:00Z'),
    );
    await store.markDeprecated(
      [{ provider: 'straico', modelId: 'a' }],
      new Date('2026-04-23T00:00:00Z'),
    );

    expect(calls[0]!.sql).toContain('from buildlog.llm_model_catalog');
    expect(calls[1]!.sql).toContain('where provider = $1');
    expect(calls[2]!.sql).toContain('insert into buildlog.llm_model_catalog');
    expect(calls[2]!.sql).toContain('on conflict (provider, model_id) do update');
    expect(calls[3]!.sql).toContain('update buildlog.llm_model_catalog');
  });

  it('parses timestamp columns into Date objects', async () => {
    const { pool } = createFakePool({
      'from buildlog.llm_model_catalog': [
        {
          provider: 'straico',
          model_id: 'a',
          family: 'claude-sonnet',
          display_name: 'A',
          first_seen_at: '2026-04-22T00:00:00Z',
          last_seen_at: '2026-04-22T06:00:00Z',
          deprecated_at: null,
        },
      ],
    });
    const store = createPostgresStore({ pool, schema: 'buildlog' });
    const rows = await store.list();
    expect(rows[0]!.firstSeenAt).toBeInstanceOf(Date);
    expect(rows[0]!.deprecatedAt).toBeNull();
  });
});
