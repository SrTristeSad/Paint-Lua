#!/bin/sh
# Expande a cópia versionada do motor quando o repositório foi clonado do GitHub.
set -eu
cd "$(dirname "$0")/.."
if [ -f core/doc.lua ]; then
  echo 'O núcleo já está extraído em core/.'
  exit 0
fi
if [ ! -d archive/core-v0.21.parts ]; then
  echo 'Arquivos da cópia do núcleo não encontrados.' >&2
  exit 1
fi
if ! command -v xz >/dev/null 2>&1; then
  echo 'xz é necessário para extrair o núcleo.' >&2
  exit 1
fi
cat archive/core-v0.21.parts/* | base64 -d | tar -xJf -
if [ ! -f core/doc.lua ]; then
  echo 'A extração não produziu core/doc.lua.' >&2
  exit 1
fi
echo 'Núcleo v0.21 extraído.'
