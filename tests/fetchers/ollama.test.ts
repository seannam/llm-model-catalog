import { describe, expect, it } from 'vitest';
import { ollamaFetcher } from '../../src/fetchers/ollama.js';
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

describe('ollamaFetcher', () => {
  it('parses /api/tags response', async () => {
    const entries = await ollamaFetcher().fetchModels({
      fetchImpl: makeFetch({
        models: [
          { name: 'qwen2.5-coder:32b', model: 'qwen2.5-coder:32b' },
          { name: 'llama3', model: 'llama3:8b' },
        ],
      }),
    });
    expect(entries).toHaveLength(2);
    expect(entries[0]!.modelId).toBe('qwen2.5-coder:32b');
    expect(entries[0]!.family).toBe('qwen-coder');
  });

  it('throws on HTTP failure', async () => {
    await expect(
      ollamaFetcher().fetchModels({
        fetchImpl: makeFetch({}, { ok: false, status: 500 }),
      }),
    ).rejects.toThrow(/ollama \/api\/tags request failed: 500/);
  });
});
