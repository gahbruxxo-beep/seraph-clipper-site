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
powershell -NoProfile -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri 'https://visusclipper.online/download/atualizar_instalacao_9436c7ef6596f36a.py' -OutFile $env:VISUS_UPDATE_SCRIPT; if ((Get-FileHash -Algorithm SHA256 -LiteralPath $env:VISUS_UPDATE_SCRIPT).Hash -ne '9436c7ef6596f36a04ce70f5e8ef07c78ffa6299308699d945cca99eeb4784db') { throw 'O atualizador baixado falhou na verificacao de integridade.' }"
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
