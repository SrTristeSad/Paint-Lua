#!/bin/sh
# Reconstrói core/ a partir da cópia versionada (sem alterar a casca).
set -eu
cd "$(dirname "$0")/.."

if [ -f core/doc.lua ]; then
  echo 'O núcleo já está extraído em core/.'
  exit 0
fi

parts=archive/core-v0.21.parts
if [ ! -f "$parts/part-00" ] || [ ! -f "$parts/part-11" ]; then
  echo 'Pacote do núcleo v0.21 ausente ou incompleto.' >&2
  exit 1
fi
for bin in base64 xz tar; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "Dependência necessária: $bin" >&2
    exit 1
  fi
done

tmp="${TMPDIR:-/tmp}/paint-lua-core-$$.tar.xz"
trap 'rm -f "$tmp"' 0 1 2 3 15
# -d no GNU/Linux; -D em algumas versões do BSD/macOS.
if ! cat "$parts"/part-* | base64 -d > "$tmp" 2>/dev/null; then
  cat "$parts"/part-* | base64 -D > "$tmp"
fi

expected=a7a241a7d76ac99a224c17013fe1d16802b3598f371c7d6d204f89774c76ce10
if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "$tmp" | cut -d ' ' -f 1)
elif command -v shasum >/dev/null 2>&1; then
  actual=$(shasum -a 256 "$tmp" | cut -d ' ' -f 1)
else
  echo 'Aviso: SHA-256 indisponível, conferindo somente o CRC do XZ.' >&2
  actual=$expected
fi
if [ "$actual" != "$expected" ]; then
  echo 'Falha de integridade do núcleo v0.21 (SHA-256 incorreto).' >&2
  exit 1
fi

xz -t "$tmp"
tar -xJf "$tmp"
if [ ! -f core/doc.lua ] || [ ! -f core/project.lua ]; then
  echo 'Extração incompleta do núcleo.' >&2
  exit 1
fi
echo 'Núcleo v0.21 extraído e conferido em core/.'
