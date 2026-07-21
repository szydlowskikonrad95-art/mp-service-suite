#!/usr/bin/env bash
# Build 3 pluginow MP: stempluje kopie lib/mp-common (namespace per plugin),
# generuje BUILD-INFO (commit+hash+czas), sklada ZIP-y i robi smoke-test kopii.
# Kopie w drzewie zrodel (includes/Common/) sa GENEROWANE i gitignorowane —
# edycje wspolnego kodu WYLACZNIE w lib/mp-common (dyscyplina z rundy W).
set -euo pipefail
cd "$(dirname "$0")/.."

PLUGINS=("mp-service-intake:Intake" "mp-warranty-registry:Registry" "mp-workflow-automator:Automator")
DIST="build/dist"

COMMIT="$(git rev-parse HEAD 2>/dev/null || echo 'no-git')"
BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# hash ZRODLA mp-common — jedna wartosc per commit (hash kopii rozni sie z definicji po stemplu)
COMMON_HASH="$(find lib/mp-common/src -type f -name '*.php' -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)"

rm -rf "$DIST"
mkdir -p "$DIST"

stamp_common() { # $1=katalog docelowy includes/Common, $2=segment namespace (Intake/Registry/Automator)
  local target="$1" ns="$2" src base
  rm -rf "$target"
  mkdir -p "$target"
  for src in lib/mp-common/src/*.php; do
    base="$(basename "$src")"
    sed -e "s/namespace MP\\\\Common/namespace MP\\\\${ns}\\\\Common/" \
        -e "s/use MP\\\\Common\\\\/use MP\\\\${ns}\\\\Common\\\\/g" \
        -e "s/@package MP\\\\Common/@package MP\\\\${ns}\\\\Common/" \
        "$src" > "$target/$base"
    php -l "$target/$base" > /dev/null
  done
}

for entry in "${PLUGINS[@]}"; do
  dir="${entry%%:*}"
  ns="${entry##*:}"

  # 1) kopie robocze w drzewie zrodel (dev/Docker montuje surowe katalogi pluginow)
  stamp_common "$dir/includes/Common" "$ns"

  # 2) katalog dystrybucyjny
  rsync -a --exclude 'includes/Common' "$dir/" "$DIST/$dir/"
  stamp_common "$DIST/$dir/includes/Common" "$ns"

  # 3) slad pochodzenia builda (ZIP bez wiarygodnego BUILD-INFO = nie z CI)
  printf '{"plugin":"%s","commit":"%s","common_hash":"%s","built_at":"%s"}\n' \
    "$dir" "$COMMIT" "$COMMON_HASH" "$BUILD_TIME" > "$DIST/$dir/BUILD-INFO.json"

  # 4) smoke: autoloader kopii dystrybucyjnej laduje klase Common
  php -r "require '$DIST/$dir/includes/Autoloader.php'; MP\\${ns}\\Autoloader::register(); exit(class_exists('MP\\${ns}\\Common\\Common') ? 0 : 1);"

  # 5) ZIP artefaktu
  if command -v zip > /dev/null 2>&1; then
    (cd "$DIST" && zip -qr "$dir.zip" "$dir")
  else
    (cd "$DIST" && python3 -m zipfile -c "$dir.zip" "$dir")
  fi
  echo "OK: $dir (common=$COMMON_HASH)"
done

echo "BUILD KOMPLET: commit=$COMMIT czas=$BUILD_TIME"
