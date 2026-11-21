"""Verifica a integridade e a estrutura do instalador publicado."""
import hashlib
import json
from pathlib import Path
from zipfile import ZipFile

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / "clipper/versao.json").read_text(encoding="utf-8"))
archive = root / manifest["arquivo"]
assert hashlib.sha256(archive.read_bytes()).hexdigest() == manifest["sha256"]
with ZipFile(archive) as package:
    assert package.testzip() is None
    assert package.read("VisusClipper/VERSAO").decode().strip() == manifest["versao"]
    origin = json.loads(package.read("VisusClipper/ORIGEM.json"))
    assert origin["commit"] == manifest["commit"]
    assert origin["versao"] == manifest["versao"]
    names = package.namelist()
    assert "VisusClipper/seraph/publicar/meta_navegador.py" in names
    for name in names:
        assert name.startswith("VisusClipper/") and ".." not in Path(name).parts
        assert not any(secret in name.lower() for secret in
                       ("painel.json", "rclone.conf", "contas.json", "senha_do_painel", ".env"))
print("Pacote, versão, SHA-256 e caminhos conferidos.")
