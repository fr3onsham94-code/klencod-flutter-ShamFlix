# Universal Website Engine

This module is the shared discovery contract for website-backed TV sources.

## Design

- A website is described by `WebsiteSiteConfig`; it is not hard-coded into the source importer.
- A `WebsiteDiscoveryAdapter` converts page snapshots into channel candidates.
- `WebsiteEngine` selects an adapter, validates page origins against the configured host allow-list, deduplicates channel pages and returns a normalized result.
- The generic adapter is intentionally conservative. It recognizes same-site links whose paths indicate channel/live pages. Provider-specific layouts can add adapters without changing M3U or Xtream import.

## Authentication boundary

- Interactive login is performed by the site's own page in the embedded WebView.
- The engine does not read passwords, cookies, local/session storage, authorization headers or browser profile data.
- Short-lived signed media URLs may be represented in memory as playback candidates only. They must not be written to source configuration, logs or long-lived database rows.
- DRM license requests, decryption keys and protected media extraction are out of scope. A site that requires those mechanisms is not a supported direct-stream adapter.
- Only HTTPS pages on explicitly allowed hosts are eligible for discovery.

## Current implementation status

This commit adds the reusable model, adapter contract, conservative generic adapter and registry. The existing authenticated WebView scanner and public server-side crawler are not replaced by this foundation yet. The next integration step is to feed authenticated WebView page snapshots into this engine, then add bounded automatic traversal of same-site channel pages and a session-aware playback handoff.

## Compatibility

The engine is isolated under `lib/website_engine/`. It does not modify M3U/Xtream import, existing source records, database schema, Supabase functions, production configuration or the `main` branch.
