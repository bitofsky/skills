#!/usr/bin/env bash
set -euxo pipefail

if command -v dnf >/dev/null 2>&1; then
  dnf update -y
  dnf install -y awscli jq findutils coreutils util-linux
elif command -v apt-get >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y awscli jq findutils coreutils util-linux
fi

mkdir -p /1 /2 /3
chmod 755 /1 /2 /3
