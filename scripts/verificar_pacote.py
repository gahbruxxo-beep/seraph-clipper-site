"""Verifica a integridade e a estrutura do instalador publicado."""
import hashlib
import json
import re
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
    # Arquivos essenciais do uso comum.
    for essential in ("Instalar.bat", "painel.bat", "seraph/web/server.py",
                      "seraph/publicar/worker.py"):
        assert "VisusClipper/" + essential in names, essential
    # A V2 é opcional e vem desligada: pode ou não estar no pacote.
    # Se estiver, precisa vir completa (código e modelo de configuração).
    if any(name.startswith("VisusClipper/seraph/v2/") for name in names):
        assert "VisusClipper/seraph/v2/src/PublisherService.js" in names
        assert "VisusClipper/seraph/v2/.env.example" in names
    assert not any("node_modules/" in name for name in names)
    for name in names:
        assert name.startswith("VisusClipper/") and ".." not in Path(name).parts
        assert not any(secret in name.lower() for secret in
                       ("painel.json", "rclone.conf", "contas.json", "senha_do_painel", ".env")
                       if not (secret == ".env" and Path(name).name == ".env.example"))
print("Pacote, versão, SHA-256 e caminhos conferidos.")


# O iniciador manual fixa o hash do auxiliar que será executado no PC.
bootstrap = (root / "download/Atualizar-Clipper.bat").read_text(encoding="utf-8")
helper = re.search(r"download/(atualizar_instalacao_[a-f0-9]+\.py)", bootstrap).group(1)
expected_hash = re.search(r"-ne '([a-f0-9]{64})'", bootstrap).group(1)
assert hashlib.sha256((root / "download" / helper).read_bytes()).hexdigest() == expected_hash
print("Atualizador manual e hash do auxiliar conferidos.")

# Nenhum script antigo fica disponível para download: só o auxiliar em uso.
published_bats = "".join(p.read_text(encoding="utf-8", errors="replace")
                         for p in (root / "download").glob("*.bat"))
for script in (root / "download").glob("*.py"):
    assert "download/" + script.name in published_bats, (
        f"download/{script.name} não é usado por nenhum .bat publicado; apague antes de publicar.")

# Notas internas e contatos pessoais não vão para o site público.
assert not (root / "CONTINUIDADE.md").exists(), "CONTINUIDADE.md é nota interna; mantenha na fonte."
for page in list(root.glob("*.html")) + list((root / "download").glob("*.md")):
    text = page.read_text(encoding="utf-8", errors="replace")
    assert "gahbruxxo@" not in text, f"{page.name} usa e-mail pessoal; use visusclips@visusclipper.online."
    for internal in ("bot-profile", "enable-automation"):
        assert internal not in text, f"{page.name} cita automação de navegador ({internal})."
print("Downloads, notas internas e contatos conferidos.")
