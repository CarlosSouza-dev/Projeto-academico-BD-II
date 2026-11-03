#!/usr/bin/env bash
# =============================================================================
# backup_restauracao.sh - ciclo COMPLETO e verificável de backup e restauração
#
#   1. tira a impressão digital do banco (08_verificacao_backup.sql)
#   2. faz o backup lógico do schema academico (pg_dump -Fc) e dos papéis
#   3. prepara o destino:   novo_banco -> cria um banco vazio <banco>_restaurado
#                           desastre   -> APAGA o schema academico do banco atual
#   4. restaura os papéis (os que já existem são ignorados)
#   5. restaura o schema (pg_restore)
#   6. tira a impressão digital de novo e COMPARA: idênticas = restauração correta
#
# Uso:   bash backup_restauracao.sh [novo_banco | desastre]      (padrão: novo_banco)
#
# Variáveis (todas opcionais):
#   PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE   conexão (padrões do psql)
#   BACKUP_DIR   onde gravar os arquivos          (padrão: ./backup_bd2)
#   VERIF        caminho do 08_verificacao_backup.sql
#
# Dentro do contêiner Docker oficial, PGUSER e PGDATABASE assumem
# POSTGRES_USER e POSTGRES_DB automaticamente. O usuário precisa ser superusuário
# (o do contêiner é): o backup dos papéis (pg_dumpall --roles-only) exige.
# =============================================================================
set -euo pipefail

MODO="${1:-novo_banco}"
case "$MODO" in novo_banco|desastre) ;; *) echo "modo inválido: $MODO (use novo_banco ou desastre)"; exit 2;; esac

export PGUSER="${PGUSER:-${POSTGRES_USER:-postgres}}"
export PGDATABASE="${PGDATABASE:-${POSTGRES_DB:-$PGUSER}}"
BACKUP_DIR="${BACKUP_DIR:-./backup_bd2}"
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIF="${VERIF:-$AQUI/../08_verificacao_backup.sql}"
[ -f "$VERIF" ] || VERIF="$AQUI/08_verificacao_backup.sql"
[ -f "$VERIF" ] || { echo "não encontrei 08_verificacao_backup.sql (defina VERIF=caminho)"; exit 2; }

STAMP="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
DUMP="$BACKUP_DIR/academico_${STAMP}.dump"
PAPEIS="$BACKUP_DIR/papeis_${STAMP}.sql"
ANTES="$BACKUP_DIR/impressao_antes_${STAMP}.txt"
DEPOIS="$BACKUP_DIR/impressao_depois_${STAMP}.txt"

passo() { printf '\n[%s] %s\n' "$1" "$2"; }

passo "1/6" "Impressão digital ANTES  (banco: $PGDATABASE)"
psql -X -q -A -t -v ON_ERROR_STOP=1 -d "$PGDATABASE" -f "$VERIF" > "$ANTES" 2>/dev/null
grep -E '\|tabela\|tb_(aluno|matricula|historico)\||ASSINATURA' "$ANTES" | cut -d'|' -f2- | sed 's/^/      /'

passo "2/6" "BACKUP lógico"
# -Fc : formato "custom" (compactado, permite restauração seletiva e paralela)
# -n  : somente o schema academico (o dblink do 06 fica em public e não faz parte)
pg_dump -Fc -n academico -f "$DUMP" "$PGDATABASE"
# Os papéis (aluno, secretaria, coordenacao, aluno_N) pertencem ao CLUSTER, não ao
# banco: o pg_dump NÃO os inclui. Sem eles, GRANTs e policies falhariam num servidor novo.
pg_dumpall --roles-only -f "$PAPEIS"
pg_restore -l "$DUMP" > "$BACKUP_DIR/conteudo_${STAMP}.txt"      # índice do que o dump contém
echo "      dump:    $DUMP  ($(du -h "$DUMP" | cut -f1))"
echo "      papéis:  $PAPEIS"
echo "      entradas no dump: $(grep -vc '^;' "$BACKUP_DIR/conteudo_${STAMP}.txt")"
if command -v sha256sum >/dev/null; then echo "      sha256:  $(sha256sum "$DUMP" | cut -d' ' -f1)"; fi

passo "3/6" "Preparando o destino (modo: $MODO)"
if [ "$MODO" = "desastre" ]; then
    ALVO="$PGDATABASE"
    echo "      SIMULANDO O DESASTRE: DROP SCHEMA academico CASCADE em $ALVO"
    PGOPTIONS='-c client_min_messages=warning' psql -X -q -v ON_ERROR_STOP=1 -d "$ALVO" -c "DROP SCHEMA academico CASCADE"
    psql -X -A -t -d "$ALVO" -c "SELECT 'schema academico existe? ' || EXISTS (SELECT 1 FROM pg_namespace WHERE nspname='academico')" | sed 's/^/      /'
else
    ALVO="${PGDATABASE}_restaurado"
    echo "      criando o banco vazio $ALVO"
    dropdb --if-exists "$ALVO"
    createdb "$ALVO"
fi

passo "4/6" "Restaurando os papéis (já existentes são ignorados)"
# Sem ON_ERROR_STOP de propósito: "role already exists" é esperado num servidor que já tem os papéis.
psql -X -q -d "$ALVO" -f "$PAPEIS" > /dev/null 2>&1 || true
psql -X -A -t -d "$ALVO" -c "SELECT '      papéis presentes: ' || string_agg(rolname, ', ' ORDER BY rolname) FROM pg_roles WHERE rolname IN ('aluno','secretaria','coordenacao')"

passo "5/6" "RESTAURANDO (pg_restore)"
# --exit-on-error: qualquer falha interrompe, em vez de produzir um banco pela metade
pg_restore --exit-on-error -d "$ALVO" "$DUMP"
echo "      restauração concluída em $ALVO"

passo "6/6" "Impressão digital DEPOIS e comparação"
PGDATABASE="$ALVO" psql -X -q -A -t -v ON_ERROR_STOP=1 -d "$ALVO" -f "$VERIF" > "$DEPOIS" 2>/dev/null
if diff -u "$ANTES" "$DEPOIS" > "$BACKUP_DIR/diferencas_${STAMP}.txt"; then
    echo "      RESULTADO: IDÊNTICO. Tabelas, conteúdo (MD5), sequências, índices, policies e concessões"
    echo "                 foram recuperados integralmente."
    grep 'ASSINATURA' "$DEPOIS" | cut -d'|' -f2- | sed 's/^/      /'
    TESTE_RLS="$(psql -X -A -t -d "$ALVO" -c "SET ROLE aluno_3; SELECT count(*) FROM academico.tb_historico;" 2>&1 | tail -1)"
    echo "      Teste do RLS no banco restaurado: aluno_3 enxerga $TESTE_RLS linha(s) de histórico (esperado: 4)"
    exit 0
else
    echo "      RESULTADO: DIFERENTE! Veja $BACKUP_DIR/diferencas_${STAMP}.txt"
    head -40 "$BACKUP_DIR/diferencas_${STAMP}.txt"
    exit 1
fi
