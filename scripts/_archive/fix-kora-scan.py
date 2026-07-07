import json

CVM_KORA = "https://www.rad.cvm.gov.br/ENET/frmDownloadDocumento.aspx?Tela=ext&numProtocolo=1306799&descTipo=IPE&CodigoInstituicao=1"
SCAN = r"E:\Diretorio\Claude\Monitoramento de Credito\scans\kora.json"

with open(SCAN, encoding="utf-8") as f:
    kora = json.load(f)

eventos = kora["resultado"]["eventos"]
print("Eventos originais:", len(eventos))
for i, ev in enumerate(eventos):
    print(f"  [{i}] {ev['classificacao']} | data={ev['data_evento']} | {ev['titulo'][:55]}")

# Remover evento com data fora da janela (2026-05-04 < 2026-05-19)
eventos = [ev for ev in eventos if ev["data_evento"] != "2026-05-04"]
print("Apos filtro:", len(eventos))

# Corrigir AGD: data_evento futuro -> data publicacao + fonte CVM
for ev in eventos:
    if ev["data_evento"] == "2026-06-23":
        ev["data_evento"] = "2026-06-08"
        ev["fonte_primaria"] = CVM_KORA
        print("AGD corrigida: data=2026-06-08, fonte=CVM RAD numProtocolo=1306799")

kora["resultado"]["eventos"] = eventos

with open(SCAN, "w", encoding="utf-8") as f:
    json.dump(kora, f, ensure_ascii=False, separators=(",", ":"))

print("kora.json salvo OK")
