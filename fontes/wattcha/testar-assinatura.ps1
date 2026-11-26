# ============================================================
#  Teste da conferencia de atualizacoes do Wattcha (assinatura RSA).
#  Usa as funcoes de verdade do fontes\wattcha\Wattcha.ps1 (AssinaturaValida e
#  ConferirAtualizacao) e o que esta publicado em wattcha\ (Wattcha.ps1 + versao.json).
#  Nao precisa da chave privada. Rode:
#   powershell -NoProfile -ExecutionPolicy Bypass -File testar-assinatura.ps1
# ============================================================
$ErrorActionPreference = 'Stop'
$fonte = $PSScriptRoot
$raiz = Split-Path (Split-Path $fonte -Parent) -Parent
$arqApp = Join-Path $fonte 'Wattcha.ps1'

# ---- pega do programa so a chave publica e as 2 funcoes de conferencia ----
$tk = $null; $er = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($arqApp, [ref]$tk, [ref]$er)
if ($er.Count -gt 0) { Write-Host 'Wattcha.ps1 com erro de sintaxe' -ForegroundColor Red; exit 1 }
$chave = $ast.Find({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$ChavePublicaAtu' }, $true)
$script:ChavePublicaAtu = $chave.Right.Extent.Text.Trim("'")
foreach ($nome in @('AssinaturaValida', 'ConferirAtualizacao')) {
    $fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $nome }, $true)
    if (-not $fn) { Write-Host ('funcao ' + $nome + ' nao encontrada') -ForegroundColor Red; exit 1 }
    . ([scriptblock]::Create($fn.Extent.Text))
}

$falhas = 0
function Conferir($titulo, $esperado, $obtido) {
    if ($obtido -eq $esperado) { Write-Host ('PASSOU  ' + $titulo + '  -> "' + $obtido + '"') -ForegroundColor Green }
    else { Write-Host ('FALHOU  ' + $titulo + '  esperado "' + $esperado + '", veio "' + $obtido + '"') -ForegroundColor Red; $script:falhas++ }
}
function Sha($b) { return [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([byte[]]$b)).Replace('-', '').ToLower() }

$bytes = [IO.File]::ReadAllBytes((Join-Path $raiz 'wattcha\Wattcha.ps1'))
$json = [IO.File]::ReadAllText((Join-Path $raiz 'wattcha\versao.json'))
$info = $json | ConvertFrom-Json

# 1) o que esta publicado: precisa ser aceito
Conferir 'assinatura valida (publicado em wattcha\)' '' (ConferirAtualizacao $bytes $info)

# 2) arquivo alterado (1 caractere a mais), com o sha256 ajustado para "bater": a assinatura tem que barrar
$alterado = [byte[]]($bytes + [Text.Encoding]::ASCII.GetBytes("`r`n# alterado`r`n"))
$infoAlt = $json | ConvertFrom-Json; $infoAlt.sha256 = Sha $alterado
Conferir 'arquivo alterado (sha256 ajustado)' 'assinatura invalida para a chave do programa' (ConferirAtualizacao $alterado $infoAlt)

# 2b) arquivo alterado sem ajustar o sha256
Conferir 'arquivo alterado (sha256 antigo)' 'sha256 diferente do versao.json' (ConferirAtualizacao $alterado $info)

# 3) versao.json sem o campo assinatura (como era ate a 1.0.3)
$infoSem = $json | ConvertFrom-Json; $infoSem.PSObject.Properties.Remove('assinatura')
Conferir 'assinatura ausente' 'versao.json sem assinatura' (ConferirAtualizacao $bytes $infoSem)

# 4) assinatura que nao e base64
$infoLixo = $json | ConvertFrom-Json; $infoLixo.assinatura = 'isto nao e base64!!'
Conferir 'assinatura com lixo' 'assinatura invalida para a chave do programa' (ConferirAtualizacao $bytes $infoLixo)

# 5) assinada por OUTRA chave (alguem que nao tem a nossa chave privada)
$outra = New-Object Security.Cryptography.RSACryptoServiceProvider(3072)
$infoOutra = $json | ConvertFrom-Json
$infoOutra.assinatura = [Convert]::ToBase64String($outra.SignData($bytes, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1))
$outra.Dispose()
Conferir 'assinada por outra chave' 'assinatura invalida para a chave do programa' (ConferirAtualizacao $bytes $infoOutra)

# 6) o publicado e igual a fonte (byte a byte)
Conferir 'wattcha\Wattcha.ps1 igual a fonte' (Sha ([IO.File]::ReadAllBytes($arqApp))) (Sha $bytes)

# 7) campos antigos continuam no versao.json (apps 1.0.2/1.0.3 precisam deles)
Conferir 'versao.json tem versao, sha256 e notas' 'True' ('' + [bool]($info.versao -and $info.sha256 -and $info.notas))

Write-Host ''
if ($falhas -gt 0) { Write-Host ($falhas.ToString() + ' teste(s) falharam.') -ForegroundColor Red; exit 1 }
Write-Host 'Todos os testes passaram.' -ForegroundColor Green
exit 0
