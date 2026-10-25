# Sistema de Matrícula Acadêmica - IESB

Projeto desenvolvido para a disciplina de Banco de Dados II (CCO072) - Semestre 2026/2. O objetivo deste projeto é implementar um banco de dados funcional para um sistema de matrícula, garantindo integridade, controle de concorrência, desempenho e segurança.

## Pré-requisitos
* [Docker](https://www.docker.com/) instalado.
* Cliente SQL: **pgAdmin (Query Tool)** ou `psql`. Todos os scripts são SQL puro e rodam nos dois (veja "Executando no pgAdmin" abaixo).

## Como executar o projeto do zero

O ambiente oficial deste projeto utiliza a imagem do **PostgreSQL 17** pré-configurada via Docker Compose.

### Passo 1: Subir o ambiente com Docker Compose
1. Abra o Prompt de Comando (CMD) ou o terminal da sua máquina.
2. Navegue até a pasta `ambiente_aluno`, onde está o `docker-compose.yml`:
   `cd "C:\caminho\para\a\pasta\ambiente_aluno"`
3. Suba o contêiner em segundo plano: `docker compose up -d`
4. Descubra o nome do serviço com `docker compose ps` (abaixo, `<servico>`; `<usuario>` e `<banco>` são os definidos no `docker-compose.yml`).

### Passo 2: Ordem de execução dos scripts
Execute os scripts da raiz, **estritamente nesta ordem** (todos em UTF-8). No pgAdmin: abra cada arquivo e execute-o inteiro (F5). Pelo terminal, um comando por arquivo:

`docker compose exec -T <servico> psql -U <usuario> -d <banco> < 04_views.sql`

| # | Arquivo | O que faz | Marco |
|---|---|---|---|
| 1 | `01_ddl_inicial.sql` | Recria o schema `academico` e cria tipos, domínios e as tabelas `tb_*` | 1 |
| 2 | `02_dml_carga.sql` | Carga: 100 alunos, 6 turmas, 300 matrículas, cursos, currículos, salas e horários | 1 |
| 3 | `03_dql_consultas.sql` | 10 consultas (junção externa, recursiva, funções de janela) | 1 |
| 4 | `04_views.sql` | `v_oferta`, `v_vagas`, `v_historico` e a materialized view `mv_indicadores_disciplina` | 2 |
| 5 | `05_indices.sql` | Índices parcial, de expressão e de cobertura | 2 |
| 6 | `06_anomalia_vagas.sql` | Anomalia da última vaga (requer `dblink`) e o laboratório de concorrência | 2 |
| 7 | `06b_correcao_bloqueio.sql` | Correção 1: `SELECT ... FOR UPDATE` | 2 |
| 8 | `06c_correcao_isolamento.sql` | Correção 2: `SERIALIZABLE` + retentativa | 2 |
| 9 | `07_seguranca.sql` | Papéis, `GRANT`/`REVOKE`, RLS e testes automáticos | 2 |
| 10 | `09_bonus_jsonb_gin.sql` | Bônus: JSONB + GIN e triggers de auditoria | 2 |

Scripts **sob demanda** (não alteram os dados ao final):
* `05b_evidencias_explain.sql`: prova de ganho dos índices em volume (cria e remove o schema `academico_perf`, ~10 s). No pgAdmin, os planos ficam na aba *Messages* e na tabela temporária `planos` (`SELECT linha FROM planos ORDER BY ordem;` > *Download as CSV*). Para gerar o arquivo pelo terminal: `docker compose exec -T <servico> psql -q -U <usuario> -d <banco> < 05b_evidencias_explain.sql > evidencias_explain.txt 2>&1`
* `06d_comparacao_custos.sql`: tabela comparativa das três versões da matrícula (~30 s).
* `08_verificacao_backup.sql`: impressão digital do schema (a última linha, *ASSINATURA GERAL*, deve ser igual antes e depois de uma restauração).

> **Atenção:** o `01_ddl_inicial.sql` executa `DROP SCHEMA academico CASCADE`; rodá-lo apaga todos os dados do schema. O `06_anomalia_vagas.sql` cria a extensão `dblink` (já inclusa na imagem oficial) e exige superusuário, que é o usuário do contêiner.

### Executando no pgAdmin (Query Tool)
1. Selecione o banco do projeto na árvore, abra **Tools > Query Tool** e carregue o arquivo (ícone de pasta, *Open File*). Deixe o **Auto commit** ligado (padrão).
2. **F5** executa o arquivo inteiro; **selecionando um trecho**, o F5 executa só a seleção. Use isso na apresentação para mostrar cada passo.
3. O pgAdmin mostra em **Data Output** apenas o resultado da **última** consulta do que foi executado (por isso cada script termina com a consulta-resumo). Mensagens `RAISE NOTICE` (testes OK/FALHA, planos do `05b`) ficam na aba **Messages**.
4. O pgAdmin envia o arquivo como **um único comando** (uma transação). Os `COMMIT` que aparecem no `05b`, `06*` e `09` são propositais; não os remova. Se algum comando falhar, o arquivo inteiro é desfeito.
5. Usuário: precisa ser **superusuário** (o do contêiner `POSTGRES_USER` é) por causa da extensão `dblink` (`05b` e `06`).
6. O backup/restauração (`scripts/backup_restauracao.sh`) roda **dentro do contêiner**, não no pgAdmin (veja o Passo 3).

### Passo 3: Backup e restauração
O ciclo completo (impressão digital, backup, restauração e comparação) está em `scripts/backup_restauracao.sh`:

```
docker compose cp scripts\backup_restauracao.sh <servico>:/tmp/backup_restauracao.sh
docker compose cp 08_verificacao_backup.sql      <servico>:/tmp/08_verificacao_backup.sql
docker compose exec -e VERIF=/tmp/08_verificacao_backup.sql -e BACKUP_DIR=/tmp/backup_bd2 <servico> bash /tmp/backup_restauracao.sh desastre
```

Modos: `novo_banco` (restaura em `<banco>_restaurado`, seguro) e `desastre` (apaga o schema `academico` e restaura no mesmo banco). Comandos manuais, justificativa da estratégia e política de backup em [`docs/backup_restauracao.md`](docs/backup_restauracao.md).

## Avaliação de desempenho
As provas de ganho dos índices (`EXPLAIN (ANALYZE, BUFFERS)` antes e depois, com 240 mil matrículas) estão em `evidencias_explain.txt`, geradas por `05b_evidencias_explain.sql`.

## Concorrência
Anomalia, correções e comparação medida em [`docs/comparacao_concorrencia.md`](docs/comparacao_concorrencia.md).

## Segurança
Papéis de grupo `aluno`, `secretaria` e `coordenacao`; cada aluno acessa com o papel individual `aluno_<id>` e o RLS limita as linhas ao próprio aluno. Teste manual:

```sql
SET ROLE aluno_3;
SELECT COUNT(*) FROM academico.tb_historico;   -- 4 (só os dele); sem o RLS seriam 300
RESET ROLE;
```

## Documentação
* [`docs/comparacao_concorrencia.md`](docs/comparacao_concorrencia.md): anomalia da última vaga e correções.
* [`docs/backup_restauracao.md`](docs/backup_restauracao.md): backup, restauração e política operacional.
* [`docs/issues_marco2_revisadas.md`](docs/issues_marco2_revisadas.md): avaliação e texto das issues do Marco 2.
* [`docs/guia_explicativo.md`](docs/guia_explicativo.md): como cada script funciona (03 a 09), com perguntas prováveis da arguição.
