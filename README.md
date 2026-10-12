# FamilyOS CI Runner

Dedicated CI runner repository leveraging GitHub Actions public macOS runners for automated iOS building and IPA artifact packaging.

## How it works

1. **Ephemeral Execution**: When triggered, a macOS runner launches in an isolated, short-lived environment.
2. **Secure Private Fetch**: Uses a dedicated read-only deploy key (`PRIVATE_SSH_KEY`) to fetch source code from the private `FamilyOS` repository.
3. **Zero Source Exposure**: No source code or secrets are ever checked into or exposed on this repository.
4. **Artifact Generation**: Packages unsigned `.ipa` and `.app` bundles ready for Sideloadly / AltStore sideloading.

## MCP gateway verification (`ci_mcp_gateway.yml`)

Verifies `rh-gateway/` in the private `Mcp` repository: `npm ci`, typecheck, the workerd test
suite (Robinhood mocked), a `wrangler deploy --dry-run` bundle, and a committed-credential scan.
Verification needs no Cloudflare or Robinhood credentials.

Deploy is a separate job: manual run with `deploy: true` only. It deploys the exact commit that
passed verification, refuses placeholder config, then requires `/healthz` 200 and an
unauthenticated `/mcp` 401. Secrets: `CLOUDFLARE_API_TOKEN` (Workers Admin for the first deploy,
then Editor for `rh-readonly-gateway` only) and optionally `CLOUDFLARE_ACCOUNT_ID`, in the
`cloudflare-production` environment. Add required reviewers on that environment to gate deploys.

- **Checkout:** uses `MCP_SSH_KEY` (a read-only deploy key on `venkateshp546/Mcp`) when set, else the
  existing `PRIVATE_REPO_TOKEN` if that token can read `Mcp`. `PRIVATE_SSH_KEY` cannot be reused:
  deploy keys are per repository.
- **Triggers:** manual (`workflow_dispatch`, `branch` input) or `repository_dispatch` types `mcp-push` / `mcp-verify`
  with `client_payload.branch`.
