"""Camada unica de invocacao de modelo para a rotulagem (G0-v3). Sem rede propria: delega ao CLI.

Primeiro rotulador (Claude): `claude -p` headless, modo assinatura-token das rotinas (TOKENVAR1,
vixradar-claude-auth.ps1): o token longevo de `claude setup-token` vive na variavel de usuario
VIXRADAR_ANTHROPIC_AUTH_TOKEN e entra no processo filho como CLAUDE_CODE_OAUTH_TOKEN. O valor nunca
aparece em argumento, log, registro ou excecao. ANTHROPIC_BASE_URL e fixado na API oficial e toda chave
paga ou alias de modelo e removido do ambiente do filho (ANTHROPIC_API_PAYG = NAO AUTORIZADO).

Isolamento do rotulador: --system-prompt proprio (substitui o do Claude Code), --setting-sources vazio
(nenhum CLAUDE.md, skill ou hook), --tools vazio (sem busca, sem shell, sem leitura de arquivo),
--disable-slash-commands, --no-session-persistence, cwd neutro. O modelo so ve o que o prompt traz.

Segundo rotulador (Codex): `codex exec --json` read-only, mesmo padrao das rotinas MENOS --search (o
rotulador nao busca). Implementado e testavel por argv; a execucao real so acontece quando o chamador
passa provider="codex" explicitamente, porque o Codex e o provider das rotinas operacionais hoje.

Registro: cada chamada vira uma linha JSON (so acrescenta) com sha256 e tamanho do prompt, modelo, usage,
classe de falha, duracao e sha256 da resposta. Nunca o token, nunca o ambiente.
"""
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile

MODELO_PADRAO = "claude-sonnet-5-5"
MODELO_CODEX_PADRAO = None  # sem -m: modelo padrao da config do Codex, como nas rotinas (rotulado 'codex-subscription')
VAR_TOKEN = "VIXRADAR_ANTHROPIC_AUTH_TOKEN"
TIMEOUT_S = 1800
CWD_NEUTRO = os.path.join(tempfile.gettempdir(), "ews-rotulador-cwd")

_RX_LIMITE = re.compile(r"(?i)session limit|usage limit|hit your .*limit|rate_limit_error|api_error_status\"?\s*:\s*429|too many requests|overloaded")
_RX_AUTH = re.compile(r"(?i)OAuth session expired|Failed to authenticate|not authenticated|Not logged in|Please run /login|Invalid API key|authentication_error|invalid_api_key")


def sha256_texto(s):
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def token_usuario():
    """Token longevo lido do processo ou do registro User. Devolve None se ausente. Nunca imprimir."""
    t = os.environ.get(VAR_TOKEN)
    if t:
        return t
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as k:
            v, _ = winreg.QueryValueEx(k, VAR_TOKEN)
            return v or None
    except Exception:  # noqa: BLE001
        return None


def ambiente_claude(token=None):
    """Ambiente do filho: token longevo em CLAUDE_CODE_OAUTH_TOKEN, API oficial, sem chave paga, sem alias."""
    env = dict(os.environ)
    for v in ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL",
              "ANTHROPIC_DEFAULT_HAIKU_MODEL", "ANTHROPIC_DEFAULT_OPUS_MODEL", "CLAUDE_CODE_SUBAGENT_MODEL",
              "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_OAUTH_TOKEN"):
        env.pop(v, None)
    env["ANTHROPIC_BASE_URL"] = "https://api.anthropic.com"
    tok = token if token is not None else token_usuario()
    if tok:
        env["CLAUDE_CODE_OAUTH_TOKEN"] = tok
    return env


def argv_claude(modelo, sistema, esquema=None, ferramentas="", add_dir=None):
    a = ["claude", "-p", "--model", modelo, "--output-format", "json", "--no-session-persistence",
         "--tools", ferramentas, "--setting-sources", "", "--disable-slash-commands",
         "--exclude-dynamic-system-prompt-sections", "--system-prompt", sistema]
    if add_dir:
        a += ["--add-dir", add_dir, "--permission-mode", "bypassPermissions"]
    if esquema is not None:
        a += ["--json-schema", json.dumps(esquema, ensure_ascii=False, separators=(",", ":"))]
    return a


def argv_codex(modelo, saida_ultima):
    base = ["-c", "features.skip_host_skill_discovery=true", "-c", "skills.include_instructions=false",
            "-c", "include_permissions_instructions=false", "-c", "include_apps_instructions=false",
            "-c", "features.plugins=false", "-c", "features.apps=false", "-c", "features.tool_suggest=false",
            "-c", "features.remote_plugin=false", "-c", "features.recommended_plugins=false"]
    return (["codex"] + base + (["-m", modelo] if modelo else []) + ["exec", "--json", "--ephemeral", "--sandbox", "read-only",
                                "--ignore-user-config", "--ignore-rules", "--skip-git-repo-check",
                                "-C", CWD_NEUTRO, "-o", saida_ultima, "-"])


def classificar_falha(texto):
    if not texto:
        return "transitoria"
    if _RX_LIMITE.search(texto):
        return "limite"
    if _RX_AUTH.search(texto):
        return "auth"
    return "transitoria"


def _usage_claude(j):
    u = (j or {}).get("usage") or {}
    return {"input": int(u.get("input_tokens") or 0), "output": int(u.get("output_tokens") or 0),
            "cache_read": int(u.get("cache_read_input_tokens") or 0),
            "cache_creation": int(u.get("cache_creation_input_tokens") or 0)}


def total_tokens(usage):
    return usage["input"] + usage["output"] + usage["cache_read"] + usage["cache_creation"]


def interpretar_saida_claude(stdout, stderr, exit_code):
    """Puro. Transforma stdout/stderr/exit do `claude -p --output-format json` no resultado normalizado."""
    r = {"ok": False, "classe": None, "exit": exit_code, "structured": None, "result": None,
         "usage": {"input": 0, "output": 0, "cache_read": 0, "cache_creation": 0}, "modelos": [],
         "duration_ms": None, "erro": None}
    j = None
    s = (stdout or "").strip()
    try:
        j = json.loads(s) if s.startswith("{") else None
    except Exception:  # noqa: BLE001
        j = None
    if j is None:
        r["classe"] = classificar_falha((stdout or "") + " " + (stderr or ""))
        r["erro"] = "saida nao e JSON (exit %s)" % exit_code
        return r
    r["usage"] = _usage_claude(j)
    r["modelos"] = sorted((j.get("modelUsage") or {}).keys())
    r["duration_ms"] = j.get("duration_ms")
    r["result"] = j.get("result")
    r["structured"] = j.get("structured_output")
    if j.get("is_error") or exit_code != 0:
        txt = " ".join(str(x) for x in (j.get("result"), j.get("api_error_status"), stderr) if x)
        r["classe"] = classificar_falha(txt)
        if str(j.get("api_error_status")) == "429":
            r["classe"] = "limite"
        r["erro"] = (str(j.get("result")) or "erro sem texto")[:400]
        return r
    r["ok"] = True
    return r


def chamar_claude(prompt, sistema, esquema=None, modelo=MODELO_PADRAO, ferramentas="", add_dir=None,
                  timeout=TIMEOUT_S, cwd=None):
    os.makedirs(CWD_NEUTRO, exist_ok=True)
    t0 = dt.datetime.now(dt.timezone.utc)
    try:
        p = subprocess.run(argv_claude(modelo, sistema, esquema, ferramentas, add_dir), input=prompt.encode("utf-8"),
                           capture_output=True, timeout=timeout, env=ambiente_claude(), cwd=cwd or CWD_NEUTRO)
        out, err, code = p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace"), p.returncode
    except subprocess.TimeoutExpired:
        out, err, code = "", "timeout apos %ss" % timeout, 124
    r = interpretar_saida_claude(out, err, code)
    r.update({"provider": "claude", "modelo": modelo, "inicio_utc": t0.isoformat(timespec="seconds"),
              "segundos": round((dt.datetime.now(dt.timezone.utc) - t0).total_seconds(), 1),
              "sha256_prompt": sha256_texto(prompt), "chars_prompt": len(prompt),
              "sha256_resposta": sha256_texto(out), "stderr_cauda": (err or "")[-300:]})
    return r


def interpretar_saida_codex(jsonl, ultima_msg):
    """Puro. Soma usage dos eventos `turn.completed` (input_tokens ja inclui cached) e devolve a ultima mensagem."""
    usage = {"input": 0, "output": 0, "cache_read": 0, "cache_creation": 0}
    eventos = 0
    for ln in (jsonl or "").splitlines():
        ln = ln.strip()
        if not ln.startswith("{"):
            continue
        try:
            o = json.loads(ln)
        except Exception:  # noqa: BLE001
            continue
        u = o.get("usage") if isinstance(o, dict) else None
        if not isinstance(u, dict) or "input_tokens" not in u:
            continue
        eventos += 1
        usage["input"] += int(u.get("input_tokens") or 0)
        usage["output"] += int(u.get("output_tokens") or 0)
        usage["cache_read"] += int(u.get("cached_input_tokens") or u.get("cache_read_input_tokens") or 0)
    structured = None
    s = (ultima_msg or "").strip()
    m = re.search(r"\{.*\}", s, re.S)
    if m:
        try:
            structured = json.loads(m.group(0))
        except Exception:  # noqa: BLE001
            structured = None
    return {"ok": structured is not None, "classe": None if structured is not None else classificar_falha(jsonl),
            "structured": structured, "result": s, "usage": usage, "usage_mensuravel": eventos > 0, "modelos": []}


def chamar_codex(prompt, sistema, esquema=None, modelo=MODELO_CODEX_PADRAO, timeout=TIMEOUT_S, executar=False):
    """Codex e o provider das rotinas: so executa com executar=True explicito. Sem isso devolve o argv (dry-run)."""
    os.makedirs(CWD_NEUTRO, exist_ok=True)
    saida = os.path.join(CWD_NEUTRO, "codex_ultima_%d.txt" % os.getpid())
    argv = argv_codex(modelo, saida)
    texto = sistema + "\n\nResponda com UM unico objeto JSON" + (" neste esquema: %s" % json.dumps(esquema, ensure_ascii=False) if esquema else "") + "\n\n" + prompt
    if not executar:
        return {"ok": False, "classe": "dry_run", "argv": argv, "sha256_prompt": sha256_texto(texto), "chars_prompt": len(texto),
                "provider": "codex", "modelo": modelo or "codex-subscription"}
    t0 = dt.datetime.now(dt.timezone.utc)
    p = subprocess.run(argv, input=texto.encode("utf-8"), capture_output=True, timeout=timeout, cwd=CWD_NEUTRO)
    ultima = open(saida, encoding="utf-8", errors="replace").read() if os.path.exists(saida) else ""
    r = interpretar_saida_codex(p.stdout.decode("utf-8", "replace"), ultima)
    r.update({"provider": "codex", "modelo": modelo, "exit": p.returncode, "inicio_utc": t0.isoformat(timespec="seconds"),
              "segundos": round((dt.datetime.now(dt.timezone.utc) - t0).total_seconds(), 1),
              "sha256_prompt": sha256_texto(texto), "chars_prompt": len(texto),
              "sha256_resposta": sha256_texto(ultima), "stderr_cauda": p.stderr.decode("utf-8", "replace")[-300:]})
    return r


def chamar(prompt, sistema, esquema=None, provider="claude", modelo=None, **kw):
    if provider == "claude":
        return chamar_claude(prompt, sistema, esquema, modelo or MODELO_PADRAO, **kw)
    if provider == "codex":
        return chamar_codex(prompt, sistema, esquema, modelo or MODELO_CODEX_PADRAO, **kw)
    raise ValueError("provider desconhecido: %r" % provider)


def registrar(caminho, registro):
    """Append-only. Nunca grava token nem ambiente: so o que o chamador devolveu."""
    reg = {k: v for k, v in registro.items() if k not in ("argv",)}
    reg["registrado_em"] = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    with open(caminho, "a", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(reg, ensure_ascii=False, default=str) + "\n")


class LimiteDeCota(RuntimeError):
    """Cota da assinatura esgotada ou credencial recusada: o chamador para e preserva o estado."""


if __name__ == "__main__":
    print(json.dumps({"modelo_padrao": MODELO_PADRAO, "token_presente": bool(token_usuario()),
                      "argv_exemplo": argv_claude(MODELO_PADRAO, "S", {"type": "object"})}, ensure_ascii=False, indent=1))
    sys.exit(0)
