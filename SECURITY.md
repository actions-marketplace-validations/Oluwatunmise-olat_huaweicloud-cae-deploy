# Security Policy

## Supported Versions

This is a [composite GitHub Action](https://docs.github.com/en/actions/sharing-automations/creating-actions/about-custom-actions). There are no runtime binaries to patch; the action is the source in this repository.

| Version | Supported          |
| ------- | ------------------ |
| `main` (latest) | :white_check_mark: |

Callers are strongly encouraged to pin to a **full commit SHA** (or a release tag such as `v1`), never to a mutable branch like `main`.

## Security Model

The three actions in this repository implement OpenID Connect (OIDC)-based, short-lived credential federation with Huawei Cloud:

1. **`auth`** — exchanges the GitHub Actions OIDC token (from `ACTIONS_ID_TOKEN_REQUEST_URL`) for temporary STS credentials via Huawei Cloud IAM v5 `AssumeAgencyWithOIDC`. The AK/SK/SecurityToken are exported to `$GITHUB_ENV` for the remainder of the job and are **never** stored in repository secrets.

2. **`swr-login`** — uses those credentials to request a temporary SWR login (SWR `CreateSecret`, lifetime set by `duration-seconds`) and runs `docker login --password-stdin`. The registry password is masked and never placed on a command line.

3. **`huaweicloud-cae-deploy`** — consumes those credentials (or explicit `accessKey`/`secretKey`/`securityToken` inputs) and upgrades a CAE component. Credentials are passed only through the environment and via `::add-mask::`, never interpolated into a shell string.

### What this repository does NOT do

- It does **not** read, store, or transmit long-lived AK/SK pairs.
- It does **not** log secrets: all keys, tokens, and secret values are masked with `::add-mask::` before use.
- It does **not** require the `id-token` permission itself — that must be granted by the caller's workflow (`permissions: id-token: write`).

### Recommended caller hardening

- Pin `oidc:sub` in the IAM trust policy to a specific GitHub **environment** (`repo:ORG/REPO:environment:production`) or **branch** — never a wildcard like `repo:ORG/REPO:*` for production workloads. See [`docs/trust-policy.json`](docs/trust-policy.json).
- Attach the principle of least privilege to the trust agency (CAE operate only, plus SWR login + push on the target organization only if the same job pushes images).
- Use a separate agency per environment (staging / production), each with its own `oidc:sub`.
- On self-hosted runners, run `docker logout <registry>` at the end of the job; Docker keeps the login in `~/.docker/config.json`.
- Set the agency's maximum session duration to the smallest value your workflows need.
- Pin the action to a full commit SHA or release tag.

