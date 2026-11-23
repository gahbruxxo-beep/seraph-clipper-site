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
powershell -NoProfile -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri 'https://visusclipper.online/download/atualizar_instalacao_7977287bb130da13.py' -OutFile $env:VISUS_UPDATE_SCRIPT; if ((Get-FileHash -Algorithm SHA256 -LiteralPath $env:VISUS_UPDATE_SCRIPT).Hash -ne '7977287bb130da1343e56e6257de519f5e4168e95b8e912c5502f14487affd03') { throw 'O atualizador baixado falhou na verificacao de integridade.' }"
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
