@echo off
setlocal
chcp 65001 >nul
set PYTHONIOENCODING=utf-8
set "VISUS_UPDATE_ROOT=%~dp0."
if not exist "%VISUS_UPDATE_ROOT%\.venv\Scripts\python.exe" (
  echo Coloque este arquivo na pasta do Visus Clipper, junto de painel.bat.
  echo Depois execute novamente.
  pause
  exit /b 1
)
set "VISUS_UPDATE_SCRIPT=%TEMP%\visus-atualizar-%RANDOM%-%RANDOM%.py"
echo Baixando o atualizador...
powershell -NoProfile -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri 'https://visusclipper.online/download/atualizar_instalacao_6d165ccca0a627a4.py' -OutFile $env:VISUS_UPDATE_SCRIPT; if ((Get-FileHash -Algorithm SHA256 -LiteralPath $env:VISUS_UPDATE_SCRIPT).Hash -ne '6d165ccca0a627a4de65f6a9ac7a63b5d6b89722c4c037e4081fb665937ba9af') { throw 'O atualizador baixado falhou na verificacao de integridade.' }"
if errorlevel 1 (
  echo Nao foi possivel baixar ou conferir o atualizador. Nenhum arquivo do programa foi alterado.
  pause
  exit /b 1
)
"%VISUS_UPDATE_ROOT%\.venv\Scripts\python.exe" "%VISUS_UPDATE_SCRIPT%" --pasta "%VISUS_UPDATE_ROOT%"
set "VISUS_UPDATE_RESULT=%ERRORLEVEL%"
del "%VISUS_UPDATE_SCRIPT%"
echo.
if "%VISUS_UPDATE_RESULT%"=="0" (
  echo Atualizacao concluida. Abra o painel e pressione Ctrl+F5.
) else (
  echo Confira a mensagem acima. Se precisar de ajuda, envie uma captura desta janela.
)
pause
exit /b %VISUS_UPDATE_RESULT%
