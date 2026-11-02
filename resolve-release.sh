#!/usr/bin/env bash
# Prints `url=` and `tag=` for the Reapr release to install, from REAPR_VERSION (`latest` or X.Y.Z).
# Reapr releases are tagged `rpr-v<version>` (sampo + cargo-dist), not `v<version>`.
set -euo pipefail
repo=https://github.com/reapr-corp/reapr/releases
version="${REAPR_VERSION:-latest}"
if [ "$version" = latest ]; then
  printf 'url=%s\ntag=\n' "$repo/latest/download"
  exit 0
fi
if ! printf '%s' "$version" | grep -Eq '^v?[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$'; then
  echo "::error title=Reapr::Invalid 'version' input: '$version' (expected latest or X.Y.Z)." >&2
  exit 2
fi
tag="rpr-v${version#v}"
printf 'url=%s\ntag=%s\n' "$repo/download/$tag" "$tag"
