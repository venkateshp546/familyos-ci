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
It never deploys and needs no Cloudflare or Robinhood credentials.

- **Secret:** `MCP_SSH_KEY`, the private half of a **read-only deploy key** added to `venkateshp546/Mcp`
  (deploy keys are per repository, so `PRIVATE_SSH_KEY` cannot be reused).
- **Triggers:** manual (`workflow_dispatch`, `branch` input) or `repository_dispatch` types `mcp-push` / `mcp-verify`
  with `client_payload.branch`.
