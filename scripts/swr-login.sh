#!/usr/bin/env bash
set -euo pipefail

: "${REGION:?REGION is required}"

ACCESS_KEY="${ACCESS_KEY:-${HUAWEICLOUD_SDK_AK:-}}"

SECRET_KEY="${SECRET_KEY:-${HUAWEICLOUD_SDK_SK:-}}"

SECURITY_TOKEN="${SECURITY_TOKEN:-${HUAWEICLOUD_SDK_SECURITY_TOKEN:-}}"

if [[ -z "$ACCESS_KEY" || -z "$SECRET_KEY" ]]; then
  echo "No credentials. Run the huaweicloud-cae-deploy/auth step first, or pass accessKey/secretKey." >&2
  exit 1
fi

echo "::add-mask::$SECRET_KEY"

if [[ -n "$SECURITY_TOKEN" ]]; then echo "::add-mask::$SECURITY_TOKEN"; fi

args=(SWR CreateSecret --cli-region="$REGION" --cli-output=json
      --cli-access-key="$ACCESS_KEY" --cli-secret-key="$SECRET_KEY"
      --projectname="$REGION")

if [[ -n "$SECURITY_TOKEN" ]]; then args+=(--cli-security-token="$SECURITY_TOKEN"); fi

if [[ -n "${DURATION:-}" ]]; then args+=(--duration_seconds="$DURATION"); fi

if ! out="$(hcloud "${args[@]}" 2>&1)"; then
  echo "SWR CreateSecret failed:" >&2
  echo "$out" >&2
  exit 1
fi

if ! registry="$(jq -er '.auths | keys[0]' <<<"$out" 2>/dev/null)"; then
  echo "Unexpected CreateSecret response (no .auths); check hcloud version / API changes." >&2
  exit 1
fi
auth="$(jq -er --arg r "$registry" '.auths[$r].auth' <<<"$out")"
echo "::add-mask::$auth"

decoded="$(base64 -d <<<"$auth")"
if [[ "$decoded" != *:* ]]; then
  echo "Unexpected auth format from CreateSecret (expected user:password)." >&2
  exit 1
fi
user="${decoded%%:*}"
pass="${decoded#*:}"
echo "::add-mask::$pass"

printf '%s' "$pass" | docker login --username "$user" --password-stdin "$registry"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo "registry=$registry" >> "$GITHUB_OUTPUT"; fi
echo "Logged in to $registry" >&2
