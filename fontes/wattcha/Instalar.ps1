# Instalador do Wattcha (instala so para o seu usuario, sem pedir administrador)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$origem = $PSScriptRoot
$destino = Join-Path $env:LOCALAPPDATA 'Programs\Wattcha'
$versao = '1.0.0'
try { $m = [regex]::Match((Get-Content -Path (Join-Path $origem 'Wattcha.ps1') -Raw), "\`$VersaoApp = '([0-9.]+)'"); if ($m.Success) { $versao = $m.Groups[1].Value } } catch {}
try {
    # fecha o Wattcha se ja estiver aberto
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue)) {
        if ($p.ProcessId -ne $PID -and $p.CommandLine -match 'Wattcha\.ps1|Medidor-de-Energia\.ps1') { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    }
    Start-Sleep -Milliseconds 800
    New-Item -Path $destino -ItemType Directory -Force | Out-Null
    foreach ($a in @('Wattcha.ps1', 'Abrir-Wattcha.vbs', 'wattcha.ico', 'Desinstalar.ps1')) {
        Copy-Item -Path (Join-Path $origem $a) -Destination (Join-Path $destino $a) -Force
        Unblock-File -Path (Join-Path $destino $a) -ErrorAction SilentlyContinue
    }
    $vbs = Join-Path $destino 'Abrir-Wattcha.vbs'
    $ico = Join-Path $destino 'wattcha.ico'
    $ws = New-Object -ComObject WScript.Shell
    function NovoAtalho($caminho) {
        $l = $ws.CreateShortcut($caminho)
        $l.TargetPath = 'wscript.exe'
        $l.Arguments = '//B "' + $vbs + '"'
        $l.WorkingDirectory = $destino
        $l.IconLocation = $ico
        $l.Description = 'Wattcha - quanto o seu PC gasta de energia'
        $l.Save()
    }
    $menu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    NovoAtalho (Join-Path $menu 'Wattcha.lnk')
    $r = [Windows.Forms.MessageBox]::Show('Criar um atalho do Wattcha na Area de Trabalho?', 'Instalando o Wattcha', 'YesNo', 'Question')
    if ($r -eq 'Yes') { NovoAtalho (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Wattcha.lnk') }
    # aparece em Configuracoes > Aplicativos (para desinstalar)
    $chave = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Wattcha'
    New-Item -Path $chave -Force | Out-Null
    Set-ItemProperty -Path $chave -Name DisplayName -Value 'Wattcha'
    Set-ItemProperty -Path $chave -Name DisplayVersion -Value $versao
    Set-ItemProperty -Path $chave -Name Publisher -Value 'Visus'
    Set-ItemProperty -Path $chave -Name DisplayIcon -Value $ico
    Set-ItemProperty -Path $chave -Name InstallLocation -Value $destino
    Set-ItemProperty -Path $chave -Name UninstallString -Value ('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $destino 'Desinstalar.ps1') + '"')
    Set-ItemProperty -Path $chave -Name NoModify -Value 1 -Type DWord
    Set-ItemProperty -Path $chave -Name NoRepair -Value 1 -Type DWord
    Start-Process -FilePath 'wscript.exe' -ArgumentList ('//B "' + $vbs + '"')
    [void][Windows.Forms.MessageBox]::Show('Wattcha instalado! Ele ja esta abrindo. Para abrir depois, use o atalho "Wattcha" no Menu Iniciar (ou na Area de Trabalho). Ele se atualiza sozinho.', 'Wattcha')
} catch {
    [void][Windows.Forms.MessageBox]::Show('Nao consegui instalar: ' + $_.Exception.Message, 'Wattcha')
}
