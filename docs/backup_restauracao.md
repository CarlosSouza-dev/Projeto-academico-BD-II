# Backup e restauração (reproduzível do zero)

Arquivos: `scripts/backup_restauracao.sh` (ciclo completo e automático) e
`08_verificacao_backup.sql` (prova de que o restaurado é igual ao original: uma consulta que
devolve uma linha por tabela, sequência e tipo de objeto e, por último, a **ASSINATURA GERAL**, um MD5 de tudo).

## 1. Estratégia e justificativa

**Backup lógico com `pg_dump`, formato custom (`-Fc`), do schema `academico`.**

| Decisão | Por quê |
|---|---|
| Lógico (`pg_dump`) e não físico (`pg_basebackup`) | O banco é pequeno e precisamos restaurar **o schema, em outro servidor, até em outra versão** (o dump do PG 16 restaura no 17). O físico copia o cluster inteiro, só serve na mesma versão/arquitetura e não permite restaurar "só o schema academico". |
| `-Fc` (custom) e não SQL puro | Compactado, tem índice interno (`pg_restore -l`), restaura seletivamente e em paralelo (`-j`). |
| Consistente sem parar o sistema | O `pg_dump` roda numa única transação com *snapshot* MVCC: lê um instante coerente do banco **sem bloquear escritas** (ninguém precisa sair do ar). |
| `-n academico` | Só o schema do projeto. A extensão `dblink` (06) fica em `public` e é recriada com `CREATE EXTENSION`. |
| Backup dos **papéis** à parte (`pg_dumpall --roles-only`) | Papéis são do **cluster**, não do banco; o `pg_dump` não os inclui. Sem `aluno`, `secretaria`, `coordenacao` e `aluno_N`, os `GRANT` e as policies de RLS **falhariam** num servidor novo. |
| `pg_restore --exit-on-error` | Qualquer falha interrompe o processo, em vez de entregar um banco pela metade sem ninguém perceber. |
| Verificação por impressão digital (MD5 do conteúdo) | "Terminou sem erro" não prova que restaurou tudo. Comparamos linhas e hash de cada tabela, sequências, índices, policies e concessões, antes e depois. |

**O que o backup lógico cobre:** tabelas e dados, tipos/domínios, constraints, índices, views, a
materialized view (com dados), funções e procedures, triggers, `GRANT`/`REVOKE`, RLS e policies,
sequências (posição do próximo id).

**O que NÃO cobre:** papéis (por isso o arquivo `papeis_*.sql`), extensões de outro schema,
configuração do servidor (`postgresql.conf`, `pg_hba.conf`) e a senha do usuário de conexão.

### Política operacional recomendada
- **Frequência:** backup completo diário (madrugada); antes de qualquer migração de schema.
- **Retenção:** 7 diários + 4 semanais + 3 mensais.
- **Local:** cópia **fora** do servidor (regra 3-2-1: 3 cópias, 2 mídias, 1 fora do local). Um dump
  guardado no mesmo disco do banco não protege contra falha de disco.
- **Teste de restauração:** periódico. Backup que nunca foi restaurado não é backup. O script abaixo
  é exatamente esse teste.
- **Limite:** o backup lógico restaura **até o instante do dump** (RPO = intervalo entre backups). Para
  perder segundos e não horas, o caminho é *archiving* de WAL + `pg_basebackup` (PITR), não
  implementado aqui por ser desnecessário para este porte.

## 2. Executar o ciclo completo (recomendado)

O script faz: impressão digital → backup → destino → papéis → restauração → impressão digital →
comparação. Termina com código 0 se as duas impressões forem idênticas.

```
bash scripts/backup_restauracao.sh novo_banco    # restaura num banco vazio <banco>_restaurado (seguro)
bash scripts/backup_restauracao.sh desastre      # APAGA o schema academico e restaura no mesmo banco
```

Saída esperada (resumo):
```
[2/6] BACKUP lógico        dump: .../academico_<data>.dump  (88K)   entradas no dump: 179
[3/6] Preparando o destino  SIMULANDO O DESASTRE: DROP SCHEMA academico CASCADE ...  schema academico existe? false
[5/6] RESTAURANDO (pg_restore)   restauração concluída
[6/6] RESULTADO: IDÊNTICO.  Teste do RLS no banco restaurado: aluno_3 enxerga 4 linha(s) (esperado: 4)
```

### No Docker oficial (PostgreSQL 17), pelo Prompt de Comando
O script roda **dentro do contêiner** (a imagem oficial tem `bash`, `pg_dump` e `pg_restore`) e usa
`POSTGRES_USER` e `POSTGRES_DB` do próprio contêiner. Troque `<servico>` pelo nome do serviço no
`docker-compose.yml` (descubra com `docker compose ps`), na pasta `ambiente_aluno`:

```
docker compose cp scripts\backup_restauracao.sh <servico>:/tmp/backup_restauracao.sh
docker compose cp 08_verificacao_backup.sql      <servico>:/tmp/08_verificacao_backup.sql
docker compose exec -e VERIF=/tmp/08_verificacao_backup.sql -e BACKUP_DIR=/tmp/backup_bd2 <servico> bash /tmp/backup_restauracao.sh desastre
docker compose cp <servico>:/tmp/backup_bd2 .\backup_bd2          :: traz os arquivos para o seu computador
```
Se o banco exigir senha, acrescente `-e PGPASSWORD=<senha>` ao `docker compose exec`.

### Usando só o pgAdmin
O pgAdmin não roda o `scripts/backup_restauracao.sh` (ele é de terminal), mas dá para fazer o ciclo pela interface:
1. Query Tool: execute `08_verificacao_backup.sql` e anote a **ASSINATURA GERAL** (última linha).
2. Botão direito no schema `academico` > **Backup...**: formato **Custom**, escolha o nome do arquivo (no pgAdmin web ele fica no armazenamento do servidor do pgAdmin).
3. Query Tool: `DROP SCHEMA academico CASCADE;` (o desastre). Os papéis `aluno`, `secretaria` e `aluno_N` **não** são apagados (são do servidor).
4. Botão direito no **banco** > **Restore...**: formato Custom, selecione o arquivo e execute.
5. Execute o `08` de novo: a **ASSINATURA GERAL** tem de ser a mesma.

Esse caminho pela interface não foi testado aqui; o que foi testado e validado é o script (seção 2). Ensaie antes.

## 3. Roteiro da demonstração ao vivo (restauração de backup) em ~3 minutos
1. `psql`: `SELECT COUNT(*) FROM academico.tb_matricula;` → **300** (mostre também `v_vagas`).
2. Rode o script em modo `desastre` e comente cada passo ao aparecer (backup, `DROP SCHEMA`, restore).
3. Mostre que o schema voltou: `SELECT COUNT(*) FROM academico.tb_matricula;` → **300**.
4. Mostre o RLS no banco restaurado: `SET ROLE aluno_3; SELECT COUNT(*) FROM academico.tb_historico;` → **4**.
5. `RESET ROLE;`

## 4. Passo a passo manual (para explicar e para responder à arguição)

```bash
# 0) Impressão digital do original
psql -X -q -A -t -d <banco> -f 08_verificacao_backup.sql > antes.txt   # a última linha é a ASSINATURA GERAL

# 1) BACKUP do schema (custom, compactado) e dos papéis (precisa ser superusuário)
pg_dump -Fc -n academico -f academico.dump <banco>
pg_dumpall --roles-only -f papeis.sql

# 2) (opcional) conferir o conteúdo do dump
pg_restore -l academico.dump

# 3) DESTINO. Opção A, servidor novo / banco vazio:
createdb bd2_restaurado
#    Opção B, desastre no mesmo banco:
psql -d <banco> -c "DROP SCHEMA academico CASCADE"

# 4) PAPÉIS (em servidor novo; os "already exists" de um servidor antigo são esperados)
psql -d bd2_restaurado -f papeis.sql

# 5) RESTAURAR
pg_restore --exit-on-error -d bd2_restaurado academico.dump

# 6) VERIFICAR
psql -X -q -A -t -d bd2_restaurado -f 08_verificacao_backup.sql > depois.txt
diff antes.txt depois.txt && echo IDÊNTICO
```

**Do zero, num contêiner novo** (`docker compose up -d` em máquina limpa): crie o banco, aplique
`papeis.sql`, rode `pg_restore` e confira com o passo 6. Não é necessário executar o 01 a 09 antes:
o dump contém o schema inteiro (estrutura + dados + índices + views + segurança).

## 5. O que foi testado (PostgreSQL 16)

| Cenário | Resultado |
|---|---|
| Banco vazio no mesmo servidor (`novo_banco`) | Idêntico; `aluno_3` vê 4 linhas |
| Desastre: `DROP SCHEMA academico CASCADE` e restauração no mesmo banco | Idêntico; `aluno_3` vê 4 linhas |
| **Servidor novo**, sem nenhum papel (0 → 104 criados pelo `papeis.sql`) | `pg_restore` sem erros; idêntico; `aluno_3` vê 4 linhas |

"Idêntico" = mesmas linhas e mesmo MD5 do conteúdo nas 16 tabelas, mesma materialized view, mesma
posição das 14 sequências, mesmos índices (36), constraints (62), policies (9) e concessões (62).

## 6. Pontos de atenção (arguição)
- **Versões:** o dump restaura em PostgreSQL **igual ou mais novo**; o inverso não é garantido.
- **Dono dos objetos:** `pg_restore` recria os `OWNER`. Num servidor onde o dono não existe, use `--no-owner`.
- **Materialized view:** restaura a definição e a **recarrega** (`REFRESH`) no fim; por isso
  `atualizado_em` muda e fica fora da impressão digital.
- **Sequências:** voltam na posição do dump, então o próximo `INSERT` não colide com `duplicate key`.
- **RLS:** a regra volta junto com as tabelas, mas depende dos papéis `aluno_N`: sem o `papeis.sql`
  as policies existiriam e ninguém conseguiria usá-las.
- **Senhas:** `pg_dumpall --roles-only` grava o hash das senhas dos papéis: trate `papeis_*.sql` como arquivo sensível.
