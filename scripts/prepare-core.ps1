# Prepara o motor v0.21 no Windows a partir das 12 partes versionadas.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$core = Join-Path $root 'core'
if (Test-Path (Join-Path $core 'doc.lua')) { Write-Host 'Nucleo ja pronto.'; exit 0 }
if (Test-Path $core) { throw 'Pasta core incompleta; faca backup antes de substituir.' }
$dir = Join-Path $root 'archive/core-v0.21.parts'
$parts = @(Get-ChildItem -LiteralPath $dir -Filter 'part-*' -File | Sort-Object Name)
if ($parts.Count -ne 12) { throw 'Pacote incompleto (esperadas 12 partes).' }
$encoded = [string]::Concat(($parts | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }))
$bytes = [Convert]::FromBase64String($encoded)
$expected = 'a7a241a7d76ac99a224c17013fe1d16802b3598f371c7d6d204f89774c76ce10'
$sha = [BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($bytes)).Replace('-','').ToLowerInvariant()
if ($sha -ne $expected) { throw 'Falha de SHA-256 do nucleo.' }
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('paintlua-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($tmp) | Out-Null
try {
  $packed = Join-Path $tmp 'core.tar.xz'
  [IO.File]::WriteAllBytes($packed,$bytes)
  & tar.exe -xJf $packed -C $tmp
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $tmp 'core/doc.lua'))) {
    throw 'Nao foi possivel extrair o nucleo.'
  }
  Move-Item -LiteralPath (Join-Path $tmp 'core') -Destination $core
  Write-Host 'Motor v0.21 instalado e verificado.'
} finally {
  if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
}
