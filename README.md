# **Huawei Cloud CAE Deploy Action**

[![Validate](https://github.com/Oluwatunmise-olat/huaweicloud-cae-deploy/actions/workflows/validate.yml/badge.svg)](https://github.com/Oluwatunmise-olat/huaweicloud-cae-deploy/actions/workflows/validate.yml)

This GitHub Action upgrades a component in **Huawei Cloud Cloud Application Engine (CAE)** to a new image, without storing long-lived Access Key / Secret Key pairs in your repository. It uses the **Huawei Cloud CLI (`hcloud`)** and, optionally, a companion `auth` action that exchanges GitHub's OIDC token for short-lived STS credentials.

It mirrors the shape of the `google-github-actions` pair:

| Action | Equivalent to | What it does |
|---|---|---|
| `huaweicloud-cae-deploy/auth` | `google-github-actions/auth` | Exchanges the GitHub OIDC token for short-lived STS credentials (IAM v5 `AssumeAgencyWithOIDC`) and exports them as `HUAWEICLOUD_SDK_AK` / `_SK` / `_SECURITY_TOKEN` |
| `huaweicloud-cae-deploy/swr-login` | `docker/login-action` with `auth` credentials | Turns those short-lived credentials into a temporary SWR `docker login` (SWR `CreateSecret`), so pushing images needs no stored AK/SK either |
| `huaweicloud-cae-deploy` | `google-github-actions/deploy-appengine` | Resolves the CAE environment/application/component by name and upgrades it to a new SWR image |

---

## **Features**

* Upgrades a CAE component to a new SWR image on every run
* Supports short-lived STS credentials via OIDC (no AK/SK stored in secrets)
* Pushes images to SWR with a temporary docker login from the same credentials (`swr-login`)
* Falls back to explicit `accessKey` / `secretKey` / `securityToken` inputs if you skip the `auth` step
* Resolves environment, application, and component names to IDs automatically
* Masks all secrets and tokens in workflow logs

---

## **Usage**

### **1. One-time Huawei Cloud setup (IAM v5)**

1. **Identity provider** — IAM v5 console → Identity Providers → Create. Type `OIDC`, name `github_com`, URL `https://token.actions.githubusercontent.com`, audience `sts.huaweicloud.com`.
2. **Agency** — IAM v5 console → Agencies → Create, with a custom trust policy. Use [`docs/trust-policy.json`](docs/trust-policy.json), replacing `<ACCOUNT_ID>`, `<ORG>`, `<REPO>`. Pin `oidc:sub` to a GitHub environment (`repo:ORG/REPO:environment:production`) or branch (`repo:ORG/REPO:ref:refs/heads/main`) — never a bare `repo:ORG/REPO:*` for production.
3. **Permissions** — attach only what the workflow needs to the agency: CAE operate permissions for the deploy; if the same job pushes images, SWR permission to create a temporary login (`swr::createLoginSecret`) and to push to the target organization. Scope everything to the deploy region's project. Use one agency per environment (staging / production) so a staging run can never deploy production.
4. In the **app repo** — create a `production` environment and repository variables `HUAWEI_OIDC_PROVIDER_URN`, `HUAWEI_AGENCY_URN`, `HUAWEI_PROJECT_ID`.

### **2. Create workflow (`.github/workflows/deploy-cae.yml`)**

```yaml
name: Deploy to CAE

on:
  push:
    branches: [ main ]

permissions:
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4

      - name: Authenticate to Huawei Cloud (OIDC)
        uses: Oluwatunmise-olat/huaweicloud-cae-deploy/auth@FULL_COMMIT_SHA
        with:
          provider-urn: ${{ vars.HUAWEI_OIDC_PROVIDER_URN }}
          agency-urn: ${{ vars.HUAWEI_AGENCY_URN }}
          sts-region: af-south-1
          duration-seconds: 3600

      - name: Log in to SWR (temporary, no stored keys)
        uses: Oluwatunmise-olat/huaweicloud-cae-deploy/swr-login@FULL_COMMIT_SHA
        with:
          region: af-south-1

      - uses: docker/setup-buildx-action@v3

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: swr.af-south-1.myhuaweicloud.com/my-org/my-image:${{ github.sha }}

      - name: Deploy to CAE
        uses: Oluwatunmise-olat/huaweicloud-cae-deploy@FULL_COMMIT_SHA
        with:
          project_id: ${{ vars.HUAWEI_PROJECT_ID }}
          region: af-south-1
          environment_name: my-env
          app_name: my-app
          component_name: my-component
          swr_organization: my-org
          swr_repository: my-image
          image_tag: ${{ github.sha }}
```

If the image is already in SWR (e.g. promoting a tested tag), drop the `swr-login` and build steps.

A complete, runnable example is in [`examples/deploy-cae.yml`](examples/deploy-cae.yml).

---

## **Inputs**

### `auth`

| Name | Description | Required | Default |
|---|---|---|---|
| `provider-urn` | `iam::<account-id>:oidcProvider:<name>` | Yes | |
| `agency-urn` | `iam::<account-id>:agency:<name>` | Yes | |
| `sts-region` | Region whose STS endpoint is called | No | `ap-southeast-1` |
| `audience` | Must match the IdP's audience | No | `sts.huaweicloud.com` |
| `duration-seconds` | Credential lifetime, 900-43200 | No | `3600` |
| `session-name` | Appears in CTS audit logs (2-128 chars, `[A-Za-z0-9_+=,.@-]`) | No | `gha-<run_id>-<attempt>` |

Output: `expiration`.

### `swr-login`

| Name | Description | Required | Default |
|---|---|---|---|
| `region` | SWR region, e.g. `af-south-1` | Yes | |
| `duration-seconds` | Login lifetime, 900-86400; empty uses the API default | No | `3600` |
| `accessKey` / `secretKey` / `securityToken` | Only needed if you skip the `auth` step | No | from env |

Output: `registry` (e.g. `swr.af-south-1.myhuaweicloud.com`).

### Deploy (root action)

| Name | Description | Required | Default |
|---|---|---|---|
| `project_id` | Huawei Cloud project ID for the region | Yes | |
| `region` | e.g. `af-south-1` | Yes | |
| `environment_name` | CAE environment name | Yes | |
| `app_name` | CAE application name | Yes | |
| `component_name` | CAE component name | Yes | |
| `swr_organization` | SWR organization | Yes | |
| `swr_repository` | SWR repository | Yes | |
| `image_tag` | Image tag | Yes | |
| `version` | Version annotation on the CAE upgrade | No | `image_tag` |
| `enterprise_project_id` | Enterprise project ID | No | `0` |
| `accessKey` / `secretKey` / `securityToken` | Only needed if you skip the `auth` step | No | from env |

---

## **Security Practices**

* Credentials come from short-lived STS tokens via OIDC, not stored secrets
* All keys, tokens, and secrets are masked in workflow logs (`::add-mask::`)
* Inputs are passed through `env`, never interpolated directly into shell commands
* Trust policy should pin `oidc:sub` to a specific GitHub environment or branch, not a wildcard
* `swr-login` passes the registry password to `docker login --password-stdin`, never on the command line
* Docker stores the login in `~/.docker/config.json`. GitHub-hosted runners are discarded after the job; on **self-hosted** runners, add `docker logout <registry>` as a final `if: always()` step

---

## **Prerequisites**

* A Huawei Cloud account with an IAM v5 OIDC identity provider and agency configured for this repository (see setup above), or AK/SK credentials if calling the deploy action directly
* A CAE environment, application, and component already created
* Project ID and, if applicable, Enterprise Project ID
* An SWR image repository already populated (via CI/CD or manual push)
* A runner with `bash`, `curl`, and `jq` available (all pre-installed on `ubuntu-latest`); the action also installs `hcloud` (KooCLI) on first use
* For `swr-login`: Docker on the runner (pre-installed on `ubuntu-latest`)

---

## **Troubleshooting**

**No OIDC token available**
The job is missing `permissions: id-token: write`.

**STS 403**
The token's `sub`/`aud`/`iss` don't match the trust policy. Repos created or renamed after GitHub's immutable-subject-claim change may use a different `sub` format — check what the token actually contains.

**STS connection error**
Try `sts-region: ap-southeast-1`.

**Environment / Application / Component not found**
Names are case-sensitive, and `project_id` must belong to `region`.

**SWR CreateSecret failed**
The agency lacks permission to create a temporary SWR login, or the credentials expired. If the error mentions `duration_seconds`, your KooCLI version predates that parameter: set `duration-seconds: ""` to use the API default.

**`denied: requested access to the resource is denied` on push**
Login worked, but the agency has no push permission on that SWR organization.

**Credentials expired mid-job**
`auth` credentials last `duration-seconds` (default 3600). Raise it if your build is long.

**Invalid image URL**
The image URL must follow this pattern:

```
swr.<region>.myhuaweicloud.com/<swr_organization>/<swr_repository>:<image_tag>
```

---

## **Reference Docs**

* [CAE Product Overview](https://support.huaweicloud.com/intl/en-us/productdesc-cae/cae_01_0001.html)
* [Huawei Cloud CLI (`hcloud`)](https://support.huaweicloud.com/intl/en-us/productdesc-hcli/hcli_01.html)
* [SWR: Generating a Temporary Login Command (`CreateSecret`)](https://support.huaweicloud.com/intl/en-us/api-swr/swr_02_0052.html)
* [Enterprise Project Management](https://support.huaweicloud.com/intl/en-us/usermanual-em/pm_topic_0003.html)

---

## **Versioning**

Callers should pin to a full commit SHA, not a tag or branch.

---

## **License**

Licensed under the **MIT License**.
