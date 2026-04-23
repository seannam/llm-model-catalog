import { describe, expect, it } from 'vitest';
import { migrationSql } from '../src/migration.js';

describe('migrationSql', () => {
  it('substitutes schema and default table name', () => {
    const sql = migrationSql({ schema: 'buildlog' });
    expect(sql).toContain('create table if not exists buildlog.llm_model_catalog');
    expect(sql).toContain('llm_model_catalog_provider_family_idx');
  });

  it('substitutes a custom table name', () => {
    const sql = migrationSql({ schema: 'public', tableName: 'my_catalog' });
    expect(sql).toContain('create table if not exists public.my_catalog');
    expect(sql).toContain('my_catalog_provider_family_idx');
  });

  it('rejects a schema with invalid characters', () => {
    expect(() => migrationSql({ schema: 'bad-schema' })).toThrow(/bare SQL identifier/);
    expect(() => migrationSql({ schema: 'drop table;' })).toThrow(/bare SQL identifier/);
  });

  it('rejects an empty schema', () => {
    expect(() => migrationSql({ schema: '' })).toThrow();
  });

  it('rejects an invalid table name', () => {
    expect(() => migrationSql({ schema: 'public', tableName: '1_bad' })).toThrow();
  });

  it('output is idempotent (uses if not exists)', () => {
    const sql = migrationSql({ schema: 'public' });
    expect(sql).toMatch(/create table if not exists/);
    expect(sql).toMatch(/create index if not exists/);
  });
});
