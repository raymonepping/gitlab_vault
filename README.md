# Vault Identity Insights

`Vault Identity Insights` is a local Vue 3 + TypeScript + Vite + Tailwind dashboard for exploring Vault audit activity tied to GitLab identities.

It is designed as an executive-friendly demo UI for answering questions like:

- who accessed a secret
- from which GitLab project, pipeline, and job
- which identities touched the same secret path
- which users and workloads appear most often
- how access changes when a local time window is applied

## Stack

- Vue 3
- TypeScript
- Vite
- Tailwind CSS 4

## What The App Shows

The dashboard currently includes:

- summary cards for key metrics and latest activity
- a proof table for identical secret access across different identities
- a local time filter bar with presets and manual range inputs
- top consumer panels for users and paths
- identity exploration tabs for humans, workloads, and timeline events
- a compare panel for side-by-side bundle comparison
- a detail drawer for selected records
- reusable collapsible executive panels with persisted open/closed state

## Data Source

The app reads its data from:

- [public/data/vault_identity.json](/Users/raymon.epping/Documents/VSC/Personal/gitlab/vault-identity-ui/public/data/vault_identity.json)

That file is generated from the Vault audit parser script in the sibling `scripts` directory:

- [parse_vault.sh](/Users/raymon.epping/Documents/VSC/Personal/gitlab/scripts/parse_vault.sh)

The JSON includes:

- metadata such as `schema_version`, `generated_at`, and `source_file`
- aggregate counts
- latest secret access
- top path and per-secret path rollups
- timeline events
- human identities
- workload identities
- full identity bundles

## Project Structure

- [src/App.vue](/Users/raymon.epping/Documents/VSC/Personal/gitlab/vault-identity-ui/src/App.vue): top-level composition and data wiring
- [src/composables/useVaultData.ts](/Users/raymon.epping/Documents/VSC/Personal/gitlab/vault-identity-ui/src/composables/useVaultData.ts): loads the JSON dataset
- [src/types/vault.ts](/Users/raymon.epping/Documents/VSC/Personal/gitlab/vault-identity-ui/src/types/vault.ts): frontend TypeScript types
- [src/style.css](/Users/raymon.epping/Documents/VSC/Personal/gitlab/vault-identity-ui/src/style.css): shared visual system and layout

Key UI components:

- [src/components/DashboardHeader.vue](/Users/raymon.epping/Documents/VSC/Personal/gitlab/vault-identity-ui/src/components/DashboardHeader.vue)
- [src/components/SummaryCards.vue](/Users/raymon.epping/Documents/VSC/Personal/gitlab/vault-identity-ui/src/components/SummaryCards.vue)
- [src/components/FingerprintTable.vue](/Users/raymon.epping/Documents/VSC/Personal/gitlab/vault-identity-ui/src/components/FingerprintTable.vue)
- [src/components/TimeFilterBar.vue](/Users/raymon.epping/Documents/VSC/Personal/gitlab/vault-identity-ui/src/components/TimeFilterBar.vue)
- [src/components/TopConsumers.vue](/Users/raymon.epping/Documents/VSC/Personal/gitlab/vault-identity-ui/src/components/TopConsumers.vue)
- [src/components/InsightsTab.vue](/Users/raymon.epping/Documents/VSC/Personal/gitlab/vault-identity-ui/src/components/InsightsTab.vue)
- [src/components/ComparePanel.vue](/Users/raymon.epping/Documents/VSC/Personal/gitlab/vault-identity-ui/src/components/ComparePanel.vue)
- [src/components/DetailDrawer.vue](/Users/raymon.epping/Documents/VSC/Personal/gitlab/vault-identity-ui/src/components/DetailDrawer.vue)
- [src/components/CollapsiblePanel.vue](/Users/raymon.epping/Documents/VSC/Personal/gitlab/vault-identity-ui/src/components/CollapsiblePanel.vue)

## Executive Panel Behavior

Several sections use the reusable collapsible panel wrapper:

- Top Consumers
- Identity Views
- Compare Identity Fingerprints
- Core Proof
- Local Time Filter

Behavior:

- default state is collapsed
- hover adds emphasis and preview only
- click toggles full expansion
- state can persist locally through `localStorage`

This is implemented in:

- [src/components/CollapsiblePanel.vue](/Users/raymon.epping/Documents/VSC/Personal/gitlab/vault-identity-ui/src/components/CollapsiblePanel.vue)

## Local Development

Install dependencies:

```bash
npm install
```

Start the dev server:

```bash
npm run dev
```

Build for production:

```bash
npm run build
```

Preview the production build:

```bash
npm run preview
```

## Updating The Dataset

Typical flow:

1. Generate or refresh the Vault report JSON with the parser script.
2. Write or copy the output to `public/data/vault_identity.json`.
3. Restart `npm run dev` if needed, or refresh the browser.

Example:

```bash
../scripts/parse_vault.sh ../input/vault_audit.log --secrets-only --format json > ./public/data/vault_identity.json
```

## Export Support

The dashboard includes a Markdown export action wired through:

- [src/utils/exportMarkdown.ts](/Users/raymon.epping/Documents/VSC/Personal/gitlab/vault-identity-ui/src/utils/exportMarkdown.ts)

The export uses the currently filtered in-memory view from [src/App.vue](/Users/raymon.epping/Documents/VSC/Personal/gitlab/vault-identity-ui/src/App.vue), not just the raw source file.

## Styling Notes

The UI uses a dark, customer-facing visual system with:

- black and charcoal backgrounds
- muted grey typography
- gold, orange, and yellow accents
- restrained motion and hover lift
- path token highlighting
- badge-based semantic emphasis for operations like `read`

Shared tokens and utility-like classes live in:

- [src/style.css](/Users/raymon.epping/Documents/VSC/Personal/gitlab/vault-identity-ui/src/style.css)

## Notes

- the app expects a local static JSON file, not a live backend
- filtering is done client-side on the loaded dataset
- the time filter is local-only and does not rerun the parser
- the dashboard is optimized for demo clarity, not multi-user production auth flows

