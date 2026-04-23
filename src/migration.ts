/**
 * SQL migration helper.
 *
 * Returns the `CREATE TABLE IF NOT EXISTS` statement for the catalog
 * table with the caller's schema and table name substituted in.
 * Consumers are free to apply it with any migration runner
 * (node-pg-migrate, Drizzle-kit, hand-rolled, Django, Rails). The
 * library ships the SQL string, not the runner.
 *
 * Schema and table names are validated against `^[a-zA-Z_][a-zA-Z0-9_]*$`
 * to avoid SQL injection via identifier interpolation; callers that
 * need quoted-identifier support should use a dedicated migration tool
 * instead.
 */

const IDENTIFIER_RE = /^[a-zA-Z_][a-zA-Z0-9_]*$/;

export interface MigrationSqlOptions {
  /** Schema to place the table in. Must be a bare SQL identifier. */
  schema: string;
  /** Table name. Defaults to `llm_model_catalog`. Must be a bare SQL identifier. */
  tableName?: string;
}

function assertIdentifier(label: string, value: string): void {
  if (!IDENTIFIER_RE.test(value)) {
    throw new Error(
      `migrationSql: ${label} must be a bare SQL identifier (letters, digits, underscores; not starting with a digit); got ${JSON.stringify(value)}`,
    );
  }
}

/**
 * Render the catalog-table SQL for a consumer's schema.
 *
 * Emits one idempotent `create table if not exists` plus a supporting
 * partial index. Safe to run every boot.
 */
export function migrationSql(options: MigrationSqlOptions): string {
  const schema = options.schema;
  const tableName = options.tableName ?? 'llm_model_catalog';
  assertIdentifier('schema', schema);
  assertIdentifier('tableName', tableName);

  return `create table if not exists ${schema}.${tableName} (
  provider       text not null,
  model_id       text not null,
  family         text not null,
  display_name   text,
  first_seen_at  timestamptz not null default now(),
  last_seen_at   timestamptz not null default now(),
  deprecated_at  timestamptz,
  primary key (provider, model_id)
);

create index if not exists ${tableName}_provider_family_idx
  on ${schema}.${tableName} (provider, family)
  where deprecated_at is null;
`;
}
