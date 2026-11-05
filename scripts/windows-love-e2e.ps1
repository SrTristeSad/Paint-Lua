# Windows: execute the ACTUAL LÖVE editor from the extracted ZIP.
# Intended for GitHub Actions or local diagnostics, without touching paintings.
param(
    [Parameter(Mandatory=$true)][string]$LoveConsole,
    [Parameter(Mandatory=$true)][string]$ProjectDirectory,
    [ValidateSet('smoke','bridge')][string]$Mode='smoke',
    [ValidateRange(5,300)][int]$TimeoutSeconds=60,
    # CI hospedada sem GPU: permite somente um SKIP explicitamente diagnosticado.
    [switch]$AllowMissingGraphics
)
$ErrorActionPreference='Stop'
$exe=(Resolve-Path -LiteralPath $LoveConsole).Path
$root=(Resolve-Path -LiteralPath $ProjectDirectory).Path
if (-not (Test-Path (Join-Path $root 'main.lua'))) {
    throw "main.lua ausente no pacote: $root"
}
if ([IO.Path]::GetFileName($exe).ToLowerInvariant() -ne 'lovec.exe') {
    throw 'O teste automatizado exige lovec.exe (runtime console)'
}
$env:PAINT_LUA_SMOKE=$null
$env:PAINT_LUA_BRIDGE_E2E=$null
$env:PAINT_LUA_SCREEN=$null
if ($Mode -eq 'smoke') {
    $env:PAINT_LUA_SMOKE='1'
    $env:PAINT_LUA_SCREEN='editor'
} else {
    $env:PAINT_LUA_BRIDGE_E2E='1'
}
$temp=if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$stdout=Join-Path $temp ("paint-lua-$Mode.stdout.txt")
$stderr=Join-Path $temp ("paint-lua-$Mode.stderr.txt")
Remove-Item $stdout,$stderr -Force -ErrorAction SilentlyContinue
Write-Output "LÖVE 11.5 no Windows: iniciando teste $Mode do pacote..."
Write-Output "Windows: SESSIONNAME=$env:SESSIONNAME; USERINTERACTIVE=$([Environment]::UserInteractive)"
$proc=Start-Process -FilePath $exe -ArgumentList '.' -WorkingDirectory $root `
    -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
try {
    # Detectar cedo a caixa de erro modal do SDL, que não fecha no
    # runner sem driver OpenGL 2.1. Outros travamentos continuam a falhar.
    $exited=$false
    $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($proc.WaitForExit(800)) { $exited=$true; break }
        if ($AllowMissingGraphics -and (Test-Path -LiteralPath $stderr)) {
            $partial=Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue
            if ($partial -and $partial.Contains('GDI Generic') -and
                $partial.Contains('Unable to create OpenGL window')) { break }
        }
    }
    if (-not $exited) {
        $shot=Join-Path $env:APPDATA 'LOVE\paint-lua\ci-smoke.png'
        Write-Output "Windows: processo ainda ativo, screenshot existe=$(Test-Path -LiteralPath $shot)"
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        $proc.WaitForExit(3000) | Out-Null
    }
    $output=if (Test-Path $stdout) { Get-Content $stdout -Raw } else { '' }
    $errors=if (Test-Path $stderr) { Get-Content $stderr -Raw } else { '' }
    if ($output) { Write-Output "LÖVE stdout: $output" }
    if ($errors) { Write-Output "LÖVE stderr: $errors" }
    # Permitir dispensa SOMENTE para a incompatibilidade de OpenGL
    # confirmada pelo próprio runtime. Não transforma outros erros
    # ou timeouts em sucesso.
    $noGPU=($errors -and $errors.Contains('Unable to create OpenGL window')
        -and $errors.Contains('OpenGL 2.1') -and $errors.Contains('GDI Generic'))
    if ($AllowMissingGraphics -and $noGPU) {
        $reason='SKIP: GitHub Windows runner tem apenas OpenGL 1.1 GDI Generic; LÖVE 11.5 exige OpenGL 2.1'
        Write-Output "::warning title=Windows sem GPU compatível::$reason"
        if ($env:GITHUB_ENV) {
            Add-Content -LiteralPath $env:GITHUB_ENV -Value 'PAINT_LUA_GRAPHICS_UNAVAILABLE=1'
        }
        if ($env:GITHUB_STEP_SUMMARY) {
            Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value (
                "### Teste gráfico Windows não executado`n" +
                "$reason. O ZIP e o inicializador foram verificados separadamente. " +
                "Testes gráficos completos no Linux passaram; valide Windows em hardware com GPU.`n")
        }
        return
    }
    if (-not $exited) {
        throw "LÖVE Windows: timeout no teste $Mode após $TimeoutSeconds segundos; logs acima"
    }
    if ($proc.ExitCode -ne 0) { throw "LÖVE Windows $Mode falhou: exit $($proc.ExitCode)" }
    if ($Mode -eq 'bridge') {
        if (-not $output.Contains('PASS: L')) {
            throw "LÖVE Windows $Mode encerrou sem emitir provas PASS da suite real"
        }
    } else {
        $shot=Join-Path $env:APPDATA 'LOVE\paint-lua\ci-smoke.png'
        if (-not (Test-Path -LiteralPath $shot)) {
            throw "LÖVE Windows inicializou, mas não gerou screenshot: $shot"
        }
        $bytes=[IO.File]::ReadAllBytes($shot)
        if ($bytes.Length -lt 1000 -or
            -not ($bytes[0] -eq 137 -and $bytes[1] -eq 80 -and
                  $bytes[2] -eq 78 -and $bytes[3] -eq 71)) {
            throw "LÖVE Windows gerou imagem inválida de screenshot"
        }
        Write-Output "PASS: editor Windows desenhou a interface e gravou screenshot PNG ($($bytes.Length) bytes)"
        Remove-Item -LiteralPath $shot -Force
    }
    Write-Output "PASS: LÖVE Windows $Mode — processo concluído sem erro"
} finally {
    $env:PAINT_LUA_SMOKE=$null
    $env:PAINT_LUA_BRIDGE_E2E=$null
    $env:PAINT_LUA_SCREEN=$null
}
