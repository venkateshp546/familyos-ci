# FamilyOS CI Runner

Dedicated CI runner repository leveraging GitHub Actions public macOS runners for automated iOS building and IPA artifact packaging.

## How it works

1. **Ephemeral Execution**: When triggered, a macOS runner launches in an isolated, short-lived environment.
2. **Secure Private Fetch**: Uses a dedicated read-only deploy key (`PRIVATE_SSH_KEY`) to fetch source code from the private `FamilyOS` repository.
3. **Zero Source Exposure**: No source code or secrets are ever checked into or exposed on this repository.
4. **Artifact Generation**: Packages unsigned `.ipa` and `.app` bundles ready for Sideloadly / AltStore sideloading.
