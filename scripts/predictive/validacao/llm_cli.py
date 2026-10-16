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
MODELO_CODEX_PADRAO = None  # sem -m so no dry-run; execucao real exige modelo fixado (modelo_codex)
# Segundo rotulador: modelo FIXADO por variavel de usuario. argv_codex usa --ignore-user-config, entao o `model` do
# ~/.codex/config.toml NAO vale aqui; sem -m o Codex cairia no padrao embutido da versao do CLI, que muda sem aviso
# e quebra a reprodutibilidade do G1a. Ausente = execucao recusada (fail-closed).
VAR_MODELO_CODEX = "VIXRADAR_ROTULADOR_CODEX_MODELO"
# Cota: o Codex e o provider das rotinas de producao (VIXRADAR_LLM_PROVIDER=codex) e a assinatura divide a mesma
# janela de 5 h e o mesmo limite semanal entre uso local e nuvem. A segunda leitura so roda fora das janelas das
# rotinas (Sentinela 09h25-17h55, Matinal 10h, Verificacao 11h03 e 19h15, Noturna 18h, Agenda dom/qua 22h) e com
# nenhuma task VIXRadar-* em execucao. Brasil sem horario de verao desde 2019: BRT = UTC-3 fixo.
JANELA_CODEX_BRT = ((0, 30), (8, 30))  # [00h30, 08h30)
BRT = dt.timezone(dt.timedelta(hours=-3))
VAR_TOKEN = "VIXRADAR_ANTHROPIC_AUTH_TOKEN"
TIMEOUT_S = 1800
CWD_NEUTRO = os.path.join(tempfile.gettempdir(), "ews-rotulador-cwd")

_RX_LIMITE = re.compile(r"(?i)session limit|usage limit|hit your .*limit|rate_limit_error|api_error_status\"?\s*:\s*429|too many requests|overloaded")
_RX_AUTH = re.compile(r"(?i)OAuth session expired|Failed to authenticate|not authenticated|Not logged in|Please run /login|Invalid API key|authentication_error|invalid_api_key"
                      r"|Error authenticating|Authentication cancelled")  # Gemini CLI sem OAuth (medido 16/10 11:44)


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


def _var_usuario(nome):
    v = os.environ.get(nome)
    if v:
        return v
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as k:
            return winreg.QueryValueEx(k, nome)[0] or None
    except Exception:  # noqa: BLE001
        return None


def modelo_codex():
    """Modelo fixado do segundo rotulador, ou None (execucao real recusada)."""
    m = (_var_usuario(VAR_MODELO_CODEX) or "").strip()
    return m or None


def janela_codex_livre(agora_utc, tarefas_rodando):
    """Puro. (livre, motivo). agora_utc: datetime aware. tarefas_rodando: lista de nomes VIXRadar-* em execucao,
    ou None quando nao foi possivel consultar (fail-closed)."""
    h = agora_utc.astimezone(BRT)
    minuto = h.hour * 60 + h.minute
    ini, fim = JANELA_CODEX_BRT[0][0] * 60 + JANELA_CODEX_BRT[0][1], JANELA_CODEX_BRT[1][0] * 60 + JANELA_CODEX_BRT[1][1]
    if not (ini <= minuto < fim):
        return False, "fora da janela livre do Codex (%02dh%02d-%02dh%02d BRT), agora %s" % (
            JANELA_CODEX_BRT[0] + JANELA_CODEX_BRT[1] + (h.strftime("%H:%M"),))
    if tarefas_rodando is None:
        return False, "nao foi possivel consultar o Task Scheduler (fail-closed)"
    if tarefas_rodando:
        return False, "rotina em execucao: %s" % ", ".join(sorted(tarefas_rodando))
    return True, "livre"


def tarefas_vixradar_rodando():
    """Nomes das tasks VIXRadar-* em Running, ou None se a consulta falhar. State e enum, nao localizado."""
    try:
        p = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
                            "Get-ScheduledTask -TaskName 'VIXRadar-*' -ErrorAction Stop | Where-Object { $_.State -eq 'Running' } | ForEach-Object { $_.TaskName }"],
                           capture_output=True, timeout=60)
        if p.returncode != 0:
            return None
        return [x.strip() for x in p.stdout.decode("utf-8", "replace").splitlines() if x.strip()]
    except Exception:  # noqa: BLE001
        return None


def chamar_codex(prompt, sistema, esquema=None, modelo=MODELO_CODEX_PADRAO, timeout=TIMEOUT_S, executar=False):
    """Codex e o provider das rotinas: so executa com executar=True explicito. Sem isso devolve o argv (dry-run).
    Execucao real exige modelo fixado e janela livre; senao levanta LimiteDeCota (o chamador para e preserva o estado)."""
    if modelo and str(modelo).lower().startswith("claude"):
        raise ValueError("modelo Claude passado ao Codex: %r" % modelo)
    os.makedirs(CWD_NEUTRO, exist_ok=True)
    if executar:
        if not modelo:
            raise LimiteDeCota("modelo do Codex nao fixado: defina %s (escopo User)" % VAR_MODELO_CODEX)
        livre, motivo = janela_codex_livre(dt.datetime.now(dt.timezone.utc), tarefas_vixradar_rodando())
        if not livre:
            raise LimiteDeCota("janela do Codex fechada: %s" % motivo)
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


# ---------------------------------------------------------------------------------------------------------------
# Segundo rotulador configuravel (16/10/2026). O protocolo (G0-v2 item 4) pede segundo rotulador de OUTRO fornecedor
# ou humano, porque dois rotulos do mesmo fornecedor tem erro correlacionado e nao medem concordancia de verdade.
#   codex       OpenAI, assinatura ja paga. Padrao. Divide cota com as rotinas: so na janela livre.
#   gemini      Google, OAuth pessoal ja logado. Sem custo de API. Ferramentas negadas por politica (sem busca, sem
#               arquivo, sem shell). Disponibilidade nao verificada: a doc oficial diz que o Gemini CLI foi trocado
#               pelo Antigravity CLI em 18/06/2026 para contas gratuitas.
#   openrouter  Qualquer fornecedor (DeepSeek, Qwen, Mistral...). PAGO por token: exige autorizacao explicita.
#   claude      Mesmo fornecedor do primeiro: so com aceite explicito, e de preferencia com modelo diferente.
# A escolha (provider, modelo, teto) vive no arquivo de autorizacao do operador, ver rotular_etapa1.segundo_config.
PROVEDORES_SEGUNDO = ("codex", "gemini", "openrouter", "claude")
GEMINI_POLITICA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gemini_politica_rotulador.toml")
OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
VAR_OPENROUTER_KEY = "OPENROUTER_API_KEY"


def fornecedor(provider, modelo):
    """Fornecedor real do modelo, para a regra de independencia. openrouter usa o prefixo 'vendor/modelo'."""
    m = str(modelo or "").lower()
    if provider == "claude" or m.startswith("claude") or m.startswith("anthropic/"):
        return "anthropic"
    if provider == "codex":
        return "openai"
    if provider == "gemini":
        return "google"
    if provider == "openrouter" and "/" in m:
        return m.split("/", 1)[0]
    return provider


def argv_gemini(modelo, politica=GEMINI_POLITICA):
    """Headless, saida JSON, toda ferramenta negada por politica de nivel admin passada por arquivo (nao altera a
    configuracao do usuario). O prompt vai por stdin; -p so dispara o modo nao interativo."""
    import shutil
    exe = shutil.which("gemini") or "gemini"
    return [exe, "-m", modelo, "-o", "json", "--approval-mode", "default", "--admin-policy", politica,
            "-p", "Responda conforme as instrucoes acima."]


def interpretar_saida_gemini(stdout, stderr, exit_code):
    """Puro. `gemini -o json` devolve {"response": texto, "stats": {...}}; usage lido de stats.models.*.tokens quando
    existir (usage_mensuravel=False quando nao). Objeto JSON da resposta extraido do texto."""
    r = {"ok": False, "classe": None, "exit": exit_code, "structured": None, "result": None,
         "usage": {"input": 0, "output": 0, "cache_read": 0, "cache_creation": 0}, "usage_mensuravel": False, "modelos": []}
    s = (stdout or "").strip()
    j = None
    try:
        j = json.loads(s[s.index("{"):]) if "{" in s else None
    except Exception:  # noqa: BLE001
        j = None
    if not isinstance(j, dict) or exit_code != 0 or j.get("error"):
        r["classe"] = classificar_falha(" ".join([s, stderr or "", json.dumps((j or {}).get("error") or "")]))
        r["erro"] = (str((j or {}).get("error") or stderr or s) or "saida invalida")[:400]
        return r
    for nome, mod in ((j.get("stats") or {}).get("models") or {}).items():
        t = (mod or {}).get("tokens") or {}
        r["modelos"].append(nome)
        cached = int(t.get("cached") or 0)
        r["usage"]["input"] += max(0, int(t.get("prompt") or 0) - cached)
        r["usage"]["cache_read"] += cached
        r["usage"]["output"] += int(t.get("candidates") or 0) + int(t.get("thoughts") or 0)
        r["usage_mensuravel"] = True
    texto = str(j.get("response") or "")
    r["result"] = texto
    m = re.search(r"\{.*\}", texto, re.S)
    if m:
        try:
            r["structured"] = json.loads(m.group(0))
        except Exception:  # noqa: BLE001
            r["structured"] = None
    r["ok"] = r["structured"] is not None
    if not r["ok"]:
        r["classe"] = "transitoria"
        r["erro"] = "resposta sem objeto JSON"
    return r


def chamar_gemini(prompt, sistema, esquema=None, modelo=None, timeout=TIMEOUT_S, executar=False):
    if not modelo:
        raise LimiteDeCota("modelo do Gemini nao fixado (modelo_segundo na autorizacao)")
    os.makedirs(CWD_NEUTRO, exist_ok=True)
    argv = argv_gemini(modelo)
    texto = sistema + "\n\nNao use ferramentas. Responda com UM unico objeto JSON" + (
        " neste esquema: %s" % json.dumps(esquema, ensure_ascii=False) if esquema else "") + "\n\n" + prompt
    base = {"provider": "gemini", "modelo": modelo, "sha256_prompt": sha256_texto(texto), "chars_prompt": len(texto)}
    if not executar:
        return dict(base, ok=False, classe="dry_run", argv=argv)
    if not os.path.exists(GEMINI_POLITICA):
        raise LimiteDeCota("politica de negacao de ferramentas ausente: %s" % GEMINI_POLITICA)
    t0 = dt.datetime.now(dt.timezone.utc)
    try:
        p = subprocess.run(argv, input=texto.encode("utf-8"), capture_output=True, timeout=timeout, cwd=CWD_NEUTRO)
        out, err, code = p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace"), p.returncode
    except subprocess.TimeoutExpired:
        out, err, code = "", "timeout apos %ss" % timeout, 124
    r = interpretar_saida_gemini(out, err, code)
    r.update(base)
    r.update({"inicio_utc": t0.isoformat(timespec="seconds"), "segundos": round((dt.datetime.now(dt.timezone.utc) - t0).total_seconds(), 1),
              "sha256_resposta": sha256_texto(out), "stderr_cauda": (err or "")[-300:]})
    return r


def interpretar_saida_openrouter(corpo, status):
    """Puro. Corpo JSON de chat/completions -> resultado normalizado. 402 = sem credito (limite)."""
    r = {"ok": False, "classe": None, "exit": status, "structured": None, "result": None,
         "usage": {"input": 0, "output": 0, "cache_read": 0, "cache_creation": 0}, "usage_mensuravel": False, "modelos": []}
    try:
        j = json.loads(corpo or "")
    except Exception:  # noqa: BLE001
        j = None
    if status in (401, 403):
        r.update(classe="auth", erro="HTTP %s" % status)
        return r
    if status in (402, 429):
        r.update(classe="limite", erro="HTTP %s (credito ou limite)" % status)
        return r
    if status != 200 or not isinstance(j, dict) or not j.get("choices"):
        r.update(classe="transitoria", erro=("HTTP %s " % status) + str((j or {}).get("error") or "")[:300])
        return r
    u = j.get("usage") or {}
    cached = int(((u.get("prompt_tokens_details") or {}).get("cached_tokens")) or 0)
    r["usage"] = {"input": max(0, int(u.get("prompt_tokens") or 0) - cached), "output": int(u.get("completion_tokens") or 0),
                  "cache_read": cached, "cache_creation": 0}
    r["usage_mensuravel"] = bool(u)
    r["modelos"] = [j.get("model")] if j.get("model") else []
    texto = str(((j["choices"][0] or {}).get("message") or {}).get("content") or "")
    r["result"] = texto
    m = re.search(r"\{.*\}", texto, re.S)
    if m:
        try:
            r["structured"] = json.loads(m.group(0))
        except Exception:  # noqa: BLE001
            r["structured"] = None
    r["ok"] = r["structured"] is not None
    if not r["ok"]:
        r.update(classe="transitoria", erro="resposta sem objeto JSON")
    return r


def chamar_openrouter(prompt, sistema, esquema=None, modelo=None, timeout=TIMEOUT_S, executar=False):
    """Chave lida do ambiente/registro User, so no header da requisicao. Nunca em argv, log ou registro."""
    if not modelo or "/" not in str(modelo):
        raise LimiteDeCota("modelo do OpenRouter nao fixado no formato fornecedor/modelo")
    corpo = {"model": modelo, "temperature": 0, "response_format": {"type": "json_object"},
             "messages": [{"role": "system", "content": sistema + "\n\nResponda com UM unico objeto JSON" + (
                 " neste esquema: %s" % json.dumps(esquema, ensure_ascii=False) if esquema else "")},
                 {"role": "user", "content": prompt}]}
    dados = json.dumps(corpo, ensure_ascii=False).encode("utf-8")
    base = {"provider": "openrouter", "modelo": modelo, "sha256_prompt": sha256_texto(prompt), "chars_prompt": len(prompt)}
    if not executar:
        return dict(base, ok=False, classe="dry_run", argv=["POST", OPENROUTER_URL])
    chave = _var_usuario(VAR_OPENROUTER_KEY)
    if not chave:
        raise LimiteDeCota("%s ausente" % VAR_OPENROUTER_KEY)
    import urllib.error
    import urllib.request
    req = urllib.request.Request(OPENROUTER_URL, data=dados, method="POST",
                                 headers={"Authorization": "Bearer " + chave, "Content-Type": "application/json"})
    t0 = dt.datetime.now(dt.timezone.utc)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            status, txt = resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        status, txt = e.code, e.read().decode("utf-8", "replace")
    except Exception as e:  # noqa: BLE001
        status, txt = 0, type(e).__name__
    r = interpretar_saida_openrouter(txt, status)
    r.update(base)
    r.update({"inicio_utc": t0.isoformat(timespec="seconds"), "segundos": round((dt.datetime.now(dt.timezone.utc) - t0).total_seconds(), 1),
              "sha256_resposta": sha256_texto(txt)})
    return r


def chamar(prompt, sistema, esquema=None, provider="claude", modelo=None, **kw):
    if provider == "claude":
        kw.pop("executar", None)
        return chamar_claude(prompt, sistema, esquema, modelo or MODELO_PADRAO, **kw)
    if modelo and str(modelo).lower().startswith("claude"):
        modelo = None  # padrao Claude herdado de rotular(): resolve para o modelo fixado do segundo rotulador
    if provider == "codex":
        return chamar_codex(prompt, sistema, esquema, modelo or modelo_codex() or MODELO_CODEX_PADRAO, **kw)
    # gemini e openrouter: rotular() so chega aqui fora do dry-run, entao executar e o padrao
    if provider == "gemini":
        return chamar_gemini(prompt, sistema, esquema, modelo or modelo_segundo(), executar=kw.pop("executar", True), **kw)
    if provider == "openrouter":
        return chamar_openrouter(prompt, sistema, esquema, modelo or modelo_segundo(), executar=kw.pop("executar", True), **kw)
    raise ValueError("provider desconhecido: %r" % provider)


VAR_MODELO_SEGUNDO = "VIXRADAR_ROTULADOR_SEGUNDO_MODELO"


def modelo_segundo():
    """Modelo do segundo rotulador nao-Codex, posto no processo por rotular_etapa1 a partir da autorizacao."""
    m = (os.environ.get(VAR_MODELO_SEGUNDO) or "").strip()
    return m or None


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
