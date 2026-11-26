"""Atualiza uma instalação existente, incluindo checkouts Git, com backup local.

Ordem: fecha o painel, guarda a lista de bibliotecas, instala as bibliotecas novas, troca o código,
testa o painel novo e só então apaga a marca PENDENTE. Se qualquer passo falhar, volta o código e as
bibliotecas para a versão anterior e reabre o painel.

    python atualizar_instalacao.py --pasta <pasta>                  atualiza pelo site
    python atualizar_instalacao.py --pasta <pasta> --dependencias   só confere/instala as bibliotecas
"""
from __future__ import annotations

import argparse
import errno
import hashlib
import json
import os
import shutil
import socket
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.request
import zipfile
from contextlib import ExitStack, closing, contextmanager
from datetime import datetime
from pathlib import Path, PurePosixPath

SITE = "https://visusclipper.online/"
ROOT_FILES = {"requirements.txt", "VERSAO", "ORIGEM.json", "LEIA-ME.txt"}
# Bibliotecas da placa NVIDIA (cerca de 2 GB): só entram em PCs que usam a placa para o Whisper.
GPU_REQ = "scripts/requirements-gpu.txt"
GPU_PACOTES = ("nvidia-cublas-cu12", "nvidia-cudnn-cu12")
BACKUPS_MANTIDOS = 2
SEM_INTERNET = ("Não consegui baixar as bibliotecas do Visus Clipper. Confira a internet e tente de novo; "
                "a versão anterior continua instalada e nada foi perdido.")


def baixar(path: str) -> bytes:
    request = urllib.request.Request(SITE + path, headers={"Cache-Control": "no-cache"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def preparar(data: bytes, manifest: dict, stage: Path) -> list[str]:
    if hashlib.sha256(data).hexdigest() != manifest["sha256"]:
        raise RuntimeError("O pacote baixado falhou na conferência SHA-256.")
    archive = stage / "pacote.zip"
    archive.write_bytes(data)
    files = []
    with zipfile.ZipFile(archive) as package:
        for entry in package.infolist():
            name = entry.filename.replace("\\", "/")
            path = PurePosixPath(name)
            if not path.parts or path.is_absolute() or ".." in path.parts or ":" in name or path.parts[0] != "VisusClipper":
                raise RuntimeError("Caminho inválido no pacote.")
            if entry.is_dir():
                continue
            if len(path.parts) < 2:
                raise RuntimeError("Arquivo fora da pasta do aplicativo.")
            relative = PurePosixPath(*path.parts[1:])
            rel = relative.as_posix()
            allowed = (relative.parts[0] in {"seraph", "assets", "scripts"}
                       or rel in ROOT_FILES or rel == "config/default.yaml"
                       or (len(relative.parts) == 1 and relative.suffix == ".bat"))
            if not allowed:
                raise RuntimeError(f"Arquivo inesperado no pacote: {rel}")
            if rel in files:
                raise RuntimeError("Arquivo duplicado no pacote.")
            target = stage / "novo" / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(package.read(entry))
            files.append(rel)
    if not {"VERSAO", "requirements.txt", "seraph/__main__.py"}.issubset(files):
        raise RuntimeError("Pacote incompleto.")
    if (stage / "novo/VERSAO").read_text().strip() != manifest["versao"]:
        raise RuntimeError("A versão interna não corresponde ao manifesto.")
    return files


def substituir(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    pending = target.with_name(target.name + ".atualizando")
    try:
        shutil.copyfile(source, pending)
        pending.replace(target)
    finally:
        pending.unlink(missing_ok=True)


def restaurar(root: Path, backup: Path) -> None:
    previous = json.loads((backup / "estado.json").read_text(encoding="utf-8"))
    for rel, existed in previous.items():
        target = root / rel
        if existed:
            substituir(backup / "arquivos" / rel, target)
        else:
            target.unlink(missing_ok=True)
    (backup / "PENDENTE").unlink(missing_ok=True)


def aplicar(root: Path, stage: Path, files: list[str], backup: Path) -> None:
    previous = {}
    for rel in files:
        target = root / rel
        if root.resolve() not in target.resolve().parents:
            raise RuntimeError("Destino fora da instalação.")
        previous[rel] = target.exists()
        if target.exists():
            saved = backup / "arquivos" / rel
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(target, saved)
    backup.mkdir(parents=True, exist_ok=True)
    (backup / "estado.json").write_text(json.dumps(previous), encoding="utf-8")
    (backup / "PENDENTE").write_text("1", encoding="ascii")
    try:
        for rel in sorted(files, key=lambda name: (name == "VERSAO", name)):
            substituir(stage / "novo" / rel, root / rel)
    except Exception:
        restaurar(root, backup)
        raise


def pip(python: Path | str, *args: str, falha: str = SEM_INTERNET) -> None:
    """Roda o pip; se falhar, troca o erro técnico por uma frase simples."""
    if subprocess.run([str(python), "-m", "pip", *args, "--disable-pip-version-check"],
                      check=False).returncode != 0:
        raise RuntimeError(falha)


def tem_nvidia() -> bool:
    try:
        return subprocess.run(["nvidia-smi", "-L"], capture_output=True, timeout=30,
                              creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0)).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def usa_cuda(root: Path, python: Path | str) -> bool:
    """O Whisper deste PC está configurado para a placa? (o instalador grava cpu se o teste falhar)"""
    code = "from seraph import config; print(config.load()['whisper'].get('device', 'cuda'))"
    try:
        r = subprocess.run([str(python), "-c", code], cwd=root, capture_output=True, text=True,
                           timeout=120, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    except (OSError, subprocess.SubprocessError):
        return True
    return r.returncode != 0 or r.stdout.strip().endswith("cuda")


def instalar_dependencias(root: Path, python: Path | str, origem: Path,
                          falha: str = SEM_INTERNET) -> list[str]:
    """Instala requirements.txt de `origem` (+ as da placa NVIDIA, se servirem) e o navegador da publicação.
    Devolve avisos que não impedem o uso."""
    avisos = []
    print("Instalando as bibliotecas (pode levar alguns minutos)...", flush=True)
    pip(python, "install", "-q", "-r", str(origem / "requirements.txt"), falha=falha)
    gpu_req = origem / GPU_REQ
    nvidia = tem_nvidia()
    if nvidia and gpu_req.is_file() and usa_cuda(root, python):
        pip(python, "install", "-q", "-r", str(gpu_req), falha=falha)
    elif not nvidia:
        # Sem placa NVIDIA essas bibliotecas não servem para nada e ocupam cerca de 2 GB.
        subprocess.run([str(python), "-m", "pip", "uninstall", "-y", "-q", *GPU_PACOTES],
                       check=False, capture_output=True)
    print("Conferindo o navegador da publicação automática...", flush=True)
    try:
        ok = subprocess.run([str(python), "-m", "playwright", "install", "--no-shell", "chromium"],
                            check=False, timeout=30 * 60).returncode == 0
    except (OSError, subprocess.SubprocessError):
        ok = False
    if not ok:
        avisos.append("Não consegui atualizar o navegador da publicação automática agora. "
                      "Se a publicação no TikTok ou no YouTube falhar, rode o Reparar-Painel.bat.")
    return avisos


def congelar(python: Path | str, destino: Path) -> Path | None:
    """Guarda a lista exata das bibliotecas atuais para poder voltar a ela."""
    r = subprocess.run([str(python), "-m", "pip", "freeze", "--disable-pip-version-check"],
                       capture_output=True, text=True, check=False)
    linhas = [l.strip() for l in r.stdout.splitlines() if "==" in l and not l.startswith(("-", "#"))]
    if r.returncode != 0 or not linhas:
        return None
    destino.parent.mkdir(parents=True, exist_ok=True)
    destino.write_text("\n".join(linhas) + "\n", encoding="utf-8")
    return destino


def voltar_bibliotecas(python: Path | str, lista: Path | None) -> None:
    if not lista or not lista.is_file():
        return
    print("Voltando as bibliotecas para a versão anterior...", flush=True)
    if subprocess.run([str(python), "-m", "pip", "install", "-q", "--disable-pip-version-check",
                       "-r", str(lista)], check=False).returncode != 0:
        print("Não consegui voltar todas as bibliotecas. Se o painel não abrir, rode o Reparar-Painel.bat.",
              flush=True)


def limpar_backups(root: Path, manter: int = BACKUPS_MANTIDOS) -> int:
    """Apaga cópias antigas do código (work/backup_atualizacao), mantendo as `manter` mais novas.
    Nunca apaga uma cópia com PENDENTE (atualização ainda não confirmada)."""
    base = (root / "work" / "backup_atualizacao").resolve()
    if not base.is_dir() or base.parent.name != "work":
        return 0
    prontos = sorted((d for d in base.iterdir() if d.is_dir() and not (d / "PENDENTE").exists()),
                     key=lambda d: d.name, reverse=True)
    apagados = 0
    for velho in prontos[manter:]:
        velho = velho.resolve()
        if velho.parent != base:
            continue
        shutil.rmtree(velho, ignore_errors=True)
        apagados += 1
    return apagados


def painel_respondeu(timeout: float = 120) -> bool:
    fim = time.monotonic() + timeout
    while time.monotonic() < fim:
        try:
            with urllib.request.urlopen("http://127.0.0.1:8765/api/config-login", timeout=2) as response:
                if response.status == 200:
                    return True
        except OSError:
            pass
        time.sleep(2)
    return False


@contextmanager
def trava(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+b") as handle:
        handle.seek(0)
        if os.name == "nt":
            import msvcrt
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield


ADIADO = "9999-12-31T23:59:59"
UPDATE_REQUEST = "atualizacao.solicitada"


def _trava_ocupada(error: OSError) -> bool:
    # msvcrt.locking devolve PermissionError/EACCES, não BlockingIOError,
    # quando outra instância do atualizador já possui o byte de trava.
    return error.errno in (errno.EACCES, errno.EAGAIN, errno.EDEADLK)


def aguardar_outro_atualizador(root: Path, versao: str, timeout: int = 20 * 60) -> bool:
    """Espera outra instância; True significa que ela já instalou esta versão."""
    deadline = time.monotonic() + timeout
    announced = False
    while True:
        try:
            with trava(root / "work/atualizador_manual.lock"):
                atual = (root / "VERSAO").read_text(encoding="utf-8").strip() \
                    if (root / "VERSAO").exists() else ""
                return atual == versao
        except OSError as error:
            if not _trava_ocupada(error):
                raise
            if not announced:
                print("Outra atualização já está em andamento. Aguardando ela terminar; "
                      "não abra outra janela do atualizador.", flush=True)
                announced = True
            if time.monotonic() >= deadline:
                raise RuntimeError(
                    "A outra atualização não terminou em 20 minutos. Feche somente esta janela "
                    "e envie logs/automatico.log e logs/painel.log.") from error
            time.sleep(5)


def ajustar_fila(root: Path, *, restaurar: bool = False) -> None:
    """Adia só posts não iniciados. Diário SQLite recupera inclusive uma queda do atualizador."""
    path = root / "work/painel/seraph.db"
    if not path.exists():
        return
    with closing(sqlite3.connect(path, timeout=30)) as conn, conn:
        conn.execute("BEGIN IMMEDIATE")
        cols = {r[1] for r in conn.execute("PRAGMA table_info(publicacoes)")}
        if not {"id", "estado", "depois"}.issubset(cols):
            raise RuntimeError("Formato da fila desconhecido; nenhuma publicação foi alterada.")
        conn.execute("CREATE TABLE IF NOT EXISTS atualizador_adiados (id INTEGER PRIMARY KEY, depois TEXT)")
        if restaurar:
            conn.execute("UPDATE publicacoes SET depois=(SELECT depois FROM atualizador_adiados "
                         "WHERE id=publicacoes.id) WHERE depois=? "
                         "AND id IN (SELECT id FROM atualizador_adiados)", (ADIADO,))
            conn.execute("DELETE FROM atualizador_adiados")
        else:
            # Uma edição manual posterior prevalece; seu novo horário passa a ser o original.
            conn.execute("DELETE FROM atualizador_adiados WHERE id NOT IN "
                         "(SELECT id FROM publicacoes WHERE depois=?)", (ADIADO,))
            conn.execute("INSERT OR IGNORE INTO atualizador_adiados SELECT id, depois "
                         "FROM publicacoes WHERE estado='na_fila'")
            conn.execute("UPDATE publicacoes SET depois=? WHERE estado='na_fila'", (ADIADO,))


@contextmanager
def reter_publicacoes(root: Path):
    request = root / "work" / UPDATE_REQUEST
    request.parent.mkdir(parents=True, exist_ok=True)
    try:
        try:
            with trava(root / "work/atualizador_manual.lock"):
                request.write_text(str(os.getpid()), encoding="ascii")
                ajustar_fila(root, restaurar=True)
                try:
                    ajustar_fila(root)
                    print("Posts da fila aguardam a atualização; a publicação já iniciada pode terminar. "
                          "Mantenha esta janela e o navegador abertos.", flush=True)
                    yield lambda: ajustar_fila(root)
                finally:
                    ajustar_fila(root, restaurar=True)
        except OSError as error:
            if _trava_ocupada(error):
                raise RuntimeError("Outro atualizador iniciou ao mesmo tempo. Aguarde sua conclusão.") from error
            raise
    finally:
        try:
            if request.read_text(encoding="ascii").strip() == str(os.getpid()):
                request.unlink(missing_ok=True)
        except OSError:
            pass


def publicacao_em_andamento(root: Path) -> bool:
    path = root / "work/painel/seraph.db"
    if not path.exists():
        return False
    try:
        with closing(sqlite3.connect(path, timeout=5)) as conn:
            return conn.execute(
                "SELECT 1 FROM publicacoes WHERE estado='publicando' LIMIT 1").fetchone() is not None
    except sqlite3.Error:
        return True


def encerrar_publicador_ocioso(root: Path) -> bool:
    """Encerra somente o worker sem upload ativo; itens na fila já foram adiados."""
    if publicacao_em_andamento(root):
        return False
    try:
        import psutil
    except ImportError:
        return False
    stopped = False
    for process in psutil.process_iter(["pid", "name"]):
        if not (process.info.get("name") or "").lower().startswith("python"):
            continue
        try:
            args = process.cmdline() or []
            if not any(args[i:i + 3] == ["-m", "seraph", "publicar"] for i in range(len(args))):
                continue
            if Path(process.cwd()).resolve() != root.resolve():
                continue
            process.terminate()
            process.wait(timeout=15)
            stopped = True
        except psutil.NoSuchProcess:
            stopped = True
        except (psutil.AccessDenied, psutil.TimeoutExpired):
            return False
    return stopped


@contextmanager
def livre(root: Path, reter=lambda: None):
    """Aguarda a tentativa atual (legados esperam 10 min pela Meta), sem encerrá-la."""
    deadline = time.monotonic() + 20 * 60
    labels = {"atualizacao.lock": "outra atualização", "fila.lock": "processamento de vídeo",
              "publicar.lock": "a publicação atual ou seu intervalo",
              "manutencao.lock": "a manutenção automática"}
    while True:
        reter()  # Inclui novas tentativas agendadas pelo publicador antigo.
        stack = ExitStack()
        try:
            for name in labels:
                stack.enter_context(trava(root / "work" / name))
            break
        except OSError as error:
            stack.close()
            import errno
            if error.errno not in (errno.EACCES, errno.EAGAIN, errno.EDEADLK):
                raise
            if name == "publicar.lock" and encerrar_publicador_ocioso(root):
                print("Publicador estava apenas aguardando o intervalo entre posts; "
                      "a espera foi encerrada para aplicar a atualização.", flush=True)
                continue
            if time.monotonic() >= deadline:
                raise RuntimeError(f"Ainda aguardando {labels[name]}. A fila será liberada; "
                                   "nenhuma tarefa foi encerrada. Envie os logs atualizados.") from error
            print(f"Aguardando {labels[name]} terminar (limite de 20 minutos)...", flush=True)
            time.sleep(5)
    with stack:
        yield


class PermissaoPainel(RuntimeError):
    """Windows exige elevação para identificar/encerrar o painel desta instalação."""


def porta_ocupada() -> bool:
    with socket.socket() as sock:
        sock.settimeout(1)
        return sock.connect_ex(("127.0.0.1", 8765)) == 0


def parar_painel(root: Path) -> None:
    import psutil
    root = root.resolve()
    candidatos = []
    inacessiveis = False
    # Consultar cmdline de todo processo incluía serviços protegidos do Windows.
    # Primeiro filtre por nome; só depois leia os argumentos dos processos Python.
    for process in psutil.process_iter(["pid", "name"]):
        if not (process.info.get("name") or "").lower().startswith("python"):
            continue
        try:
            args = process.cmdline() or []
            if not any(args[i:i + 3] == ["-m", "seraph", "painel"] for i in range(len(args))):
                continue
            if Path(process.cwd()).resolve() != root:
                continue
            candidatos.append(process)
        except psutil.NoSuchProcess:
            continue
        except psutil.AccessDenied:
            inacessiveis = True
    for process in candidatos:
        try:
            process.terminate()
            process.wait(timeout=15)
        except psutil.NoSuchProcess:
            pass
        except psutil.AccessDenied as error:
            raise PermissaoPainel(
                "O Windows não permitiu encerrar o painel desta instalação. "
                "Ele pode ter sido aberto como administrador.") from error
        except psutil.TimeoutExpired as error:
            raise RuntimeError("O painel demorou para encerrar. Nenhum arquivo de código foi substituído; "
                               "aguarde e execute o atualizador novamente.") from error
    # Não ignorar AccessDenied cegamente: um painel elevado poderia continuar usando o código.
    if porta_ocupada():
        if inacessiveis:
            raise PermissaoPainel("O painel ainda responde na porta 8765, mas o Windows impediu "
                                 "a identificação de processos Python. É necessário conferir com permissão de administrador.")
        raise RuntimeError("A porta 8765 continua ocupada por um processo que não foi identificado como "
                           "o painel desta pasta. A atualização foi interrompida antes da troca do código.")


def administrador() -> bool:
    if os.name != "nt":
        return False
    import ctypes
    return bool(ctypes.windll.shell32.IsUserAnAdmin())


def elevar(root: Path) -> int:
    """Usa a confirmação padrão do Windows; não contorna nem aceita o UAC automaticamente."""
    env = {**os.environ,
           "VISUS_ELEVATE_PYTHON": str(root / ".venv/Scripts/python.exe"),
           "VISUS_ELEVATE_ARGS": subprocess.list2cmdline(
               [str(Path(__file__).resolve()), "--pasta", str(root), "--elevado"]),
           "VISUS_ELEVATE_ROOT": str(root)}
    command = ("$ErrorActionPreference='Stop'; try { "
               "$p=Start-Process -FilePath $env:VISUS_ELEVATE_PYTHON "
               "-ArgumentList $env:VISUS_ELEVATE_ARGS -WorkingDirectory $env:VISUS_ELEVATE_ROOT "
               "-Verb RunAs -PassThru; $p.WaitForExit(); exit $p.ExitCode "
               "} catch { Write-Host 'A permissao do Windows nao foi concedida ou a inicializacao falhou. "
               "Execute o atualizador novamente para tentar.'; exit 1 }")
    print("O painel pode estar elevado. O Windows solicitará permissão para continuar a atualização. "
          "Aguarde a conclusão; mantenha esta janela aberta.", flush=True)
    return subprocess.run(["powershell.exe", "-NoProfile", "-Command", command], env=env, check=False).returncode


def iniciar(root: Path) -> None:
    subprocess.Popen(["cmd.exe", "/c", str(root / "scripts/painel_servidor.bat")],
                     cwd=root, creationflags=subprocess.CREATE_NO_WINDOW)


def main(root: Path) -> None:
    root = root.resolve()
    if os.name != "nt" or not (root / ".venv/Scripts/python.exe").is_file() or not (root / "seraph").is_dir():
        raise RuntimeError("Execute no Windows, na pasta do Visus Clipper que contém painel.bat e .venv.")
    python = root / ".venv/Scripts/python.exe"
    print("Baixando e conferindo a atualização...", flush=True)
    try:
        manifest = json.loads(baixar("clipper/versao.json"))
    except OSError as error:
        raise RuntimeError("Não consegui falar com o site do Visus Clipper. Confira a internet e tente de novo; "
                           "nada foi alterado.") from error
    if manifest["arquivo"] != "download/VisusClipper.zip":
        raise RuntimeError("Endereço de pacote inesperado.")
    with tempfile.TemporaryDirectory(prefix="visus-atualizar-") as temp:
        stage = Path(temp)
        try:
            pacote = baixar(manifest["arquivo"])
        except OSError as error:
            raise RuntimeError("Não consegui baixar a versão nova. Confira a internet e tente de novo; "
                               "nada foi alterado.") from error
        files = preparar(pacote, manifest, stage)
        if aguardar_outro_atualizador(root, manifest["versao"]):
            print(f"A outra janela concluiu a atualização para {manifest['versao']}.", flush=True)
            return
        avisos = []
        with reter_publicacoes(root) as reter, livre(root, reter):
            # psutil identifica somente o painel desta pasta antes da troca de arquivos.
            pip(python, "install", "-q", "psutil==7.2.2")
            parar_painel(root)
            backup = root / "work" / "backup_atualizacao" / datetime.now().strftime("%Y%m%d_%H%M%S_%f")
            applied = False
            lista = None
            concluido = False
            try:
                for pending in sorted((root / "work/backup_atualizacao").glob("*/PENDENTE")):
                    print("Restaurando uma atualização interrompida...", flush=True)
                    restaurar(root, pending.parent)
                # Antes de mexer: a lista exata das bibliotecas atuais, para poder voltar.
                lista = congelar(python, backup / "bibliotecas.txt")
                avisos = instalar_dependencias(root, python, stage / "novo")
                aplicar(root, stage, files, backup)
                applied = True
                teste = subprocess.run([str(python), "-c", "from seraph.web.server import app; assert app"],
                                       cwd=root, capture_output=True, text=True, check=False)
                if teste.returncode != 0:
                    print((teste.stdout + teste.stderr)[-2000:], flush=True)   # para o log do suporte
                    raise RuntimeError("A versão nova não passou no teste do painel. Voltei para a versão "
                                       "anterior; nada foi perdido.")
                (root / "work/atualizar_pip.flag").unlink(missing_ok=True)
                iniciar(root)
                print("Abrindo o painel novo...", flush=True)
                if not painel_respondeu():
                    print("O painel novo não respondeu; voltando para a versão anterior...", flush=True)
                    parar_painel(root)
                    raise RuntimeError("A versão nova não conseguiu abrir o painel. Voltei para a versão "
                                       "anterior; nada foi perdido.")
                (backup / "PENDENTE").unlink(missing_ok=True)
                concluido = True
            except Exception:
                if applied:
                    restaurar(root, backup)
                voltar_bibliotecas(python, lista)
                raise
            finally:
                if not concluido:
                    iniciar(root)
            # Ocupa o mínimo de disco: só as cópias mais recentes do código anterior ficam.
            limpar_backups(root)
    print(f"Atualizado para {manifest['versao']}.", flush=True)
    for aviso in avisos:
        print(aviso, flush=True)
    print("Painel respondendo. Abra o painel e pressione Ctrl+F5.", flush=True)


def registrar_erro(root: Path, error: BaseException) -> None:
    """Detalhes técnicos vão para logs/atualizacao.log; na tela fica só a frase simples."""
    import traceback
    try:
        log = root / "logs" / "atualizacao.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        with log.open("a", encoding="utf-8") as saida:
            saida.write(f"{datetime.now():%Y-%m-%d %H:%M:%S} erro do atualizador:\n")
            saida.write("".join(traceback.format_exception(error)))
    except OSError:
        pass


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pasta", type=Path, required=True)
    parser.add_argument("--dependencias", action="store_true",
                        help="só confere e instala as bibliotecas e o navegador desta instalação")
    parser.add_argument("--elevado", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    try:
        if args.dependencias:
            pasta = args.pasta.resolve()
            for aviso in instalar_dependencias(pasta, pasta / ".venv/Scripts/python.exe", pasta,
                                               falha="Não consegui instalar as bibliotecas do Visus Clipper. "
                                                     "Confira a internet e tente de novo."):
                print(aviso, flush=True)
            sys.exit(0)
        try:
            main(args.pasta)
        except PermissaoPainel:
            if args.elevado or administrador():
                raise
            # main já liberou as travas e restaurou os horários antes de solicitar o UAC.
            sys.exit(elevar(args.pasta.resolve()))
    except Exception as error:
        registrar_erro(args.pasta, error)
        if isinstance(error, RuntimeError):
            print(f"Não foi possível concluir: {error}", file=sys.stderr)
        else:
            print("Não foi possível concluir a atualização por um erro inesperado. A versão anterior "
                  "continua instalada. Os detalhes ficaram no arquivo de registro da atualização "
                  "(pasta logs) para o suporte.", file=sys.stderr)
        sys.exit(1)
