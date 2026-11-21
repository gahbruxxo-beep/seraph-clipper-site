@echo off
setlocal
cd /d "%~dp0"
set PYTHONIOENCODING=utf-8
if not exist ".venv\Scripts\python.exe" (
  echo Coloque este arquivo na pasta do Visus Clipper, junto de painel.bat.
  echo Depois execute novamente.
  pause
  exit /b 1
)
echo Conferindo a biblioteca do controle de pausa...
".venv\Scripts\python.exe" -m pip install --disable-pip-version-check psutil==7.2.2
if errorlevel 1 (
  echo Nao foi possivel instalar a biblioteca. Confira a mensagem acima e sua conexao.
  pause
  exit /b 1
)
echo Conferindo se o servidor consegue iniciar...
".venv\Scripts\python.exe" -c "from seraph.web.server import app; print('Servidor carregado com sucesso.')"
if errorlevel 1 (
  echo O servidor encontrou outro erro. Envie a mensagem exibida acima.
  pause
  exit /b 1
)
call painel.bat
endlocal
