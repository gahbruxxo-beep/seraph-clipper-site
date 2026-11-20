# ============================================================
#  WATTCHA  -  energia + desempenho do PC  (programa com janela)
#  Aba 1: mede o PC todo em tempo real (kWh e R$).  E uma ESTIMATIVA.
#  Aba 2: modos de desempenho (Equilibrado / Alto desempenho / Gaming).
#  Aba 3: limpeza de lixo (moderada ou agressiva).
#  Aba 4: hibernacao (ligar, agendar horario ou desligar).
#  Aba 5: ajustes (abrir com o Windows, ficar perto do relogio).
#  O medidor tem 2 telas: AO VIVO e HISTORICO (por dia).
# ============================================================
param([switch]$Segundo, [switch]$AguardarFechar, [switch]$Medir)
$ErrorActionPreference = 'SilentlyContinue'
$VersaoApp = '1.0.3'
$UrlsBase = @('https://visusclipper.online/wattcha/', 'https://gahbruxxo-beep.github.io/seraph-clipper-site/wattcha/')
$script:idxBase = 0
$script:baseOk = $null
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$inv = [Globalization.CultureInfo]::InvariantCulture

# ---- Padroes (conta de luz: R$ 202 / 186 kWh = R$ 1,086 por kWh) ----
$TarifaPadrao = '1,086'
$HorasPadrao  = '24'

# ---- so uma copia do programa por vez ----
$script:mutex = $null; $evAbrir = $null
$temOutra = $false
try {
    $script:mutex = New-Object Threading.Mutex($false, 'Local\Wattcha')
    $espera = 0; if ($AguardarFechar) { $espera = 15000 }
    $ok = $false
    try { $ok = $script:mutex.WaitOne($espera) } catch [Threading.AbandonedMutexException] { $ok = $true }
    if (-not $ok) { $temOutra = $true }
} catch { $temOutra = $true }
try { $evAbrir = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::AutoReset, 'Local\Wattcha-Abrir') } catch {}
if ($temOutra) {
    $enviado = $false
    try { if ($evAbrir) { [void]$evAbrir.Set(); $enviado = $true } } catch {}
    if (-not $enviado) { [void][Windows.Forms.MessageBox]::Show('O programa ja esta aberto: clique no icone perto do relogio.', 'Wattcha') }
    exit
}

# ---- configuracao e historico guardados em %LOCALAPPDATA%\Wattcha ----
$pastaDados = Join-Path $env:LOCALAPPDATA 'Wattcha'
$pastaAntiga = Join-Path $env:LOCALAPPDATA 'MedidorEnergia'
if (-not (Test-Path $pastaDados) -and (Test-Path $pastaAntiga)) { try { Copy-Item -Path $pastaAntiga -Destination $pastaDados -Recurse -Force } catch {} }
if (-not (Test-Path $pastaDados)) { New-Item -Path $pastaDados -ItemType Directory -Force | Out-Null }
$arqCfg = Join-Path $pastaDados 'config.json'
$arqHist = Join-Path $pastaDados 'historico.csv'
$cfg = [pscustomobject]@{ Tarifa = $TarifaPadrao; Horas = $HorasPadrao; Monitor = '0'; Bandeja = $true; AutoAtualizar = $true; UltimaChecagem = '' }
if (Test-Path $arqCfg) {
    try {
        $j = Get-Content -Path $arqCfg -Raw | ConvertFrom-Json
        foreach ($k in @('Tarifa', 'Horas', 'Monitor', 'Bandeja', 'AutoAtualizar', 'UltimaChecagem')) { if ($j.$k -ne $null) { $cfg.$k = $j.$k } }
    } catch {}
}
function SalvarCfg {
    try {
        $script:cfg.Tarifa = '' + $script:tTarifa.Text
        $script:cfg.Horas = '' + $script:tHoras.Text
        $script:cfg.Monitor = '' + $script:tMonitor.Text
        $script:cfg | ConvertTo-Json | Set-Content -Path $script:arqCfg -Encoding UTF8
    } catch {}
}

# ---------------- Descobre o hardware ----------------
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$cpuNome = ('' + $cpu.Name).Trim()
$nucleos = [int]$cpu.NumberOfCores
if ($nucleos -lt 1) { $nucleos = 4 }
$notebook = [bool](Get-CimInstance Win32_Battery)

$tdp = 0
if     ($cpuNome -match 'Core.*i9')            { $tdp = 125 }
elseif ($cpuNome -match 'Core.*i7')            { $tdp = 95 }
elseif ($cpuNome -match 'Core.*i5')            { $tdp = 65 }
elseif ($cpuNome -match 'Core.*i3')            { $tdp = 60 }
elseif ($cpuNome -match 'Ryzen 9')             { $tdp = 105 }
elseif ($cpuNome -match 'Ryzen 7')             { $tdp = 85 }
elseif ($cpuNome -match 'Ryzen 5')             { $tdp = 65 }
elseif ($cpuNome -match 'Ryzen 3')             { $tdp = 65 }
elseif ($cpuNome -match 'Xeon')                { $tdp = 120 }
elseif ($cpuNome -match 'Celeron|Pentium|Athlon') { $tdp = 45 }
else                                           { $tdp = 10 + 8 * $nucleos }
if ($cpuNome -match '\d{4,5}(U|Y)\b|Ryzen.*\dU\b') { $tdp = 15 }
elseif ($cpuNome -match '\d{4,5}(H|HQ|HK|HX)\b|Ryzen.*\d(H|HS|HX)\b') { $tdp = 45 }
if ($notebook -and $tdp -gt 45) { $tdp = 45 }
$cpuOcioso = [math]::Max(5, $tdp * 0.10)

$gpuNome = ''
$placas = @(Get-CimInstance Win32_VideoController)
foreach ($p in $placas) { if ($p.Name -match 'NVIDIA|GeForce|Radeon RX|Radeon Pro|Arc ') { $gpuNome = $p.Name } }
$gpuDedicada = ($gpuNome -ne '')
if (-not $gpuDedicada -and $placas.Count -gt 0) { $gpuNome = ('' + $placas[0].Name) }
$gpuMax = 8; $gpuOciosa = 3
if ($gpuDedicada) {
    $gpuMax = 120; $gpuOciosa = 12
    if ($gpuNome -match '4090|3090|7900')             { $gpuMax = 350; $gpuOciosa = 20 }
    elseif ($gpuNome -match '4080|3080|7800|6800')    { $gpuMax = 250; $gpuOciosa = 18 }
    elseif ($gpuNome -match '4070|3070|3060|7700|6700|2080|2070') { $gpuMax = 170; $gpuOciosa = 14 }
    elseif ($gpuNome -match '1050|1650|1630|6500|6400|3050|GT ') { $gpuMax = 75; $gpuOciosa = 8 }
    elseif ($gpuNome -match '1060|1660|2060|4060|6600|1070') { $gpuMax = 130; $gpuOciosa = 10 }
}
$smi = $null
foreach ($c in @('nvidia-smi.exe', "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe", "$env:SystemRoot\System32\nvidia-smi.exe")) {
    $g = Get-Command $c -ErrorAction SilentlyContinue
    if ($g) { $smi = $g.Source; break }
}

$pentes = @(Get-CimInstance Win32_PhysicalMemory)
$ramW = 3.0 * [math]::Max(1, $pentes.Count)
if ($notebook) { $ramW = 2.0 * [math]::Max(1, $pentes.Count) }

$discosW = 0.0; $discosTxt = @()
$fis = @(Get-PhysicalDisk)
if ($fis.Count -eq 0) { $discosW = 4.0; $discosTxt += 'disco' }
foreach ($d in $fis) {
    if ($d.BusType -eq 'NVMe')       { $discosW += 3.5; $discosTxt += 'NVMe' }
    elseif ($d.MediaType -eq 'HDD')  { $discosW += 6.5; $discosTxt += 'HD' }
    elseif ($d.MediaType -eq 'SSD')  { $discosW += 2.5; $discosTxt += 'SSD' }
    else                             { $discosW += 4.0; $discosTxt += 'disco' }
}
$baseW = 25.0; $eficiencia = 0.87
if ($notebook) { $baseW = 8.0; $eficiencia = 0.88 }

# ---------------- Uma medicao ----------------
function Medir($monitorW) {
    $carga = $null
    $pi = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'"
    if ($pi) { $carga = [double]$pi.PercentProcessorUtility }
    if ($carga -eq $null -or $carga -le 0) {
        $po = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'"
        if ($po) { $carga = [double]$po.PercentProcessorTime }
    }
    if ($carga -eq $null) { $carga = 20 }
    if ($carga -gt 100) { $carga = 100 }
    $cpuW = $script:cpuOciosa + ($script:tdp - $script:cpuOciosa) * ($carga / 100.0)

    $gpuW = $null; $fonte = 'estimado'
    if ($script:smi) {
        $txt = & $script:smi --query-gpu=power.draw --format=csv,noheader,nounits 2>$null
        $v = 0.0
        $linha = ('' + ($txt | Select-Object -First 1)).Trim() -replace ',', '.'
        if ([double]::TryParse($linha, [Globalization.NumberStyles]::Float, $script:inv, [ref]$v)) { $gpuW = $v; $fonte = 'medido' }
    }
    if ($gpuW -eq $null) {
        $uso = 0.0
        $eng = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine
        if ($eng) { foreach ($e in $eng) { if ($e.Name -match 'engtype_(3D|Compute|VideoDecode|VideoEncode)') { $uso += [double]$e.UtilizationPercentage } } }
        if ($uso -gt 100) { $uso = 100 }
        $gpuW = $script:gpuOciosa + ($script:gpuMax - $script:gpuOciosa) * ($uso / 100.0)
    }
    $interno = $cpuW + $gpuW + $script:ramW + $script:discosW + $script:baseW
    return [pscustomobject]@{ Parede = ($interno / $script:eficiencia) + $monitorW; Carga = $carga; CpuW = $cpuW; GpuW = $gpuW; Fonte = $fonte }
}

function Numero($texto, $padrao) {
    $t = ('' + $texto) -replace 'R\$', '' -replace ',', '.'
    $v = 0.0
    if ([double]::TryParse($t.Trim(), [Globalization.NumberStyles]::Float, $script:inv, [ref]$v) -and $v -ge 0) { return $v }
    return $padrao
}
function Reais($v) { return 'R$ ' + ('{0:N2}' -f $v) }

# ---------------- Janela ----------------
$fundo = [Drawing.Color]::FromArgb(24, 18, 46)
$painel = [Drawing.Color]::FromArgb(40, 32, 74)
$amarelo = [Drawing.Color]::FromArgb(255, 193, 69)
$verde = [Drawing.Color]::FromArgb(110, 231, 140)
$rosa = [Drawing.Color]::FromArgb(255, 107, 129)
$claro = [Drawing.Color]::FromArgb(230, 226, 245)
$suave = [Drawing.Color]::FromArgb(160, 152, 190)
$escuro = [Drawing.Color]::FromArgb(24, 18, 46)

$f = New-Object Windows.Forms.Form
$f.Text = 'Wattcha - energia e desempenho do PC'
$f.ClientSize = New-Object Drawing.Size(540, 680)
$f.StartPosition = 'CenterScreen'
$f.FormBorderStyle = 'FixedSingle'; $f.MaximizeBox = $false
$f.BackColor = $fundo; $f.ForeColor = $claro
$f.Font = New-Object Drawing.Font('Segoe UI', 10)

$script:pai = $f
function Rotulo($texto, $x, $y, $w, $h, $tam, $cor, $negrito) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $texto; $l.Location = New-Object Drawing.Point($x, $y); $l.Size = New-Object Drawing.Size($w, $h)
    $estilo = [Drawing.FontStyle]::Regular; if ($negrito) { $estilo = [Drawing.FontStyle]::Bold }
    $l.Font = New-Object Drawing.Font('Segoe UI', $tam, $estilo); $l.ForeColor = $cor; $l.BackColor = [Drawing.Color]::Transparent
    $script:pai.Controls.Add($l); return $l
}
function Caixa($texto, $x, $y, $w) {
    $t = New-Object Windows.Forms.TextBox
    $t.Text = $texto; $t.Location = New-Object Drawing.Point($x, $y); $t.Size = New-Object Drawing.Size($w, 28)
    $t.BackColor = $painel; $t.ForeColor = [Drawing.Color]::White; $t.BorderStyle = 'FixedSingle'
    $t.Font = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold)
    $script:pai.Controls.Add($t); return $t
}
function Botao($texto, $x, $y, $w, $h, $cor, $corTexto, $tam) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $texto; $b.Location = New-Object Drawing.Point($x, $y); $b.Size = New-Object Drawing.Size($w, $h)
    $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $cor; $b.ForeColor = $corTexto
    $b.Font = New-Object Drawing.Font('Segoe UI', $tam, [Drawing.FontStyle]::Bold); $b.Cursor = 'Hand'
    $script:pai.Controls.Add($b); return $b
}

$souAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

[void](Rotulo 'WATTCHA' 20 8 500 34 17 $amarelo $true)
[void](Rotulo 'Vigie quanto o PC gasta, deixe ele mais rapido e limpe o lixo' 20 40 500 20 9.5 $suave $false)

# ---- aviso de administrador ----
if ($souAdmin) {
    [void](Rotulo 'Rodando como administrador: todas as funcoes liberadas.' 20 66 500 22 9 $verde $true)
} else {
    $lAdm = Rotulo 'Abra como administrador (botao direito > Executar como administrador) para liberar a limpeza completa e a hibernacao.' 20 62 360 34 8.5 $amarelo $true
    $bAdm = Botao 'REABRIR COMO ADMINISTRADOR' 388 64 132 30 $amarelo $escuro 7.5
    $bAdm.Add_Click({
        try {
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $PSCommandPath + '" -AguardarFechar') -ErrorAction Stop
            $script:sair = $true
            $f.Close()
        } catch {}
    })
}

# ---- abas ----
$abaBtn = @()
$abaBtn += Botao 'MEDIDOR' 20 100 96 32 $amarelo $escuro 8
$abaBtn += Botao 'DESEMPENHO' 121 100 96 32 $painel $claro 8
$abaBtn += Botao 'LIMPEZA' 222 100 96 32 $painel $claro 8
$abaBtn += Botao 'HIBERNAR' 323 100 96 32 $painel $claro 8
$abaBtn += Botao 'AJUSTES' 424 100 96 32 $painel $claro 8

$paginas = @()
for ($i = 0; $i -lt 5; $i++) {
    $pn = New-Object Windows.Forms.Panel
    $pn.Location = New-Object Drawing.Point(0, 140); $pn.Size = New-Object Drawing.Size(540, 540)
    $pn.BackColor = $fundo; $pn.AutoScroll = $false
    $f.Controls.Add($pn); $paginas += $pn
}
function MostrarAba($n) {
    for ($i = 0; $i -lt 5; $i++) {
        $script:paginas[$i].Visible = ($i -eq $n)
        if ($i -eq $n) { $script:abaBtn[$i].BackColor = $script:amarelo; $script:abaBtn[$i].ForeColor = $script:escuro }
        else { $script:abaBtn[$i].BackColor = $script:painel; $script:abaBtn[$i].ForeColor = $script:claro }
    }
}
for ($i = 0; $i -lt 5; $i++) {
    $abaBtn[$i].Tag = $i
    $abaBtn[$i].Add_Click({ param($quem, $ev) MostrarAba ([int]$quem.Tag) })
}

# =====================================================================
#  ABA 1 - MEDIDOR
# =====================================================================
$p1 = $paginas[0]
$script:pai = $p1
$bVivo = Botao 'AO VIVO' 20 0 245 28 $amarelo $escuro 9.5
$bHist = Botao 'HISTORICO (dia a dia)' 275 0 245 28 $painel $claro 9.5
$pLive = New-Object Windows.Forms.Panel
$pLive.Location = New-Object Drawing.Point(0, 32); $pLive.Size = New-Object Drawing.Size(540, 508); $pLive.BackColor = $fundo
$pHist = New-Object Windows.Forms.Panel
$pHist.Location = New-Object Drawing.Point(0, 32); $pHist.Size = New-Object Drawing.Size(540, 508); $pHist.BackColor = $fundo; $pHist.Visible = $false
$p1.Controls.Add($pLive); $p1.Controls.Add($pHist)

# ----- AO VIVO -----
$script:pai = $pLive
[void](Rotulo 'Preco do kWh (R$)' 20 4 160 20 9 $suave $false)
[void](Rotulo 'Horas ligado por dia' 190 4 160 20 9 $suave $false)
[void](Rotulo 'Monitor (watts)' 360 4 140 20 9 $suave $false)
$tTarifa = Caixa $cfg.Tarifa 20 26 150
$tHoras = Caixa $cfg.Horas 190 26 150
$tMonitor = Caixa $cfg.Monitor 360 26 150
$tTarifa.Add_Leave({ SalvarCfg }); $tHoras.Add_Leave({ SalvarCfg }); $tMonitor.Add_Leave({ SalvarCfg })

$btn = Botao 'INICIAR' 20 62 500 44 $amarelo $escuro 14

$box = New-Object Windows.Forms.Panel
$box.Location = New-Object Drawing.Point(20, 116); $box.Size = New-Object Drawing.Size(500, 312); $box.BackColor = $painel
$pLive.Controls.Add($box)
$script:pai = $box
[void](Rotulo 'GASTO ESTIMADO POR MES' 16 10 468 20 9 $suave $true)
$lMes = Rotulo 'R$ --' 16 28 468 64 36 $verde $true
$lKwhMes = Rotulo '-- kWh por mes' 16 94 468 24 12 $claro $false
[void](Rotulo 'AGORA' 16 130 150 18 8.5 $suave $true)
[void](Rotulo 'MEDIA' 176 130 150 18 8.5 $suave $true)
[void](Rotulo 'POR DIA' 336 130 150 18 8.5 $suave $true)
$lAgora = Rotulo '-- W' 16 148 155 34 18 $claro $true
$lMedia = Rotulo '-- W' 176 148 155 34 18 $claro $true
$lDia = Rotulo 'R$ --' 336 148 155 34 18 $claro $true
[void](Rotulo 'CONSUMO DESDE QUE INICIOU' 16 196 230 18 8.5 $suave $true)
[void](Rotulo 'CUSTO DESDE QUE INICIOU' 260 196 230 18 8.5 $suave $true)
$lKwhAc = Rotulo '0,000 kWh' 16 214 240 34 18 $claro $true
$lCustoAc = Rotulo 'R$ 0,00' 260 214 230 34 18 $claro $true
$lDetalhe = Rotulo 'Clique em INICIAR.' 16 260 468 44 9 $suave $false

$script:pai = $pLive
[void](Rotulo ('Este PC -> Processador: ' + $cpuNome + '   |   Video: ' + $gpuNome) 20 434 500 30 8.5 $suave $false)
[void](Rotulo 'Estimativa feita com as pecas DESTE computador. Troque o preco do kWh pelo da sua conta de luz: valor total da conta dividido pelos kWh consumidos.' 20 466 500 34 8 $suave $false)

# ----- HISTORICO -----
$script:pai = $pHist
$sumBox = New-Object Windows.Forms.Panel
$sumBox.Location = New-Object Drawing.Point(20, 0); $sumBox.Size = New-Object Drawing.Size(500, 92); $sumBox.BackColor = $painel
$pHist.Controls.Add($sumBox)
$script:pai = $sumBox
[void](Rotulo 'MEDIA DE CONSUMO POR DIA' 16 8 468 18 8.5 $suave $true)
$lHistMedia = Rotulo 'sem dados ainda' 16 26 468 34 18 $verde $true
$lHistTotal = Rotulo '' 16 64 468 22 9 $suave $false
$script:pai = $pHist
$lv = New-Object Windows.Forms.ListView
$lv.Location = New-Object Drawing.Point(20, 100); $lv.Size = New-Object Drawing.Size(500, 322)
$lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.HideSelection = $false; $lv.BorderStyle = 'None'
$lv.BackColor = $painel; $lv.ForeColor = $claro; $lv.Font = New-Object Drawing.Font('Segoe UI', 9.5)
$lv.HeaderStyle = 'Nonclickable'
[void]$lv.Columns.Add('Data', 128)
[void]$lv.Columns.Add('Tempo ligado', 92)
[void]$lv.Columns.Add('Consumo', 82)
[void]$lv.Columns.Add('Media', 66)
[void]$lv.Columns.Add('Gasto no dia', 112)
$pHist.Controls.Add($lv)
$bApagaHist = Botao 'APAGAR HISTORICO' 20 430 200 30 $painel $claro 8.5
$lHistNota = Rotulo 'Tempo ligado = tempo em que o programa ficou medindo (nao conta o PC hibernado ou desligado). Para o historico ficar completo, deixe abrir junto com o Windows (aba AJUSTES).' 20 466 500 38 8 $suave $false

function MostrarSub($qual) {
    if ($qual -eq 'hist') {
        $script:pLive.Visible = $false; $script:pHist.Visible = $true
        $script:bHist.BackColor = $script:amarelo; $script:bHist.ForeColor = $script:escuro
        $script:bVivo.BackColor = $script:painel; $script:bVivo.ForeColor = $script:claro
        AtualizarHistorico
    } else {
        $script:pHist.Visible = $false; $script:pLive.Visible = $true
        $script:bVivo.BackColor = $script:amarelo; $script:bVivo.ForeColor = $script:escuro
        $script:bHist.BackColor = $script:painel; $script:bHist.ForeColor = $script:claro
    }
}
$bVivo.Add_Click({ MostrarSub 'vivo' })
$bHist.Add_Click({ MostrarSub 'hist' })

# =====================================================================
#  ABA 2 - DESEMPENHO
# =====================================================================
$p2 = $paginas[1]
$script:pai = $p2

function PlanoAtivo {
    $t = (& powercfg /getactivescheme) -join ' '
    $g = ''; $nome = ''
    if ($t -match '([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') { $g = $Matches[1] }
    if ($t -match '\(([^)]+)\)') { $nome = $Matches[1] }
    return [pscustomobject]@{ Guid = $g; Nome = $nome }
}
$pastaCfg = $pastaDados
$arqAntes = Join-Path $pastaCfg 'antes.xml'
$RegItens = @(
    @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; N = 'EnableTransparency' },
    @{ P = 'HKCU:\Software\Microsoft\GameBar'; N = 'AutoGameModeEnabled' },
    @{ P = 'HKCU:\Software\Microsoft\GameBar'; N = 'AllowAutoGameMode' },
    @{ P = 'HKCU:\System\GameConfigStore'; N = 'GameDVR_Enabled' },
    @{ P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; N = 'AppCaptureEnabled' }
)
function DefReg($p, $n, $v) {
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    New-ItemProperty -Path $p -Name $n -Value $v -PropertyType DWord -Force | Out-Null
}
function GuardarEstadoOriginal {
    if (Test-Path $arqAntes) { return }   # guarda so a primeira vez: e o "como estava"
    if (-not (Test-Path $pastaCfg)) { New-Item -Path $pastaCfg -ItemType Directory -Force | Out-Null }
    $regs = @()
    foreach ($r in $script:RegItens) {
        $v = $null; $existe = $false
        $pp = Get-ItemProperty -Path $r.P -Name $r.N -ErrorAction SilentlyContinue
        if ($pp -ne $null -and ($pp.PSObject.Properties.Name -contains $r.N)) { $v = $pp.($r.N); $existe = $true }
        $regs += [pscustomobject]@{ P = $r.P; N = $r.N; V = $v; Existe = $existe }
    }
    $pl = PlanoAtivo
    [pscustomobject]@{ Plano = $pl.Guid; Regs = $regs } | Export-Clixml -Path $arqAntes
}
function AtivarPlano($apelido, $guidBase) {
    & powercfg /setactive $apelido 2>$null
    if ($LASTEXITCODE -ne 0) {
        $saida = (& powercfg -duplicatescheme $guidBase 2>$null) -join ' '
        if ($saida -match '([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') { & powercfg /setactive $Matches[1] 2>$null }
    }
}
function AtivarMaximo {
    $lista = (& powercfg /list) -join "`n"
    $achou = $null
    foreach ($linha in ($lista -split "`n")) {
        if ($linha -match 'Ultimate|Desempenho M') { if ($linha -match '([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') { $achou = $Matches[1]; break } }
    }
    if (-not $achou) {
        $saida = (& powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null) -join ' '
        if ($saida -match '([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') { $achou = $Matches[1] }
    }
    if ($achou) { & powercfg /setactive $achou 2>$null; return $true }
    AtivarPlano 'SCHEME_MIN' '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    return $false
}
function AtualizarModoAtual {
    $pl = PlanoAtivo
    $script:lModoAtual.Text = 'Plano de energia agora: ' + $pl.Nome
}
function AplicarModo($modo) {
    GuardarEstadoOriginal
    $extra = ''
    if ($modo -eq 'equilibrado') {
        AtivarPlano 'SCHEME_BALANCED' '381b4222-f694-41f0-9685-ff5bb260df2e'
        DefReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 1
        $nomeModo = 'EQUILIBRADO'
    }
    elseif ($modo -eq 'alto') {
        AtivarPlano 'SCHEME_MIN' '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        & powercfg /change disk-timeout-ac 0 2>$null
        $nomeModo = 'ALTO DESEMPENHO'
    }
    else {
        $ok = AtivarMaximo
        if (-not $ok) { $extra = ' (Desempenho Maximo indisponivel: usei Alto desempenho)' }
        & powercfg /change disk-timeout-ac 0 2>$null
        DefReg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
        DefReg 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1
        DefReg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
        DefReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
        DefReg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
        $nomeModo = 'GAMING'
    }
    AtualizarModoAtual
    $script:lResultadoPerf.Text = 'Pronto! Modo ' + $nomeModo + ' aplicado.' + $extra
}
function RestaurarModo {
    if (-not (Test-Path $arqAntes)) { $script:lResultadoPerf.Text = 'Nada para restaurar: voce ainda nao aplicou nenhum modo.'; return }
    $a = Import-Clixml -Path $arqAntes
    if ($a.Plano) { & powercfg /setactive $a.Plano 2>$null }
    foreach ($r in $a.Regs) {
        if ($r.Existe) { DefReg $r.P $r.N ([int]$r.V) }
        else { Remove-ItemProperty -Path $r.P -Name $r.N -ErrorAction SilentlyContinue }
    }
    Remove-Item -Path $arqAntes -Force -ErrorAction SilentlyContinue
    AtualizarModoAtual
    $script:lResultadoPerf.Text = 'Pronto! O PC voltou para o jeito que estava antes.'
}

[void](Rotulo 'Escolha o modo. Um clique e o PC fica pronto.' 20 4 500 22 10.5 $claro $true)
$lModoAtual = Rotulo 'Plano de energia agora: ...' 20 28 500 20 9 $suave $false

function Cartao($y, $titulo, $corTitulo, $energia, $desc, $muda, $modo) {
    $c = New-Object Windows.Forms.Panel
    $c.Location = New-Object Drawing.Point(20, $y); $c.Size = New-Object Drawing.Size(500, 118); $c.BackColor = $script:painel
    $script:p2.Controls.Add($c)
    $script:pai = $c
    [void](Rotulo $titulo 14 8 280 26 13 $corTitulo $true)
    $le = Rotulo $energia 260 12 228 20 8.5 $script:suave $true
    $le.TextAlign = 'MiddleRight'
    [void](Rotulo $desc 14 36 472 22 9.5 $script:claro $false)
    [void](Rotulo $muda 14 58 366 58 8.5 $script:suave $false)
    $b = Botao 'APLICAR' 388 66 98 40 $script:amarelo $script:escuro 10
    $b.Add_Click({ AplicarModo $modo }.GetNewClosure())
    $script:pai = $script:p2
}
Cartao 52 'Equilibrado' $verde 'Gasta pouca energia' 'Dia a dia: acelera quando precisa e economiza quando esta parado.' ("O que muda:`r`n- Plano de energia: Equilibrado`r`n- Transparencias do Windows ligadas") 'equilibrado'
Cartao 176 'Alto desempenho' $amarelo 'Gasta mais energia' 'Trabalho pesado: abrir e editar rapido, o processador fica sempre pronto.' ("O que muda:`r`n- Plano de energia: Alto desempenho`r`n- O disco nunca fica em repouso") 'alto'
Cartao 300 'Gaming' $rosa 'Gasta o maximo de energia' 'Para jogar (ex.: AION2): tira peso do Windows e libera o PC para o jogo.' ("O que muda:`r`n- Plano Desempenho Maximo + Modo Jogo ligado`r`n- Gravacao de tela do Xbox/Game Bar desligada`r`n- Transparencias do Windows desligadas") 'gaming'

$bRestaurar = Botao 'VOLTAR COMO ESTAVA ANTES' 20 424 500 38 $painel $claro 10
$bRestaurar.Add_Click({ RestaurarModo })
$lResultadoPerf = Rotulo 'Nenhum modo aplicado ainda.' 20 470 500 24 10 $verde $true
[void](Rotulo 'Nao mexe em programas, arquivos, jogos nem no Docker. Tudo isso volta ao normal no botao acima.' 20 498 500 34 8.5 $suave $false)

# =====================================================================
#  ABA 3 - LIMPEZA
# =====================================================================
$p3 = $paginas[2]
$script:pai = $p3

# Moderada = 1 (so o essencial) | Agressiva = tudo
$limpeza = @(
    @{ Nome = 'Temporarios do seu usuario'; Desc = 'Sobras de programas que ja fecharam. Seguro.'; Pastas = @("$env:TEMP"); Admin = $false; Tipo = 'pastas'; Moderada = $true },
    @{ Nome = 'Temporarios do Windows'; Desc = 'Sobras do sistema. Seguro. (precisa de administrador)'; Pastas = @("$env:SystemRoot\Temp"); Admin = $true; Tipo = 'pastas'; Moderada = $true },
    @{ Nome = 'Cache dos navegadores'; Desc = 'Chrome, Edge, Brave e Firefox. NAO apaga senhas, logins nem historico. Feche-os antes.'; Admin = $false; Tipo = 'pastas'; Moderada = $true;
       Pastas = @("$env:LOCALAPPDATA\Google\Chrome\User Data\*\Cache", "$env:LOCALAPPDATA\Google\Chrome\User Data\*\Code Cache", "$env:LOCALAPPDATA\Google\Chrome\User Data\*\GPUCache",
                  "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Cache", "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Code Cache", "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\GPUCache",
                  "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\*\Cache", "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\*\Code Cache", "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\*\GPUCache",
                  "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2") },
    @{ Nome = 'Downloads do Windows Update'; Desc = 'Arquivos de atualizacao ja usados. (precisa de administrador)'; Pastas = @("$env:SystemRoot\SoftwareDistribution\Download"); Admin = $true; Tipo = 'pastas'; Moderada = $true },
    @{ Nome = 'Relatorios de erro do Windows'; Desc = 'Registros de travamentos antigos. (precisa de administrador)'; Admin = $true; Tipo = 'pastas'; Moderada = $true;
       Pastas = @("$env:ProgramData\Microsoft\Windows\WER\ReportArchive", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue", "$env:LOCALAPPDATA\Microsoft\Windows\WER") },
    @{ Nome = 'Cache de jogos e video (shaders)'; Desc = 'So na AGRESSIVA. Refeito sozinho; o 1o jogo depois pode abrir mais lento.'; Admin = $false; Tipo = 'pastas'; Moderada = $false;
       Pastas = @("$env:LOCALAPPDATA\D3DSCache", "$env:LOCALAPPDATA\NVIDIA\DXCache", "$env:LOCALAPPDATA\NVIDIA\GLCache", "$env:LOCALAPPDATA\AMD\DxCache") },
    @{ Nome = 'Cache de entrega do Windows'; Desc = 'So na AGRESSIVA. Copias de atualizacoes para outros PCs. (administrador)'; Pastas = @("$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"); Admin = $true; Tipo = 'pastas'; Moderada = $false },
    @{ Nome = 'Cache de internet (DNS)'; Desc = 'So na AGRESSIVA. Esquece enderecos de sites guardados; volta sozinho.'; Pastas = @(); Admin = $false; Tipo = 'dns'; Moderada = $false },
    @{ Nome = 'Esvaziar a Lixeira'; Desc = 'ATENCAO: apaga de vez o que esta na lixeira. Sempre desmarcado: marque se quiser.'; Pastas = @(); Admin = $false; Tipo = 'lixeira'; Moderada = $false }
)

function TamTxt($b) {
    if ($b -ge 1GB) { return ('{0:N2} GB' -f ($b / 1GB)) }
    if ($b -ge 1MB) { return ('{0:N0} MB' -f ($b / 1MB)) }
    if ($b -gt 0) { return ('{0:N0} KB' -f ($b / 1KB)) }
    return '0'
}
function PastasReais($padroes) {
    $r = @()
    foreach ($p in $padroes) { $g = Get-Item -Path $p -Force -ErrorAction SilentlyContinue; if ($g) { $r += $g } }
    return $r
}
function TamanhoItem($it) {
    if ($it.Tipo -eq 'lixeira') {
        $t = 0.0
        try { $sh = New-Object -ComObject Shell.Application; foreach ($x in $sh.NameSpace(10).Items()) { $t += [double]$x.Size } } catch {}
        return $t
    }
    if ($it.Tipo -eq 'dns') { return 0 }
    $t = 0.0
    foreach ($d in (PastasReais $it.Pastas)) {
        $m = Get-ChildItem -LiteralPath $d.FullName -Force -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
        if ($m.Sum) { $t += [double]$m.Sum }
    }
    return $t
}
function LimparItem($it) {
    if ($it.Tipo -eq 'dns') { & ipconfig /flushdns | Out-Null; return }
    if ($it.Tipo -eq 'lixeira') { Clear-RecycleBin -Force -ErrorAction SilentlyContinue; return }
    foreach ($d in (PastasReais $it.Pastas)) {
        Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}
function LivreC {
    $d = Get-PSDrive -Name C -ErrorAction SilentlyContinue
    if ($d) { return [double]$d.Free }
    return 0
}

# ---- escolha do tipo de limpeza ----
$bModM = Botao 'MODERADA (recomendada)' 20 0 245 34 $amarelo $escuro 10
$bModA = Botao 'AGRESSIVA' 275 0 245 34 $painel $claro 10
$lLegModo = Rotulo '' 20 38 500 30 8.5 $claro $false

$checks = @(); $lTams = @()
$y = 72
foreach ($it in $limpeza) {
    $cb = New-Object Windows.Forms.CheckBox
    $cb.Text = $it.Nome; $cb.Checked = $it.Moderada
    $cb.Location = New-Object Drawing.Point(20, $y); $cb.Size = New-Object Drawing.Size(360, 21)
    $cb.Font = New-Object Drawing.Font('Segoe UI', 9.5, [Drawing.FontStyle]::Bold); $cb.ForeColor = $claro; $cb.BackColor = [Drawing.Color]::Transparent
    $p3.Controls.Add($cb); $checks += $cb
    $lt = Rotulo '' 390 ($y + 1) 130 20 9.5 $verde $true
    $lt.TextAlign = 'MiddleRight'; $lTams += $lt
    [void](Rotulo $it.Desc 40 ($y + 19) 480 16 8 $suave $false)
    $y += 36
}
$lDisco = Rotulo '' 20 ($y + 2) 500 18 9.5 $claro $false
$bAnalisar = Botao 'ANALISAR' 20 ($y + 24) 170 40 $painel $claro 11
$bLimpar = Botao 'LIMPAR AGORA' 200 ($y + 24) 320 40 $amarelo $escuro 12
$lResLimpa = Rotulo '' 20 ($y + 70) 500 22 10 $verde $true
[void](Rotulo 'Nao mexe em documentos, fotos, musicas, jogos, downloads, senhas nem no Docker.' 20 ($y + 94) 500 18 8.5 $suave $false)

function SelecionarLimpeza($modo) {
    for ($i = 0; $i -lt $script:limpeza.Count; $i++) {
        $it = $script:limpeza[$i]
        if ($it.Tipo -eq 'lixeira') { $script:checks[$i].Checked = $false; continue }
        $script:checks[$i].Checked = ($modo -eq 'agressiva') -or $it.Moderada
    }
    if ($modo -eq 'agressiva') {
        $script:bModA.BackColor = $script:amarelo; $script:bModA.ForeColor = $script:escuro
        $script:bModM.BackColor = $script:painel; $script:bModM.ForeColor = $script:claro
        $script:lLegModo.Text = 'AGRESSIVA: limpa TUDO da lista, inclusive caches que o Windows e os jogos refazem sozinhos (o primeiro uso depois pode ser um pouco mais lento).'
    } else {
        $script:bModM.BackColor = $script:amarelo; $script:bModM.ForeColor = $script:escuro
        $script:bModA.BackColor = $script:painel; $script:bModA.ForeColor = $script:claro
        $script:lLegModo.Text = 'MODERADA: limpa so o essencial e nao mexe nos caches de jogos, de entrega do Windows nem no DNS. Nada que o PC use no dia a dia e afetado.'
    }
}
$bModM.Add_Click({ SelecionarLimpeza 'moderada' })
$bModA.Add_Click({ SelecionarLimpeza 'agressiva' })
SelecionarLimpeza 'moderada'

function Analisar {
    $total = 0.0
    for ($i = 0; $i -lt $script:limpeza.Count; $i++) {
        $it = $script:limpeza[$i]
        $script:lTams[$i].Text = '...'
        [Windows.Forms.Application]::DoEvents()
        if ($it.Tipo -eq 'dns') { $script:lTams[$i].Text = 'rapido'; continue }
        if ($it.Admin -and -not $script:souAdmin) { $script:lTams[$i].Text = 'precisa admin'; $script:lTams[$i].ForeColor = $script:amarelo; continue }
        $b = TamanhoItem $it
        $script:lTams[$i].ForeColor = $script:verde
        $script:lTams[$i].Text = TamTxt $b
        if ($script:checks[$i].Checked) { $total += $b }
    }
    $script:lDisco.Text = ('Da para liberar cerca de ' + (TamTxt $total) + '   |   Livre no C: ' + (TamTxt (LivreC)))
}
$bAnalisar.Add_Click({ $bAnalisar.Enabled = $false; Analisar; $bAnalisar.Enabled = $true })
$bLimpar.Add_Click({
    $bLimpar.Enabled = $false; $bAnalisar.Enabled = $false
    $antes = LivreC
    for ($i = 0; $i -lt $limpeza.Count; $i++) {
        if (-not $checks[$i].Checked) { continue }
        $it = $limpeza[$i]
        if ($it.Admin -and -not $souAdmin) { continue }
        $lResLimpa.Text = 'Limpando: ' + $it.Nome + '...'
        [Windows.Forms.Application]::DoEvents()
        LimparItem $it
    }
    $depois = LivreC
    $lib = $depois - $antes; if ($lib -lt 0) { $lib = 0 }
    $lResLimpa.Text = 'Pronto! Liberado: ' + (TamTxt $lib) + '.  Livre no C: ' + (TamTxt $depois)
    $lDisco.Text = ''
    for ($i = 0; $i -lt $lTams.Count; $i++) { $lTams[$i].Text = '' }
    $bLimpar.Enabled = $true; $bAnalisar.Enabled = $true
})

# =====================================================================
#  ABA 4 - HIBERNAR
# =====================================================================
$p4 = $paginas[3]
$script:pai = $p4

function HibLigada {
    $v = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name HibernateEnabled -ErrorAction SilentlyContinue).HibernateEnabled
    return ($v -eq 1)
}
function TextoHorarios {
    $txt = ''
    foreach ($t in @(Get-ScheduledTask -TaskName 'Wattcha-*' -ErrorAction SilentlyContinue)) {
        $hh = ''
        $sb = $null; if ($t.Triggers -and $t.Triggers.Count -gt 0) { $sb = $t.Triggers[0].StartBoundary }
        if ($sb) { try { $hh = ([datetime]$sb).ToString('HH:mm') } catch {} }
        $quem = 'hibernar'; if ($t.TaskName -like '*Acordar*') { $quem = 'religar sozinho' }
        $txt += ('  ' + $quem + ' todo dia as ' + $hh + "`r`n")
    }
    if ($txt -eq '') { return 'Horarios agendados por este programa: nenhum.' }
    return ('Horarios agendados por este programa:' + "`r`n" + $txt)
}
function AtualizarHib {
    if (HibLigada) { $script:lHibStatus.Text = 'Hibernacao agora: LIGADA'; $script:lHibStatus.ForeColor = $script:verde }
    else { $script:lHibStatus.Text = 'Hibernacao agora: DESLIGADA'; $script:lHibStatus.ForeColor = $script:amarelo }
    $script:lHorarios.Text = TextoHorarios
}
function ExigeAdmin {
    if ($script:souAdmin) { return $true }
    $script:lHibRes.ForeColor = $script:amarelo
    $script:lHibRes.Text = 'Precisa do administrador: use o botao amarelo no topo da janela.'
    return $false
}
function RemoverTarefas {
    foreach ($t in @(Get-ScheduledTask -TaskName 'Wattcha-*' -ErrorAction SilentlyContinue)) {
        Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
}
function HoraValida($t) {
    $t = ('' + $t).Trim()
    if ($t -match '^([01]?\d|2[0-3])[:h]([0-5]\d)$') {
        $hh = [int]$Matches[1]
        $mm = $Matches[2]
        return ('{0:00}:{1}' -f $hh, $mm)
    }
    return $null
}

[void](Rotulo 'HIBERNAR: o PC se desliga guardando tudo e volta igualzinho ao ligar.' 20 0 500 22 10 $claro $true)
$lHibStatus = Rotulo 'Hibernacao agora: ...' 20 24 500 22 11 $verde $true
[void](Rotulo 'Hibernar salva tudo o que esta aberto e desliga o PC, gastando quase zero de energia. Ao ligar, ele volta exatamente como estava. Gasta bem menos que deixar ligado a noite toda.' 20 48 500 42 8.5 $suave $false)

$bHibSim = Botao 'SIM, QUERO USAR' 20 96 245 40 $amarelo $escuro 10.5
$bHibNao = Botao 'NAO QUERO USAR' 275 96 245 40 $painel $claro 10.5
[void](Rotulo 'Liga a hibernacao agora. Depois voce pode marcar um horario para hibernar e religar sozinho. Se nao marcar nenhum horario, so a hibernacao fica ligada e mais nada muda.' 20 140 245 74 8.5 $suave $false)
[void](Rotulo 'Desliga a hibernacao e apaga o arquivo "hiberfil.sys" (libera varios GB de disco). Tambem desliga a Inicializacao Rapida e remove horarios criados por este programa.' 275 140 245 74 8.5 $suave $false)

$lHibRes = Rotulo '' 20 218 500 34 10 $verde $true

$pHor = New-Object Windows.Forms.Panel
$pHor.Location = New-Object Drawing.Point(20, 256); $pHor.Size = New-Object Drawing.Size(500, 196); $pHor.BackColor = $painel; $pHor.Visible = $false
$p4.Controls.Add($pHor)
$script:pai = $pHor
$chkHor = New-Object Windows.Forms.CheckBox
$chkHor.Text = 'Quero um horario para hibernar e religar sozinho'
$chkHor.Location = New-Object Drawing.Point(14, 10); $chkHor.Size = New-Object Drawing.Size(470, 24)
$chkHor.Font = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold); $chkHor.ForeColor = $claro; $chkHor.BackColor = [Drawing.Color]::Transparent
$pHor.Controls.Add($chkHor)
[void](Rotulo 'Hibernar as (HH:MM)' 14 42 150 18 8.5 $suave $true)
[void](Rotulo 'Religar sozinho as (HH:MM)' 190 42 200 18 8.5 $suave $true)
$tHib = Caixa '23:00' 14 62 120
$tAco = Caixa '07:00' 190 62 120
[void](Rotulo 'Se deixar a caixa de cima DESMARCADA, nada e agendado: a hibernacao so fica disponivel. Marcando, o PC hiberna e acorda todos os dias nesses horarios (precisa estar na tomada; vale para PC de mesa e depende da BIOS permitir).' 14 98 472 44 8.5 $suave $false)
$bSalvaHor = Botao 'SALVAR' 14 148 230 38 $amarelo $escuro 10.5
$bTiraHor = Botao 'REMOVER HORARIOS' 254 148 232 38 $painel $claro 10
$script:pai = $p4
$lHorarios = Rotulo '' 20 460 500 66 9 $suave $false

$bHibSim.Add_Click({
    if (-not (ExigeAdmin)) { return }
    $saida = (& powercfg /h on 2>&1) -join ' '
    AtualizarHib
    if (HibLigada) {
        $lHibRes.ForeColor = $verde
        $lHibRes.Text = 'Hibernacao LIGADA. Quer um horario? Marque abaixo. Se nao quiser, pode parar por aqui.'
        $pHor.Visible = $true
    } else {
        $lHibRes.ForeColor = $amarelo
        $lHibRes.Text = 'Nao consegui ligar: ' + $saida
    }
})
$bHibNao.Add_Click({
    if (-not (ExigeAdmin)) { return }
    RemoverTarefas
    $saida = (& powercfg /h off 2>&1) -join ' '
    AtualizarHib
    $pHor.Visible = $false
    if (-not (HibLigada)) {
        $lHibRes.ForeColor = $verde
        $lHibRes.Text = 'Hibernacao DESLIGADA e arquivo hiberfil.sys apagado. Espaco liberado no disco.'
    } else {
        $lHibRes.ForeColor = $amarelo
        $lHibRes.Text = 'Nao consegui desligar: ' + $saida
    }
})
$bSalvaHor.Add_Click({
    if (-not (ExigeAdmin)) { return }
    if (-not (HibLigada)) { & powercfg /h on 2>&1 | Out-Null }
    if (-not $chkHor.Checked) {
        $lHibRes.ForeColor = $verde
        $lHibRes.Text = 'Nenhum horario marcado: so a hibernacao ficou ligada. Nada mais mudou.'
        AtualizarHib
        return
    }
    $h1 = HoraValida $tHib.Text; $h2 = HoraValida $tAco.Text
    if (-not $h1 -or -not $h2) { $lHibRes.ForeColor = $amarelo; $lHibRes.Text = 'Horario invalido. Use o formato HH:MM, por exemplo 23:00.'; return }
    if ($h1 -eq $h2) { $lHibRes.ForeColor = $amarelo; $lHibRes.Text = 'Os dois horarios nao podem ser iguais.'; return }
    try {
        RemoverTarefas
        $u = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $a1 = New-ScheduledTaskAction -Execute 'shutdown.exe' -Argument '/h'
        $t1 = New-ScheduledTaskTrigger -Daily -At $h1
        Register-ScheduledTask -TaskName 'Wattcha-Hibernar' -Action $a1 -Trigger $t1 -User $u -Force -ErrorAction Stop | Out-Null
        $a2 = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c exit'
        $t2 = New-ScheduledTaskTrigger -Daily -At $h2
        $cfg = New-ScheduledTaskSettingsSet -WakeToRun -StartWhenAvailable
        Register-ScheduledTask -TaskName 'Wattcha-Acordar' -Action $a2 -Trigger $t2 -Settings $cfg -User $u -Force -ErrorAction Stop | Out-Null
        & powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKE 1 2>$null | Out-Null
        & powercfg /setactive SCHEME_CURRENT 2>$null | Out-Null
        $lHibRes.ForeColor = $verde
        $lHibRes.Text = 'Pronto! Hiberna as ' + $h1 + ' e religa sozinho as ' + $h2 + ', todos os dias.'
    } catch {
        $lHibRes.ForeColor = $amarelo
        $lHibRes.Text = 'Nao consegui agendar: ' + $_.Exception.Message
    }
    AtualizarHib
})
$bTiraHor.Add_Click({
    if (-not (ExigeAdmin)) { return }
    RemoverTarefas
    $lHibRes.ForeColor = $verde
    $lHibRes.Text = 'Horarios removidos. A hibernacao continua como estava.'
    AtualizarHib
})
AtualizarHib
if (HibLigada) { $pHor.Visible = $true }

# =====================================================================
#  ABA 5 - AJUSTES
# =====================================================================
$p5 = $paginas[4]
$script:pai = $p5
$script:sair = $false
$script:avisouBandeja = $false
$nomeTarefaAuto = 'Wattcha-Iniciar'
$chaveRun = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$nomeRun = 'Wattcha'

function AutoLigado {
    $t = Get-ScheduledTask -TaskName $script:nomeTarefaAuto -ErrorAction SilentlyContinue
    if ($t) { return $true }
    $v = (Get-ItemProperty -Path $script:chaveRun -Name $script:nomeRun -ErrorAction SilentlyContinue).($script:nomeRun)
    return [bool]$v
}
function AutoDesligar {
    Unregister-ScheduledTask -TaskName $script:nomeTarefaAuto -Confirm:$false -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $script:chaveRun -Name $script:nomeRun -ErrorAction SilentlyContinue
}
function AutoLigar {
    $vbs = Join-Path (Split-Path -Parent $PSCommandPath) 'Abrir-Wattcha.vbs'
    if (Test-Path $vbs) { $exe = 'wscript.exe'; $arg = '//B "' + $vbs + '" -Segundo' }
    else { $exe = 'powershell.exe'; $arg = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $PSCommandPath + '" -Segundo' }
    if ($script:souAdmin) {
        $u = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $a = New-ScheduledTaskAction -Execute $exe -Argument $arg
        $t = New-ScheduledTaskTrigger -AtLogOn -User $u
        $pr = New-ScheduledTaskPrincipal -UserId $u -LogonType Interactive -RunLevel Highest
        $st = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)
        Register-ScheduledTask -TaskName $script:nomeTarefaAuto -Action $a -Trigger $t -Principal $pr -Settings $st -Force -ErrorAction Stop | Out-Null
        Remove-ItemProperty -Path $script:chaveRun -Name $script:nomeRun -ErrorAction SilentlyContinue
        return 'admin'
    }
    if (-not (Test-Path $script:chaveRun)) { New-Item -Path $script:chaveRun -Force | Out-Null }
    Set-ItemProperty -Path $script:chaveRun -Name $script:nomeRun -Value ($exe + ' ' + $arg)
    return 'normal'
}

[void](Rotulo 'AJUSTES' 20 0 500 24 11 $claro $true)

$c1 = New-Object Windows.Forms.Panel
$c1.Location = New-Object Drawing.Point(20, 32); $c1.Size = New-Object Drawing.Size(500, 130); $c1.BackColor = $painel
$p5.Controls.Add($c1)
$script:pai = $c1
$chkAuto = New-Object Windows.Forms.CheckBox
$chkAuto.Text = 'Abrir junto com o Windows (e medir sozinho)'
$chkAuto.Location = New-Object Drawing.Point(14, 10); $chkAuto.Size = New-Object Drawing.Size(472, 26)
$chkAuto.Font = New-Object Drawing.Font('Segoe UI', 10.5, [Drawing.FontStyle]::Bold); $chkAuto.ForeColor = $claro; $chkAuto.BackColor = [Drawing.Color]::Transparent
$c1.Controls.Add($chkAuto)
[void](Rotulo 'Quando o computador ligar, o programa abre sozinho, escondido perto do relogio, e ja comeca a medir. Assim o HISTORICO fica completo, dia apos dia, sem voce precisar fazer nada. Se mover a pasta do programa, ligue esta opcao de novo.' 14 42 472 62 8.5 $suave $false)
$lAutoRes = Rotulo '' 14 104 472 20 8.5 $verde $true

$c2 = New-Object Windows.Forms.Panel
$c2.Location = New-Object Drawing.Point(20, 172); $c2.Size = New-Object Drawing.Size(500, 118); $c2.BackColor = $painel
$p5.Controls.Add($c2)
$script:pai = $c2
$chkBand = New-Object Windows.Forms.CheckBox
$chkBand.Text = 'Ao fechar ou minimizar, continuar rodando'
$chkBand.Location = New-Object Drawing.Point(14, 10); $chkBand.Size = New-Object Drawing.Size(472, 26)
$chkBand.Font = New-Object Drawing.Font('Segoe UI', 10.5, [Drawing.FontStyle]::Bold); $chkBand.ForeColor = $claro; $chkBand.BackColor = [Drawing.Color]::Transparent
$chkBand.Checked = [bool]$cfg.Bandeja
$c2.Controls.Add($chkBand)
[void](Rotulo 'O programa nao fecha: ele vai para o cantinho da barra de tarefas (perto do relogio, icone amarelo com raio) e segue medindo. Clique duas vezes no icone para abrir. Para sair de verdade: botao direito no icone > Sair de vez.' 14 42 472 70 8.5 $suave $false)

$script:pai = $p5
$lAjusteRes = Rotulo '' 20 300 500 22 9.5 $verde $true
[void](Rotulo ('Seus dados (historico e ajustes) ficam guardados so neste computador, na pasta: ' + $pastaDados) 20 328 500 36 8 $suave $false)

$chkAuto.Checked = (AutoLigado)
$chkAuto.Add_Click({
    if ($chkAuto.Checked) {
        try {
            $modo = AutoLigar
            if ($modo -eq 'admin') { $lAutoRes.Text = 'Ligado: abre com o Windows ja como administrador.' }
            else { $lAutoRes.Text = 'Ligado. (Para abrir ja como administrador, ligue esta opcao com o programa aberto como administrador.)' }
            $lAutoRes.ForeColor = $verde
        } catch {
            $chkAuto.Checked = $false
            $lAutoRes.ForeColor = $amarelo
            $lAutoRes.Text = 'Nao consegui ligar: ' + $_.Exception.Message
        }
    } else {
        AutoDesligar
        $lAutoRes.ForeColor = $verde
        $lAutoRes.Text = 'Desligado: o programa nao abre mais com o Windows.'
    }
})
$chkBand.Add_Click({
    $script:cfg.Bandeja = [bool]$chkBand.Checked
    SalvarCfg
    if ($chkBand.Checked) { $lAjusteRes.Text = 'Ao fechar, o programa continua rodando perto do relogio.' }
    else { $lAjusteRes.Text = 'Ao fechar, o programa fecha de verdade.' }
})

# ---- atualizacoes ----
$script:pai = $p5
$c3 = New-Object Windows.Forms.Panel
$c3.Location = New-Object Drawing.Point(20, 372); $c3.Size = New-Object Drawing.Size(500, 124); $c3.BackColor = $painel
$p5.Controls.Add($c3)
$script:pai = $c3
$chkAtu = New-Object Windows.Forms.CheckBox
$chkAtu.Text = 'Instalar atualizacoes sozinho (recomendado)'
$chkAtu.Location = New-Object Drawing.Point(14, 10); $chkAtu.Size = New-Object Drawing.Size(472, 26)
$chkAtu.Font = New-Object Drawing.Font('Segoe UI', 10.5, [Drawing.FontStyle]::Bold); $chkAtu.ForeColor = $claro; $chkAtu.BackColor = [Drawing.Color]::Transparent
$chkAtu.Checked = [bool]$cfg.AutoAtualizar
$c3.Controls.Add($chkAtu)
[void](Rotulo ('Versao instalada: ' + $VersaoApp + '. O programa confere sozinho, uma vez por dia, se saiu versao nova.') 14 40 472 20 8.5 $suave $false)
$bAtu = Botao 'VERIFICAR AGORA' 14 70 190 34 $amarelo $escuro 9
$lAtuRes = Rotulo '' 214 68 276 48 8.5 $verde $true
$chkAtu.Add_Click({ $script:cfg.AutoAtualizar = [bool]$chkAtu.Checked; SalvarCfg })
$script:pai = $p5

$script:atuEstado = 'ocioso'
$script:tarefaAtu = $null; $script:wcAtu = $null; $script:atuInicio = $null; $script:atuInfo = $null; $script:atuManual = $false

function NovoWebClient {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $w = New-Object Net.WebClient
    $w.Headers.Add('Cache-Control', 'no-cache')
    $w.Headers.Add('User-Agent', 'Wattcha/' + $script:VersaoApp)
    return $w
}
function FimAtu($msg, $cor) {
    $script:atuEstado = 'ocioso'
    if ($script:atuManual) {
        $script:lAtuRes.Text = $msg
        if ($cor -eq 'aviso') { $script:lAtuRes.ForeColor = $script:amarelo } else { $script:lAtuRes.ForeColor = $script:verde }
    }
}
function PedirVersao {
    $script:wcAtu = NovoWebClient
    $script:tarefaAtu = $script:wcAtu.DownloadStringTaskAsync([Uri]($script:UrlsBase[$script:idxBase] + 'versao.json?t=' + [DateTime]::UtcNow.Ticks))
    $script:atuInicio = Get-Date
}
function ChecarAtualizacao($manual) {
    if ($script:atuEstado -ne 'ocioso') { return }
    $script:atuManual = [bool]$manual
    $script:atuEstado = 'verificando'; $script:atuInicio = Get-Date
    $script:idxBase = 0; $script:baseOk = $null
    if ($manual) { $script:lAtuRes.ForeColor = $script:suave; $script:lAtuRes.Text = 'Verificando...' }
    try { PedirVersao }
    catch { $script:atuEstado = 'ocioso'; if ($manual) { FimAtu 'Sem internet agora.' 'aviso' } }
}
function BaixarAtualizacao {
    if ($script:atuEstado -ne 'ocioso' -or -not $script:atuInfo) { return }
    $script:atuEstado = 'baixando'; $script:atuInicio = Get-Date
    $script:atuManual = $true
    $script:lAtuRes.ForeColor = $script:suave; $script:lAtuRes.Text = 'Baixando a versao ' + $script:atuInfo.versao + '...'
    try {
        $script:wcAtu = NovoWebClient
        $script:tarefaAtu = $script:wcAtu.DownloadDataTaskAsync([Uri]($script:baseOk + 'Wattcha.ps1?t=' + [DateTime]::UtcNow.Ticks))
    } catch { $script:atuEstado = 'ocioso'; FimAtu 'Nao consegui baixar. Tente de novo mais tarde.' 'aviso' }
}
function Reiniciar {
    $linha = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $PSCommandPath + '" -AguardarFechar'
    if (-not $script:f.Visible) { $linha += ' -Segundo' } elseif ($script:rodando) { $linha += ' -Medir' }
    try {
        if ($script:souAdmin) { Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $linha -ErrorAction Stop }
        else { Start-Process -FilePath 'powershell.exe' -ArgumentList $linha -WindowStyle Hidden -ErrorAction Stop }
    } catch { return }
    $script:sair = $true
    $script:f.Close()
}
function AplicarAtualizacao($bytes) {
    $info = $script:atuInfo
    try {
        $sha = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace('-', '').ToLower()
        if ($sha -ne ('' + $info.sha256).ToLower()) { FimAtu 'O arquivo baixado veio diferente do esperado. Nada foi trocado.' 'aviso'; return }
        $texto = [Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)
        $tk = $null; $er = $null
        [void][Management.Automation.Language.Parser]::ParseInput($texto, [ref]$tk, [ref]$er)
        $padrao = '\$VersaoApp = ''' + [regex]::Escape('' + $info.versao) + ''''
        if ($er.Count -gt 0 -or $texto -notmatch $padrao) { FimAtu 'A atualizacao veio com defeito. Nada foi trocado.' 'aviso'; return }
        $dest = $PSCommandPath
        Copy-Item -Path $dest -Destination ($dest + '.bak') -Force -ErrorAction SilentlyContinue
        [IO.File]::WriteAllBytes($dest, $bytes)
    } catch { FimAtu ('Nao consegui instalar a atualizacao: ' + $_.Exception.Message) 'aviso'; return }
    $script:atuEstado = 'ocioso'; $script:atuInfo = $null
    $script:bAtu.Text = 'VERIFICAR AGORA'
    $script:abaBtn[4].Text = 'AJUSTES'
    $script:lAtuRes.ForeColor = $script:verde
    $script:lAtuRes.Text = 'Atualizado para a versao ' + $info.versao + '. Ela vale na proxima vez que o programa abrir.'
    if (-not $script:f.Visible) { if (-not $script:souAdmin) { Reiniciar } }
    else {
        $r = [Windows.Forms.MessageBox]::Show('O Wattcha foi atualizado para a versao ' + $info.versao + '. Reiniciar agora para usar?', 'Wattcha', 'YesNo', 'Question')
        if ($r -eq 'Yes') { Reiniciar }
    }
}
$tAtu = New-Object Windows.Forms.Timer
$tAtu.Interval = 700
$tAtu.Add_Tick({
    if ($script:atuEstado -eq 'ocioso') { return }
    $t = $script:tarefaAtu
    if (-not $t) { $script:atuEstado = 'ocioso'; return }
    if (((Get-Date) - $script:atuInicio).TotalSeconds -gt 90) {
        try { $script:wcAtu.CancelAsync() } catch {}
        FimAtu 'O servidor nao respondeu. Tente de novo mais tarde.' 'aviso'
        return
    }
    if (-not $t.IsCompleted) { return }
    if (($t.IsFaulted -or $t.IsCanceled) -and $script:atuEstado -eq 'verificando' -and $script:idxBase -lt ($script:UrlsBase.Count - 1)) {
        $script:idxBase++
        try { PedirVersao } catch { FimAtu 'Nao consegui verificar agora (sem internet?).' 'aviso' }
        return
    }
    if ($t.IsFaulted -or $t.IsCanceled) {
        if ($script:atuEstado -eq 'baixando') { FimAtu 'Nao consegui baixar. Tente de novo mais tarde.' 'aviso' }
        else { FimAtu 'Nao consegui verificar agora (sem internet?).' 'aviso' }
        return
    }
    if ($script:atuEstado -eq 'verificando') {
        try {
            $info = $t.Result | ConvertFrom-Json
            $nova = [version]('' + $info.versao); $atual = [version]$script:VersaoApp
        } catch { FimAtu 'Resposta do servidor ilegivel. Tente mais tarde.' 'aviso'; return }
        $script:baseOk = $script:UrlsBase[$script:idxBase]
        $script:cfg.UltimaChecagem = (Get-Date).ToString('o'); SalvarCfg
        if ($nova -gt $atual) {
            $script:atuInfo = $info
            $script:atuEstado = 'ocioso'
            $script:bAtu.Text = 'ATUALIZAR PARA ' + $info.versao
            $script:abaBtn[4].Text = 'AJUSTES *'
            $script:lAtuRes.ForeColor = $script:amarelo
            $script:lAtuRes.Text = 'Versao nova: ' + $info.versao + '. ' + $info.notas
            if ([bool]$script:cfg.AutoAtualizar) { BaixarAtualizacao }
            elseif (-not $script:f.Visible) { try { $script:ni.ShowBalloonTip(4000, 'Wattcha', 'Tem versao nova. Abra o Wattcha > AJUSTES para atualizar.', [Windows.Forms.ToolTipIcon]::Info) } catch {} }
        } else {
            FimAtu ('Voce ja usa a versao mais nova (' + $script:VersaoApp + ').') 'ok'
        }
    } elseif ($script:atuEstado -eq 'baixando') {
        AplicarAtualizacao $t.Result
    }
})
$tAtu.Start()
$bAtu.Add_Click({
    if ($script:atuInfo) { $script:atuManual = $true; BaixarAtualizacao } else { ChecarAtualizacao $true }
})
function ChecagemAutomatica {
    $ult = [datetime]::MinValue
    try { $ult = [datetime]::Parse('' + $script:cfg.UltimaChecagem, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) } catch {}
    if (((Get-Date) - $ult).TotalHours -ge 20) { ChecarAtualizacao $false }
}
$tIni = New-Object Windows.Forms.Timer
$tIni.Interval = 12000
$tIni.Add_Tick({ $script:tIni.Stop(); ChecagemAutomatica })
$tIni.Start()
$tDia = New-Object Windows.Forms.Timer
$tDia.Interval = 3600000
$tDia.Add_Tick({ ChecagemAutomatica })
$tDia.Start()

# ---------------- Historico (por dia) ----------------
$script:hist = @{}
function CarregarHist {
    $script:hist = @{}
    if (Test-Path $script:arqHist) {
        try {
            foreach ($r in (Import-Csv -Path $script:arqHist)) {
                $script:hist[[string]$r.Data] = [pscustomobject]@{
                    Data = [string]$r.Data
                    Seg = [double]::Parse($r.Seg, $script:inv)
                    Kwh = [double]::Parse($r.Kwh, $script:inv)
                    Custo = [double]::Parse($r.Custo, $script:inv)
                }
            }
        } catch {}
    }
}
function SalvarHist {
    try {
        $linhas = @()
        foreach ($k in ($script:hist.Keys | Sort-Object)) {
            $r = $script:hist[$k]
            $linhas += [pscustomobject]@{ Data = $r.Data; Seg = $r.Seg.ToString('0.##', $script:inv); Kwh = $r.Kwh.ToString('0.#####', $script:inv); Custo = $r.Custo.ToString('0.#####', $script:inv) }
        }
        if ($linhas.Count -gt 0) { $linhas | Export-Csv -Path $script:arqHist -NoTypeInformation -Encoding UTF8 }
    } catch {}
}
function AtualizarHistorico {
    $script:lv.BeginUpdate()
    $script:lv.Items.Clear()
    $totK = 0.0; $totC = 0.0; $nDias = 0
    $hojeTxt = (Get-Date).ToString('yyyy-MM-dd')
    foreach ($k in ($script:hist.Keys | Sort-Object -Descending)) {
        $r = $script:hist[$k]
        if ($r.Seg -lt 60) { continue }
        $d = [datetime]::ParseExact($r.Data, 'yyyy-MM-dd', $script:inv)
        $etq = $d.ToString('dd/MM/yyyy')
        if ($r.Data -eq $hojeTxt) { $etq = $etq + ' (hoje)' }
        $hh = [int][math]::Floor($r.Seg / 3600.0)
        $mm = [int][math]::Floor(($r.Seg % 3600.0) / 60.0)
        $mediaW = $r.Kwh * 1000.0 / ($r.Seg / 3600.0)
        $it = New-Object Windows.Forms.ListViewItem($etq)
        [void]$it.SubItems.Add(('{0:00}h{1:00}min' -f $hh, $mm))
        [void]$it.SubItems.Add(('{0:N2} kWh' -f $r.Kwh))
        [void]$it.SubItems.Add(('{0:N0} W' -f $mediaW))
        [void]$it.SubItems.Add((Reais $r.Custo))
        [void]$script:lv.Items.Add($it)
        $totK += $r.Kwh; $totC += $r.Custo; $nDias++
    }
    $script:lv.EndUpdate()
    if ($nDias -eq 0) {
        $script:lHistMedia.Text = 'sem dados ainda'
        $script:lHistTotal.Text = 'Clique em INICIAR na tela AO VIVO para comecar a registrar.'
    } else {
        $script:lHistMedia.Text = ('{0:N2} kWh  =  {1} por dia' -f ($totK / $nDias), (Reais ($totC / $nDias)))
        $script:lHistTotal.Text = ('Dias medidos: {0}   |   Total: {1:N2} kWh  =  {2}' -f $nDias, $totK, (Reais $totC))
    }
}
$bApagaHist.Add_Click({
    $r = [Windows.Forms.MessageBox]::Show('Apagar TODO o historico de consumo? Isso nao pode ser desfeito.', 'Apagar historico', 'YesNo', 'Warning')
    if ($r -eq 'Yes') { $script:hist = @{}; SalvarHist; Remove-Item -Path $arqHist -Force -ErrorAction SilentlyContinue; AtualizarHistorico }
})
CarregarHist

# ---------------- Logica do medidor ----------------
$script:rodando = $false
$script:soma = 0.0; $script:n = 0; $script:min = 99999.0; $script:max = 0.0
$script:kwh = 0.0; $script:inicio = $null; $script:ultimo = $null; $script:custoMes = 0.0; $script:mediaW = 0.0
$script:contaTick = 0

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 2000

$tick = {
    $tarifa = Numero $tTarifa.Text 1.086
    $horas = Numero $tHoras.Text 24; if ($horas -gt 24 -or $horas -le 0) { $horas = 24 }
    $mon = Numero $tMonitor.Text 0
    $m = Medir $mon
    $agora = Get-Date
    $dt = ($agora - $script:ultimo).TotalSeconds; $script:ultimo = $agora
    if ($dt -gt 30 -or $dt -lt 0) { $dt = 0 }     # PC hibernou ou relogio mudou: nao conta esse intervalo
    $inc = ($m.Parede / 1000.0) * ($dt / 3600.0)
    $script:kwh += $inc
    $script:soma += $m.Parede; $script:n++
    if ($m.Parede -lt $script:min) { $script:min = $m.Parede }
    if ($m.Parede -gt $script:max) { $script:max = $m.Parede }
    $media = $script:soma / $script:n; $script:mediaW = $media

    # historico do dia
    $chave = $agora.ToString('yyyy-MM-dd')
    if (-not $script:hist.ContainsKey($chave)) { $script:hist[$chave] = [pscustomobject]@{ Data = $chave; Seg = 0.0; Kwh = 0.0; Custo = 0.0 } }
    $rh = $script:hist[$chave]
    $rh.Seg += $dt; $rh.Kwh += $inc; $rh.Custo += ($inc * $tarifa)
    $script:contaTick++
    if ($script:contaTick % 15 -eq 0) { SalvarHist; SalvarCfg }

    $kwhMes = $media / 1000.0 * $horas * 30
    $script:custoMes = $kwhMes * $tarifa
    $lMes.Text = Reais $script:custoMes
    $lKwhMes.Text = ('{0:N1} kWh por mes' -f $kwhMes)
    $lAgora.Text = ('{0:N0} W' -f $m.Parede)
    $lMedia.Text = ('{0:N0} W' -f $media)
    $lDia.Text = Reais ($media / 1000.0 * $horas * $tarifa)
    $lKwhAc.Text = ('{0:N3} kWh' -f $script:kwh)
    $lCustoAc.Text = Reais ($script:kwh * $tarifa)
    $dur = $agora - $script:inicio
    $dH = [int][math]::Floor($dur.TotalHours); $dM = [int]$dur.Minutes; $dS = [int]$dur.Seconds
    $lDetalhe.Text = ('Medindo ha {0:00}:{1:00}:{2:00}   |   minimo {3:N0} W, maximo {4:N0} W' -f $dH, $dM, $dS, $script:min, $script:max) + "`r`n" + ('Processador {0:N0}% (~{1:N0} W)   |   Video ~{2:N0} W ({3})' -f $m.Carga, $m.CpuW, $m.GpuW, $m.Fonte)
    if ($script:pHist.Visible -and ($script:contaTick % 5 -eq 0)) { AtualizarHistorico }
    try { $script:ni.Text = ('Wattcha: {0:N0} W | hoje {1}' -f $m.Parede, (Reais $rh.Custo)) } catch {}
}
$timer.Add_Tick($tick)

function Salvar {
    if ($script:n -lt 1) { return }
    $tarifa = Numero $tTarifa.Text 1.086
    $pasta = [Environment]::GetFolderPath('Desktop')
    $arq = Join-Path $pasta 'wattcha-medicao.txt'
    $linha = ('{0} | {1} | media {2:N0} W | {3:N3} kWh medidos | estimativa mensal {4} | tarifa {5}' -f (Get-Date -Format 'dd/MM/yyyy HH:mm'), $env:COMPUTERNAME, $script:mediaW, $script:kwh, (Reais $script:custoMes), (Reais $tarifa))
    $linha | Out-File -FilePath $arq -Append -Encoding UTF8
}
function IniciarMedicao {
    if ($script:rodando) { return }
    $script:rodando = $true
    $script:soma = 0.0; $script:n = 0; $script:min = 99999.0; $script:max = 0.0; $script:kwh = 0.0
    $script:inicio = Get-Date; $script:ultimo = $script:inicio
    $script:btn.Text = 'PARAR'; $script:btn.BackColor = $script:rosa
    $script:lDetalhe.Text = 'Medindo... os valores aparecem em instantes.'
    $script:timer.Start()
    & $script:tick
}
function PararMedicao {
    if (-not $script:rodando) { return }
    $script:timer.Stop(); $script:rodando = $false
    $script:btn.Text = 'INICIAR'; $script:btn.BackColor = $script:amarelo
    SalvarHist; Salvar
    $script:lDetalhe.Text = ($script:lDetalhe.Text + "`r`nParado. Resumo salvo em wattcha-medicao.txt (Area de Trabalho).")
}
$script:autoMedicao = $false
$btn.Add_Click({ if ($script:rodando) { PararMedicao } else { $script:autoMedicao = $false; IniciarMedicao } })

# ---------------- Icone perto do relogio ----------------
function NovoIcone {
    $bmp = New-Object Drawing.Bitmap 32, 32
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([Drawing.Color]::Transparent)
    $g.FillEllipse((New-Object Drawing.SolidBrush ($script:amarelo)), 1, 1, 30, 30)
    $pts = [Drawing.Point[]]@(
        (New-Object Drawing.Point 18, 3), (New-Object Drawing.Point 9, 18), (New-Object Drawing.Point 15, 18),
        (New-Object Drawing.Point 13, 29), (New-Object Drawing.Point 23, 13), (New-Object Drawing.Point 17, 13))
    $g.FillPolygon((New-Object Drawing.SolidBrush ($script:escuro)), $pts)
    $g.Dispose()
    return [Drawing.Icon]::FromHandle($bmp.GetHicon())
}
$icone = NovoIcone
$f.Icon = $icone
$ni = New-Object Windows.Forms.NotifyIcon
$ni.Icon = $icone; $ni.Text = 'Wattcha - energia do PC'; $ni.Visible = $true

function EsconderJanela {
    $script:f.WindowState = [Windows.Forms.FormWindowState]::Normal
    $script:f.Hide()
    $script:timer.Interval = 5000
    if (-not $script:avisouBandeja) {
        $script:avisouBandeja = $true
        try { $script:ni.ShowBalloonTip(3000, 'Wattcha', 'Continua rodando aqui perto do relogio. Clique duas vezes no icone para abrir.', [Windows.Forms.ToolTipIcon]::Info) } catch {}
    }
}
function AbrirJanela {
    $script:f.Opacity = 1
    $script:f.ShowInTaskbar = $true
    $script:f.Show()
    $script:f.WindowState = [Windows.Forms.FormWindowState]::Normal
    $script:timer.Interval = 2000
    $script:f.TopMost = $true; $script:f.TopMost = $false
    $script:f.Activate()
}
$menu = New-Object Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add('Abrir', $null, { AbrirJanela })
[void]$menu.Items.Add('Sair de vez', $null, { $script:sair = $true; $f.Close() })
$ni.ContextMenuStrip = $menu
$ni.Add_DoubleClick({ AbrirJanela })

$tEvento = New-Object Windows.Forms.Timer
$tEvento.Interval = 700
$tEvento.Add_Tick({ try { if ($evAbrir -and $evAbrir.WaitOne(0)) { AbrirJanela } } catch {} })
$tEvento.Start()

$f.Add_Resize({
    if ($f.WindowState -eq [Windows.Forms.FormWindowState]::Minimized -and [bool]$script:cfg.Bandeja) { EsconderJanela }
})
$f.Add_FormClosing({
    param($quem, $e)
    if (-not $script:sair -and [bool]$script:cfg.Bandeja -and $e.CloseReason -eq [Windows.Forms.CloseReason]::UserClosing) {
        $e.Cancel = $true
        EsconderJanela
        return
    }
    $timer.Stop(); $tEvento.Stop()
    if ($script:rodando -and -not $Segundo -and -not $script:autoMedicao) { Salvar }
    SalvarHist; SalvarCfg
    try { $ni.Visible = $false; $ni.Dispose() } catch {}
    try { $script:mutex.ReleaseMutex() } catch {}
})
$f.Add_Shown({
    if ($Medir -and -not $Segundo) { IniciarMedicao }
    elseif (-not $Segundo) { $script:autoMedicao = $true; IniciarMedicao }   # abriu na mao: ja comeca a medir
    if ($Segundo) {
        IniciarMedicao
        EsconderJanela
        $f.Opacity = 1
    }
})

AtualizarModoAtual
MostrarAba 0
MostrarSub 'vivo'
try {
    $pastaScript = Split-Path -Parent $PSCommandPath
    $arqErro = Join-Path $pastaScript 'erro-wattcha.txt'
    $reais = @($Error | Where-Object { $_.FullyQualifiedErrorId -notmatch 'CmdletizationQuery_NotFound|GetItemPropertyCommand' })
    if ($reais.Count -gt 0) {
        $logTxt = ($reais | ForEach-Object { ($_ | Out-String).Trim() }) -join "`r`n----`r`n"
        Set-Content -Path $arqErro -Value ('Erros ao montar a janela (' + $reais.Count + '):' + "`r`n" + $logTxt) -Encoding UTF8
    } elseif (Test-Path $arqErro) { Remove-Item -Path $arqErro -Force -ErrorAction SilentlyContinue }
} catch {}
if ($Segundo) { $f.Opacity = 0; $f.ShowInTaskbar = $false }
[Windows.Forms.Application]::Run($f)
