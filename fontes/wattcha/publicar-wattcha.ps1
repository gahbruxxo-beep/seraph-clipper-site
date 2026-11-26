# ============================================================
#  Publica uma versao nova do Wattcha na pasta wattcha\ do site.
#  1. Confere a sintaxe do fontes\wattcha\Wattcha.ps1 e le a $VersaoApp dele
#  2. Copia byte a byte para wattcha\Wattcha.ps1
#  3. Calcula o SHA-256 e ASSINA o arquivo com a chave privada
#     (RSA-SHA256, PKCS#1 v1.5, sobre os bytes do proprio Wattcha.ps1, em base64)
#  4. Grava wattcha\versao.json  {"versao","sha256","notas","assinatura"}
#     (os apps 1.0.2/1.0.3 so olham o sha256; da 1.0.4 em diante exigem a assinatura)
#  5. Refaz wattcha\Wattcha-Instalador.exe com o iexpress (a nao ser com -SemInstalador)
#  Nao faz git commit nem push: confira e publique voce mesmo.
#
#  Uso:
#   powershell -NoProfile -ExecutionPolicy Bypass -File publicar-wattcha.ps1 -Notas "O que mudou"
#   (opcional) -ChavePrivada "caminho\da\chave.xml"   -SemInstalador
# ============================================================
param(
    [Parameter(Mandatory = $true)][string]$Notas,
    [string]$ChavePrivada = 'G:\Meu Drive\VisusTV\4-Chaves-e-senhas\wattcha-assinatura-privada.xml',
    [switch]$SemInstalador
)
$ErrorActionPreference = 'Stop'
$fonte = $PSScriptRoot
$raiz = Split-Path (Split-Path $fonte -Parent) -Parent
$saida = Join-Path $raiz 'wattcha'
$arqFonte = Join-Path $fonte 'Wattcha.ps1'
$utf8SemBom = New-Object Text.UTF8Encoding($false)

function Falhar($msg) { Write-Host ('ERRO: ' + $msg) -ForegroundColor Red; exit 1 }

# ---- 1. sintaxe e versao ----
foreach ($a in @('Wattcha.ps1', 'Instalar.ps1', 'Desinstalar.ps1')) {
    $tk = $null; $er = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $fonte $a), [ref]$tk, [ref]$er)
    if ($er.Count -gt 0) { Falhar ($a + ' tem erro de sintaxe: ' + $er[0].Message + ' (linha ' + $er[0].Extent.StartLineNumber + ')') }
}
$bytes = [IO.File]::ReadAllBytes($arqFonte)
$texto = [Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)
$m = [regex]::Match($texto, "\`$VersaoApp = '([0-9]+\.[0-9]+\.[0-9]+)'")
if (-not $m.Success) { Falhar 'nao achei a linha $VersaoApp = ''x.y.z'' no Wattcha.ps1' }
$versao = $m.Groups[1].Value
$mp = [regex]::Match($texto, "\`$ChavePublicaAtu = '(<RSAKeyValue>.+?</RSAKeyValue>)'")
if (-not $mp.Success) { Falhar 'nao achei a $ChavePublicaAtu no Wattcha.ps1' }
Write-Host ('Versao ' + $versao)

# ---- 3. sha256 e assinatura ----
if (-not (Test-Path $ChavePrivada)) { Falhar ('chave privada nao encontrada em ' + $ChavePrivada) }
$sha = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace('-', '').ToLower()
$rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
try {
    $rsa.FromXmlString([IO.File]::ReadAllText($ChavePrivada))
    if ($rsa.PublicOnly) { Falhar 'o arquivo indicado tem so a chave publica' }
    $assin = $rsa.SignData($bytes, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
} finally { $rsa.Dispose() }
$assinB64 = [Convert]::ToBase64String($assin)

# confere com a chave publica que esta DENTRO do programa (pega chave trocada por engano)
$pub = New-Object Security.Cryptography.RSACryptoServiceProvider
try {
    $pub.FromXmlString($mp.Groups[1].Value)
    $ok = $pub.VerifyData($bytes, $assin, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
} finally { $pub.Dispose() }
if (-not $ok) { Falhar 'a chave privada nao corresponde a chave publica embutida no Wattcha.ps1' }
Write-Host 'Assinatura feita e conferida com a chave publica do programa.'

# ---- 2 e 4. grava Wattcha.ps1 e versao.json ----
[IO.File]::WriteAllBytes((Join-Path $saida 'Wattcha.ps1'), $bytes)
$info = [ordered]@{ versao = $versao; sha256 = $sha; notas = $Notas; assinatura = $assinB64 }
[IO.File]::WriteAllText((Join-Path $saida 'versao.json'), ($info | ConvertTo-Json -Compress), $utf8SemBom)
Write-Host ('Gravados wattcha\Wattcha.ps1 e wattcha\versao.json (sha256 ' + $sha + ')')

# ---- 5. instalador ----
if ($SemInstalador) { Write-Host 'Instalador NAO refeito (-SemInstalador).'; exit 0 }
$iexpress = Join-Path $env:SystemRoot 'System32\iexpress.exe'
if (-not (Test-Path $iexpress)) { Write-Host 'iexpress nao encontrado: instalador NAO refeito.' -ForegroundColor Yellow; exit 0 }
$build = Join-Path $env:TEMP ('wattcha-build-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -Path $build -ItemType Directory -Force | Out-Null
try {
    foreach ($a in @('Instalar.ps1', 'Wattcha.ps1', 'Abrir-Wattcha.vbs', 'wattcha.ico', 'Desinstalar.ps1')) {
        Copy-Item -Path (Join-Path $fonte $a) -Destination (Join-Path $build $a) -Force
    }
    # o .sed da fonte usa C:\PASTA-DE-BUILD\ como marcador; aqui vira a pasta temporaria (CRLF, como o iexpress exige)
    $linhas = [IO.File]::ReadAllLines((Join-Path $fonte 'wattcha-instalador.sed'))
    $linhas = $linhas | ForEach-Object { $_.Replace('C:\PASTA-DE-BUILD\', $build + '\') }
    $sed = Join-Path $build 'wattcha-instalador.sed'
    [IO.File]::WriteAllText($sed, (($linhas -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
    $exe = Join-Path $build 'Wattcha-Instalador.exe'
    # o iexpress falha (codigo 1) se o .sed vier com caminho entre aspas: passa so o nome, rodando dentro da pasta
    $p = Start-Process -FilePath $iexpress -ArgumentList '/N /Q wattcha-instalador.sed' -WorkingDirectory $build -Wait -PassThru
    if (-not (Test-Path $exe)) { Falhar ('o iexpress nao gerou o instalador (codigo ' + $p.ExitCode + ')') }
    Copy-Item -Path $exe -Destination (Join-Path $saida 'Wattcha-Instalador.exe') -Force
    Write-Host ('Instalador refeito: wattcha\Wattcha-Instalador.exe (' + (Get-Item $exe).Length + ' bytes)')
} finally {
    Remove-Item -Path $build -Recurse -Force -ErrorAction SilentlyContinue
}
