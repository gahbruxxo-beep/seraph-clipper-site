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
    assert "VisusClipper/seraph/v2/src/PublisherService.js" in names
    assert "VisusClipper/seraph/v2/.env.example" in names
    assert "VisusClipper/Iniciar-V2.bat" in names
    assert not any("node_modules/" in name for name in names)
    for name in names:
        assert name.startswith("VisusClipper/") and ".." not in Path(name).parts
        assert not any(secret in name.lower() for secret in
                       ("painel.json", "rclone.conf", "contas.json", "senha_do_painel", ".env")
                       if not (secret == ".env" and Path(name).name == ".env.example"))
print("Pacote, versão, SHA-256 e caminhos conferidos.")


# O iniciador manual fixa o hash do auxiliar que será executado no PC.
import re
bootstrap = (root / "download/Atualizar-Clipper.bat").read_text(encoding="utf-8")
helper = re.search(r"download/(atualizar_instalacao_[a-f0-9]+\.py)", bootstrap).group(1)
expected_hash = re.search(r"-ne '([a-f0-9]{64})'", bootstrap).group(1)
assert hashlib.sha256((root / "download" / helper).read_bytes()).hexdigest() == expected_hash
print("Atualizador manual e hash do auxiliar conferidos.")
