// Decisao pura da guarda de quarentena (CFG-02 P3). Sem rede e sem import do
// Worker, para ser testada de duas pontas em api/test/quarentena-guarda.test.mjs.
//
// Entrada:
//   fila         entidades em quarentena devolvidas por admin_cvm_quarentena
//   entidades    total de entidades em quarentena declarado pelo Worker
//   descartados  cvm_ingestao_descartados_sem_dono do health (fluxo do ultimo
//                sync, o que a ingestao NAO gravou), ou null se o health nao expoe
//   donoPorCnpj  mapa cnpj so-digito -> emissor dos 103, mesma regua de producao
//   soDigito     normalizador de CNPJ
//
// Saida: { codigo, falhas, motivo }
//   0 = aprovado, 1 = emissor dos 103 na quarentena, 3 = vacuo (fila vazia com
//   descarte positivo: a guarda nao tem o que avaliar e o descarte prova que
//   houve documento sem dono que a fila nao mostra), 4 = descarte nao medivel.
//
// Fila vazia so aprova quando o descarte e ZERO medido. Aprovar sobre conjunto
// vazio com descarte positivo foi o que manteve o defeito invisivel desde 13/09.
export function avaliarQuarentena({ fila, entidades, descartados, donoPorCnpj, soDigito }) {
  const lista = Array.isArray(fila) ? fila : [];
  const falhas = [];
  for (const e of lista) {
    const dig = soDigito(e && e.cnpj || "");
    if (dig && donoPorCnpj[dig]) falhas.push({ cnpj: e.cnpj, nome: e.nome, emissor: donoPorCnpj[dig], documentos: e.documentos });
  }
  if (falhas.length) return { codigo: 1, falhas, motivo: "emissor_dos_103_na_quarentena" };
  const vazia = lista.length === 0 && !(Number(entidades) > 0);
  if (vazia) {
    if (descartados == null || !Number.isFinite(Number(descartados))) return { codigo: 4, falhas, motivo: "descarte_nao_medivel" };
    if (Number(descartados) > 0) return { codigo: 3, falhas, motivo: "fila_vazia_com_descarte_positivo" };
  }
  return { codigo: 0, falhas, motivo: "ok" };
}
