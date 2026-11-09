#!/usr/bin/env bash
set -euo pipefail

if ! command -v hcloud >/dev/null; then
  curl -fsSL https://hwcloudcli.obs.cn-north-1.myhuaweicloud.com/cli/latest/hcloud_install.sh -o /tmp/hcloud_install.sh

  bash /tmp/hcloud_install.sh -y

  if [[ -n "${GITHUB_PATH:-}" ]]; then echo "$HOME/.hcloud/bin" >> "$GITHUB_PATH"; fi

  export PATH="$HOME/.hcloud/bin:$PATH"
fi

hcloud configure set --cli-agree-privacy-statement=true \
  --cli-read-timeout=20 --cli-connect-timeout=10 >/dev/null
hcloud version
