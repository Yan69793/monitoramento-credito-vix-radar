"""Rotina semanal do pacote EWS 2.0 para o GitHub Actions (EWS2PUB1). Mesmo caminho da rotina do Windows
(scripts/run_vixradar_ews2_pacote.ps1), em Python puro e sem token Cloudflare: publica pelo Worker, com a ROUTINE_API_KEY.

Fluxo, cada passo fail-closed, mesmos codigos de saida da rotina do Windows:
  1. backtest de referencia com sha256 pinado (decide QUAIS sinais aparecem); hash diferente = exit 2
  2. T = ultimo dia util anterior a hoje (calendario do ews2), salvo --T
  3. atualizar_dados.py: baixa IPE, DFP, ITR, FCA, COTAHIST, cadastro e Selic; fonte velha = exit 2
  4. gerar_payload.py gera o pacote; falha = exit 3
  5. validar_pacote.mjs valida pela regua do adaptador do Worker; reprovou = exit 4 e NADA e enviado
  6. so com --publicar: POST ews2_publicar (o Worker revalida e guarda o anterior); 5 = envio falhou, 6 = releitura nao confirmou
  7. registra o pacote no livro de previsoes (exit 11 se falhar) e confere contra eventos reais (conferencia.py)
  8. veredito desligar: 14 na primeira rodada (aguarda confirmacao), na segunda POST ews2_flag_desligar e exit 9 (13 se falhar)
Sem --publicar e dry-run: nada e enviado ao Worker, nada entra no livro, a flag nunca e tocada.

Segredo: ROUTINE_API_KEY so por variavel de ambiente. O corpo do POST vai por arquivo temporario (curl --data-binary @arq), nunca
na linha de comando. Python urllib toma 403 do Cloudflare nesta API, por isso curl.

Uso: python -I rodar_ci.py [--publicar] [--T AAAA-MM-DD] [--saida-dir DIR]
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import subprocess
import sys
import tempfile

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import conferencia as C  # noqa: E402

BASE = os.path.abspath(os.path.join(AQUI, "..", "..", ".."))
API_PADRAO = "https://api.vixradar.com"
BACKTEST_PADRAO = os.path.join(BASE, "data", "validacao", "g0v4", "backtest_real_v3_20261018.json")
BACKTEST_SHA256 = "8dcdba69d36cf7aba3c6df74f4da9f5765c0e7e8544bd725dc7864e16c73ec61"
N_EMISSORES = 104
ESTADO_PADRAO = os.path.join(BASE, "data", "ews2-conferencia", "estado_conferencia.json")   # fora do livro: ler_livro le todo .json de la


def log(msg):
    print("[%s] %s" % (dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S"), msg), flush=True)


class Parar(Exception):
    def __init__(self, codigo, motivo):
        super().__init__(motivo)
        self.codigo, self.motivo = codigo, motivo


def sha_arquivo(p):
    with open(p, "rb") as fh:
        return hashlib.sha256(fh.read().replace(b"\r\n", b"\n")).hexdigest()


def comando(argv, timeout, cwd=BASE):
    try:
        r = subprocess.run(argv, cwd=cwd, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return 124, "", "timeout apos %ds" % timeout
    except OSError as e:
        return 127, "", str(e)
    return r.returncode, r.stdout.decode("utf-8", "replace"), r.stderr.decode("utf-8", "replace")


def json_da_saida(texto):
    for ln in reversed((texto or "").strip().splitlines()):
        ln = ln.strip()
        if ln.startswith("{"):
            try:
                return json.loads(ln)
            except ValueError:
                continue
    return None


def postar_curl(url, corpo, chave):
    """POST JSON com curl. O corpo (que leva a chave) vai por arquivo temporario. Devolve (http, json|None)."""
    corpo = dict(corpo, routine_key=chave)
    fd, caminho = tempfile.mkstemp(suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(corpo, fh, ensure_ascii=False)
        argv = ["curl", "-sS", "-m", "120", "-X", "POST", "-H", "Content-Type: application/json", "-w", "\n__HTTP=%{http_code}",
                "--data-binary", "@" + caminho, url]
        cod, out, err = comando(argv, 150)
    finally:
        try:
            os.remove(caminho)
        except OSError:
            pass
    http = None
    if "__HTTP=" in out:
        corpo_resp, _, h = out.rpartition("__HTTP=")
        out = corpo_resp
        http = int(h.strip() or 0)
    try:
        j = json.loads(out)
    except ValueError:
        j = None
    return http, j


def hoje_brt():
    """Data de hoje em Brasilia. O cron roda terca 02:15 UTC, que ainda e segunda 23:15 em Brasilia: T tem que ser a sexta."""
    return (dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=3)).date()


def ultimo_dia_util_anterior(hoje):
    import calendario as CAL
    d = hoje - dt.timedelta(days=1)
    while not CAL.dia_util(d):
        d -= dt.timedelta(days=1)
    return d


def executar(a, post=None, hoje=None):
    """Roda o fluxo. Devolve (exit, resultado). `post(url, corpo)` e injetavel (testes)."""
    res = {"modo": "publicar" if a.publicar else "dry-run", "T": None, "exit": 1, "ok": False, "motivo": None}
    hoje = hoje or hoje_brt()
    chave = os.environ.get("ROUTINE_API_KEY", "")
    if post is None:
        if a.publicar and not chave:
            return 2, dict(res, exit=2, motivo="ROUTINE_API_KEY ausente no ambiente")
        post = lambda url, corpo: postar_curl(url, corpo, chave)  # noqa: E731
    os.makedirs(a.saida_dir, exist_ok=True)
    try:
        if a.pacote_pronto:
            pacote = a.pacote_pronto
            if not os.path.exists(pacote):
                raise Parar(2, "pacote pronto ausente: " + pacote)
            T = a.T or C._json(pacote, "utf-8-sig")["data_observacao"]
        else:
            if not os.path.exists(a.backtest):
                raise Parar(2, "backtest de referencia ausente: " + a.backtest)
            sha = sha_arquivo(a.backtest)
            if sha != a.backtest_sha256.lower():
                raise Parar(2, "sha256 do backtest diverge do pinado: " + sha)
            log("BACKTEST: %s sha256=%s" % (a.backtest, sha))
            T = a.T or ultimo_dia_util_anterior(hoje).isoformat()
        res["T"] = T
        log("T: " + T)

        if not a.pacote_pronto:
            argv = [sys.executable, "-I", os.path.join(AQUI, "atualizar_dados.py"), "--T", T]
            if a.sem_download:
                argv.append("--sem-download")
            cod, out, err = comando(argv, a.dados_timeout)
            dj = json_da_saida(out)
            res["dados"] = dj
            log("DADOS: exit=%s %s" % (cod, (out.strip().splitlines() or [""])[-1][:400]))
            if cod != 0 or not dj or dj.get("ok") is not True:
                raise Parar(2, "dados velhos ou indisponiveis, nada gerado: %s" % ((dj or {}).get("motivo") or err[-300:]))
            pacote = os.path.join(a.saida_dir, "ews2_latest.json")
            argv = [sys.executable, "-I", os.path.join(AQUI, "gerar_payload.py"), "--backtest", a.backtest, "--saida", pacote, "--T", T]
            cod, out, err = comando(argv, a.gerar_timeout)
            log("GERAR: exit=%s %s" % (cod, (out.strip().splitlines() or [""])[-1][:300]))
            if cod != 0 or not os.path.exists(pacote):
                raise Parar(3, "gerar_payload falhou: " + (err or out)[-400:])
        res["pacote"] = pacote
        res["pacote_sha256"] = sha_arquivo(pacote)

        cod, out, err = comando(["node", os.path.join(AQUI, "integracao", "validar_pacote.mjs"), pacote, "--n", str(N_EMISSORES), "--T", T], 60)
        vj = json_da_saida(out)
        res["validacao"] = vj
        log("VALIDAR: exit=%s %s" % (cod, out.strip()[:300]))
        if cod != 0 or not vj or vj.get("ok") is not True:
            raise Parar(4, "pacote reprovado, NADA enviado: " + ("; ".join(vj.get("erros", [])) if vj else err[-200:]))

        pacote_obj = C._json(pacote, "utf-8-sig")
        if a.publicar:
            http, j = post(a.api + "/", {"action": "ews2_publicar", "pacote": pacote_obj})
            log("PUBLICAR: http=%s %s" % (http, json.dumps(j, ensure_ascii=False)[:300] if j else None))
            if http != 200 or not j:
                raise Parar(5, "publicacao falhou: http=%s %s" % (http, (j or {}).get("erros") or (j or {}).get("erro")))
            if j.get("ok") is not True or j.get("releitura_confere") is not True:
                raise Parar(6, "gravado mas releitura nao confirmou: %s" % j)
            res["publicado"] = {k: j.get(k) for k in ("gerado_em", "data_observacao", "emissores", "anterior")}
            try:
                res["livro"] = C.registrar(pacote, a.livro, a.historico)
            except Exception as e:  # noqa: BLE001
                raise Parar(11, "pacote publicado, mas o registro no livro de previsoes falhou: %s" % e)
            log("LIVRO: %s" % res["livro"].get("arquivo"))
        else:
            log("DRYRUN: pacote valido, SERIA publicado. Nada enviado ao Worker, nada no livro.")

        if not a.sem_conferencia:
            conferir(a, post, res, T)
        res["ok"], res["exit"] = True, 0
        return 0, res
    except Parar as p:
        res["exit"], res["motivo"] = p.codigo, p.motivo
        log("FIM: FALHA exit=%d motivo=%s" % (p.codigo, p.motivo))
        return p.codigo, res


def conferir(a, post, res, T):
    try:
        crit = C.ler_criterios()
    except SystemExit as e:
        raise Parar(12, "conferencia recusou rodar: %s" % e)
    snaps = C.ler_livro(a.livro)
    if not snaps:
        if a.publicar:
            raise Parar(12, "livro de previsoes vazio")
        log("CONFERENCIA: livro vazio em dry-run, nada a fazer")
        return
    hoje_conf = a.hoje_conferencia or dt.date.today().isoformat()
    if a.eventos_json:
        evs, det = C._json(a.eventos_json), {"fonte": "arquivo"}
    else:
        import conferencia_eventos as CE
        evs, det = CE.eventos(C._d(hoje_conf), sem_rede=False, primeiro_pacote=min(C._d(s["data_obs"]) for s in snaps))
    out = C.decidir(snaps, evs, crit, hoje_conf)
    out["deteccao"] = det
    rel = os.path.join(a.saida_dir, "conferencia.json")
    with open(rel, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, ensure_ascii=False, indent=1)
    res["conferencia"] = {k: out[k] for k in ("decisao", "motivo", "eventos_independentes", "pacotes", "p_sinal", "pct_medio_ews2", "pct_medio_atual")}
    log("CONFERENCIA: %s" % json.dumps(res["conferencia"], ensure_ascii=False))
    agora = dt.datetime.now(dt.timezone.utc)
    estado = ler_estado(a.estado)
    if out["decisao"] != "desligar":
        if a.publicar:
            gravar_estado(a.estado, {"decisao": out["decisao"], "desde": agora.isoformat(), "atualizado_em": agora.isoformat(), "motivo": out["motivo"]})
        return
    if not a.publicar:
        log("CONFERENCIA: veredito DESLIGAR em dry-run, flag nao alterada")
        return
    desde = agora
    if estado and estado.get("decisao") == "desligar" and estado.get("desde"):
        desde = dt.datetime.fromisoformat(estado["desde"])
    gravar_estado(a.estado, {"decisao": "desligar", "desde": desde.isoformat(), "atualizado_em": agora.isoformat(), "motivo": out["motivo"]})
    confirmado = bool(estado and estado.get("decisao") == "desligar" and (agora - desde).total_seconds() / 86400 >= a.confirmacao_min_dias)
    if not confirmado:
        raise Parar(14, "conferencia indicou desligar, aguardando confirmacao na proxima rodada (min %s dias): %s" % (a.confirmacao_min_dias, out["motivo"]))
    http, j = post(a.api + "/", {"action": "ews2_flag_desligar", "motivo": out["motivo"], "relatorio": "ews2-conferencia/" + T})
    log("FLAG_DESLIGAR: http=%s %s" % (http, json.dumps(j, ensure_ascii=False)[:300] if j else None))
    if http != 200 or not j or j.get("ok") is not True or (j.get("flag") or {}).get("ativo") is not False:
        raise Parar(13, "conferencia mandou desligar e o desligamento da flag falhou: http=%s" % http)
    res["flag_desligada"] = True
    raise Parar(9, "conferencia mandou desligar o EWS 2.0 e a flag foi desligada: " + out["motivo"])


def ler_estado(caminho):
    if caminho and os.path.exists(caminho):
        try:
            return C._json(caminho)
        except ValueError:
            return None
    return None


def gravar_estado(caminho, estado):
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    with open(caminho, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(estado, fh, ensure_ascii=False, indent=1)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--publicar", action="store_true")
    ap.add_argument("--T")
    ap.add_argument("--api", default=API_PADRAO)
    ap.add_argument("--saida-dir", default=os.path.join(tempfile.gettempdir(), "ews2-ci"))
    ap.add_argument("--backtest", default=BACKTEST_PADRAO)
    ap.add_argument("--backtest-sha256", default=BACKTEST_SHA256)
    ap.add_argument("--livro", default=C.LIVRO)
    ap.add_argument("--historico", default=C.HISTORICO)
    ap.add_argument("--estado", default=ESTADO_PADRAO)
    ap.add_argument("--sem-download", action="store_true")
    ap.add_argument("--sem-conferencia", action="store_true")
    ap.add_argument("--confirmacao-min-dias", type=float, default=5)
    ap.add_argument("--dados-timeout", type=int, default=3000)
    ap.add_argument("--gerar-timeout", type=int, default=1500)
    ap.add_argument("--pacote-pronto", help="so teste: valida/publica um arquivo existente sem baixar nem gerar")
    ap.add_argument("--eventos-json", help="so teste: eventos no lugar da deteccao")
    ap.add_argument("--hoje-conferencia", help="so teste")
    a = ap.parse_args(argv)
    cod, res = executar(a)
    with open(os.path.join(a.saida_dir, "resultado.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(res, fh, ensure_ascii=False, indent=1, default=str)
    log("RESULTADO " + json.dumps({k: res.get(k) for k in ("modo", "T", "exit", "ok", "motivo")}, ensure_ascii=False))
    return cod


if __name__ == "__main__":
    sys.exit(main())
