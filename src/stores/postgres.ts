/**
 * Postgres-backed `CatalogStore`.
 *
 * `pg` is an optional peer dependency; consumers who only use the
 * memory store pay nothing for it. The `pool` argument carries the
 * connection, so consumers choose their own pool management.
 *
 * Parameterized SQL is used everywhere values touch user input.
 * `schema` / `tableName` are validated identifiers, but because they
 * cannot be parameterized by pg they are embedded verbatim after a
 * regex check (same rule as `migrationSql`).
 */

import type {
  CatalogEntry,
  CatalogStore,
  CatalogUpsert,
} from '../types.js';

interface PgPoolLike {
  query: (text: string, values?: unknown[]) => Promise<{ rows: Record<string, unknown>[] }>;
}

export interface CreatePostgresStoreOptions {
  pool: PgPoolLike;
  schema: string;
  tableName?: string;
}

const IDENTIFIER_RE = /^[a-zA-Z_][a-zA-Z0-9_]*$/;

function assertIdentifier(label: string, value: string): void {
  if (!IDENTIFIER_RE.test(value)) {
    throw new Error(
      `createPostgresStore: ${label} must be a bare SQL identifier; got ${JSON.stringify(value)}`,
    );
  }
}

function rowToEntry(row: Record<string, unknown>): CatalogEntry {
  return {
    provider: String(row['provider']),
    modelId: String(row['model_id']),
    family: String(row['family']),
    displayName:
      row['display_name'] === null || row['display_name'] === undefined
        ? null
        : String(row['display_name']),
    firstSeenAt: new Date(row['first_seen_at'] as string),
    lastSeenAt: new Date(row['last_seen_at'] as string),
    deprecatedAt:
      row['deprecated_at'] === null || row['deprecated_at'] === undefined
        ? null
        : new Date(row['deprecated_at'] as string),
  };
}

export function createPostgresStore(
  options: CreatePostgresStoreOptions,
): CatalogStore {
  const schema = options.schema;
  const tableName = options.tableName ?? 'llm_model_catalog';
  assertIdentifier('schema', schema);
  assertIdentifier('tableName', tableName);
  const fq = `${schema}.${tableName}`;
  const pool = options.pool;

  const selectAllSql = `select provider, model_id, family, display_name, first_seen_at, last_seen_at, deprecated_at from ${fq} order by provider, model_id`;
  const selectByProviderSql = `select provider, model_id, family, display_name, first_seen_at, last_seen_at, deprecated_at from ${fq} where provider = $1 order by model_id`;

  const upsertSql = `insert into ${fq}
      (provider, model_id, family, display_name, first_seen_at, last_seen_at, deprecated_at)
    values ($1, $2, $3, $4, $5, $5, null)
    on conflict (provider, model_id) do update set
      family = excluded.family,
      display_name = excluded.display_name,
      last_seen_at = excluded.last_seen_at,
      deprecated_at = null`;

  const markDeprecatedSql = `update ${fq} set deprecated_at = $3 where provider = $1 and model_id = $2 and deprecated_at is null`;

  return {
    async list(): Promise<CatalogEntry[]> {
      const res = await pool.query(selectAllSql);
      return res.rows.map(rowToEntry);
    },
    async listByProvider(provider: string): Promise<CatalogEntry[]> {
      const res = await pool.query(selectByProviderSql, [provider]);
      return res.rows.map(rowToEntry);
    },
    async upsert(entries: CatalogUpsert[], now = new Date()): Promise<void> {
      for (const entry of entries) {
        await pool.query(upsertSql, [
          entry.provider,
          entry.modelId,
          entry.family,
          entry.displayName,
          now,
        ]);
      }
    },
    async markDeprecated(keys, at): Promise<void> {
      for (const { provider, modelId } of keys) {
        await pool.query(markDeprecatedSql, [provider, modelId, at]);
      }
    },
  };
}
