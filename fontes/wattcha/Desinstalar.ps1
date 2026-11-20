# Desinstalador do Wattcha
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
$destino = Join-Path $env:LOCALAPPDATA 'Programs\Wattcha'
$dados = Join-Path $env:LOCALAPPDATA 'Wattcha'
$r = [Windows.Forms.MessageBox]::Show('Remover o Wattcha deste computador?', 'Desinstalar o Wattcha', 'YesNo', 'Question')
if ($r -ne 'Yes') { exit }
foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'")) {
    if ($p.ProcessId -ne $PID -and $p.CommandLine -match 'Wattcha\.ps1') { Stop-Process -Id $p.ProcessId -Force }
}
Unregister-ScheduledTask -TaskName 'Wattcha-*' -Confirm:$false
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Wattcha'
Remove-Item -Path (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Wattcha.lnk') -Force
Remove-Item -Path (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Wattcha.lnk') -Force
Remove-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Wattcha' -Recurse -Force
$r2 = [Windows.Forms.MessageBox]::Show('Apagar tambem o seu historico de consumo e os ajustes?' + [Environment]::NewLine + '(Se escolher NAO, eles ficam guardados caso voce instale de novo.)', 'Desinstalar o Wattcha', 'YesNo', 'Question')
if ($r2 -eq 'Yes') { Remove-Item -Path $dados -Recurse -Force }
# a pasta do programa se apaga depois que este script terminar
Start-Process -FilePath 'cmd.exe' -ArgumentList ('/c ping 127.0.0.1 -n 3 >nul & rmdir /s /q "' + $destino + '"') -WindowStyle Hidden
[void][Windows.Forms.MessageBox]::Show('Wattcha removido.', 'Wattcha')
