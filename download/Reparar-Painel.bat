@echo off
rem Conserta o painel: reinstala as bibliotecas, o navegador da publicacao e testa se o painel abre.
setlocal
cd /d "%~dp0"
set PYTHONIOENCODING=utf-8
if not exist ".venv\Scripts\python.exe" (
  echo Este arquivo precisa ficar na pasta do Visus Clipper, junto de painel.bat.
  echo Se ele ja esta la, a instalacao esta incompleta: de dois cliques em Instalar.bat.
  pause
  exit /b 1
)
echo Conferindo as bibliotecas do Visus Clipper. Pode levar alguns minutos...
".venv\Scripts\python.exe" -m pip install -q --disable-pip-version-check psutil==7.2.2
".venv\Scripts\python.exe" scripts\atualizar_instalacao.py --pasta . --dependencias
if errorlevel 1 goto sem_internet
if exist work\atualizar_pip.flag del work\atualizar_pip.flag
if exist work\aviso_painel.txt del work\aviso_painel.txt
echo Conferindo se o painel consegue abrir...
".venv\Scripts\python.exe" -W ignore -c "from seraph.web.server import app; print('Painel pronto para abrir.')"
if errorlevel 1 goto erro_painel
call painel.bat
exit /b 0

:sem_internet
echo.
echo Nao foi possivel baixar as bibliotecas. Confira a internet e rode este arquivo de novo.
pause
exit /b 1

:erro_painel
echo.
echo O painel ainda nao abre. Rode o Instalar.bat de novo: ele refaz o que estiver faltando.
echo Se continuar, envie uma foto desta janela para o suporte.
pause
exit /b 1
