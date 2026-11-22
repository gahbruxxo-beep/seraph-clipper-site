"""Atualiza uma instalação existente, incluindo checkouts Git, com backup local."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
import zipfile
from contextlib import ExitStack, contextmanager
from datetime import datetime
from pathlib import Path, PurePosixPath

SITE = "https://visusclipper.online/"
ROOT_FILES = {"requirements.txt", "VERSAO", "ORIGEM.json", "LEIA-ME.txt"}


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


@contextmanager
def livre(root: Path):
    """Espera até dois minutos por tarefas em andamento, sem interrompê-las."""
    deadline = time.monotonic() + 120
    while True:
        stack = ExitStack()
        try:
            for name in ("atualizacao.lock", "fila.lock", "publicar.lock"):
                path = root / "work" / name
                path.parent.mkdir(parents=True, exist_ok=True)
                handle = stack.enter_context(path.open("a+b"))
                handle.seek(0)
                if os.name == "nt":
                    import msvcrt
                    msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except OSError:
            stack.close()
            if time.monotonic() >= deadline:
                raise RuntimeError("Há processamento ou publicação em andamento. Aguarde concluir e execute novamente.")
            print("Aguardando o processamento e as publicações terminarem...", flush=True)
            time.sleep(5)
    with stack:
        yield


def parar_painel(root: Path) -> None:
    import psutil
    for process in psutil.process_iter(["pid", "cmdline"]):
        try:
            args = process.info["cmdline"] or []
            if not any(args[i:i + 3] == ["-m", "seraph", "painel"] for i in range(len(args))):
                continue
            if Path(process.cwd()).resolve() != root:
                continue
            process.terminate()
            process.wait(timeout=15)
        except psutil.NoSuchProcess:
            pass


def iniciar(root: Path) -> None:
    subprocess.Popen(["cmd.exe", "/c", str(root / "scripts/painel_servidor.bat")],
                     cwd=root, creationflags=subprocess.CREATE_NO_WINDOW)


def main(root: Path) -> None:
    root = root.resolve()
    if os.name != "nt" or not (root / ".venv/Scripts/python.exe").is_file() or not (root / "seraph").is_dir():
        raise RuntimeError("Execute no Windows, na pasta do Visus Clipper que contém painel.bat e .venv.")
    python = root / ".venv/Scripts/python.exe"
    print("Baixando e conferindo a atualização...", flush=True)
    manifest = json.loads(baixar("clipper/versao.json"))
    if manifest["arquivo"] != "download/VisusClipper.zip":
        raise RuntimeError("Endereço de pacote inesperado.")
    with tempfile.TemporaryDirectory(prefix="visus-atualizar-") as temp:
        stage = Path(temp)
        files = preparar(baixar(manifest["arquivo"]), manifest, stage)
        with livre(root):
            # psutil identifica somente o painel desta pasta antes da troca de arquivos.
            subprocess.run([str(python), "-m", "pip", "install", "--disable-pip-version-check",
                            "psutil==7.2.2"], check=True)
            parar_painel(root)
            for pending in sorted((root / "work/backup_atualizacao").glob("*/PENDENTE")):
                print("Restaurando uma atualização interrompida...", flush=True)
                restaurar(root, pending.parent)
            backup = root / "work" / "backup_atualizacao" / datetime.now().strftime("%Y%m%d_%H%M%S_%f")
            applied = False
            try:
                subprocess.run([str(python), "-m", "pip", "install", "--disable-pip-version-check",
                                "-r", str(stage / "novo/requirements.txt")], check=True)
                aplicar(root, stage, files, backup)
                applied = True
                subprocess.run([str(python), "-c", "from seraph.web.server import app; assert app"],
                               cwd=root, check=True)
                (root / "work/atualizar_pip.flag").unlink(missing_ok=True)
                (backup / "PENDENTE").unlink(missing_ok=True)
            except Exception:
                if applied:
                    restaurar(root, backup)
                raise
            finally:
                iniciar(root)
            print(f"Atualizado para {manifest['versao']}.", flush=True)
            print(f"Código anterior preservado em {backup}", flush=True)
    for _ in range(30):
        try:
            with urllib.request.urlopen("http://127.0.0.1:8765/api/config-login", timeout=2) as response:
                if response.status == 200:
                    print("Painel respondendo. Abra o painel e pressione Ctrl+F5.")
                    return
        except OSError:
            pass
        time.sleep(2)
    raise RuntimeError("Arquivos atualizados, mas o painel não respondeu. Confira logs/painel.log.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pasta", type=Path, required=True)
    try:
        main(parser.parse_args().pasta)
    except Exception as error:
        print(f"Não foi possível concluir: {error}", file=sys.stderr)
        sys.exit(1)
