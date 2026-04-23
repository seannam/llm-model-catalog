# Versioning

Preset: `node` (mode: `auto`). Source of truth: git tag `vX.Y.Z`.
Current: `0.1.0`. Primary manifest: `package.json`. Changelog: `CHANGELOG.md`.

## Bumping (mode: auto)

This repo auto-releases on push to `main`. Conventional commits drive the bump:

- `feat:` -> minor bump
- `fix:`, `perf:` -> patch bump
- `feat!:` / `BREAKING CHANGE:` -> major bump
- `chore:`, `docs:`, `test:`, etc. -> no release

The workflow lives at `.github/workflows/auto-release-on-push.yml`. It is
intentionally small: no builds, no tests, runs in ~10-20 seconds.

To force a local bump (emergency): `scripts/version/bump.sh --force`.

## Files kept in sync on every bump (app_root=.)

- `package.json` (json: version)
- `package-lock.json` (json: version)
- `VERSION` (plain)

## UI integration

Import version from package.json at build time. Vite, Next.js, Remix, and Astro all support this via JSON imports or env vars. For runtime reads (serverless, long-running processes), serve the VERSION file from a /version endpoint.

### cli

```
import { readFileSync } from 'node:fs'; const { version } = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
```

### express-endpoint

```
app.get('/version', (_, res) => res.json({ version: require('./package.json').version }));
```

### next

```
export const APP_VERSION = process.env.npm_package_version ?? 'dev';
```

### vite

```
import pkg from '../package.json'; export const APP_VERSION = pkg.version;
```


