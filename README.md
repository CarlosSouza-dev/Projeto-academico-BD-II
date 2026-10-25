# Sistema de Matrícula Acadêmica - IESB

Projeto desenvolvido para a disciplina de Banco de Dados II (CCO072) - Semestre 2026/2. O objetivo deste projeto é implementar um banco de dados funcional para um sistema de matrícula, garantindo integridade, controle de concorrência, desempenho e segurança.

## Pré-requisitos
* [Docker](https://www.docker.com/) instalado.
* Cliente SQL (ex: DBeaver, pgAdmin ou psql). Os scripts 04 em diante usam comandos do `psql` (`\echo`, `\gexec`...), então devem ser executados **pelo `psql`**.

## Como executar o projeto do zero

O ambiente oficial deste projeto utiliza a imagem do **PostgreSQL 17** pré-configurada via Docker Compose.

### Passo 1: Subir o ambiente com Docker Compose
1. Abra o Prompt de Comando (CMD) ou o terminal da sua máquina.
2. Navegue até a pasta `ambiente_aluno`, onde está o `docker-compose.yml`:
   `cd "C:\caminho\para\a\pasta\ambiente_aluno"`
3. Suba o contêiner em segundo plano: `docker compose up -d`
4. Descubra o nome do serviço com `docker compose ps` (abaixo, `<servico>`; `<usuario>` e `<banco>` são os definidos no `docker-compose.yml`).

### Passo 2: Ordem de execução dos scripts
Execute os scripts da raiz, **estritamente nesta ordem** (todos em UTF-8). Exemplo de comando para cada arquivo:

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
* `05b_evidencias_explain.sql`: prova de ganho dos índices em volume (cria e remove o schema `academico_perf`, ~10 s). Gere o arquivo de evidência: `docker compose exec -T <servico> psql -q -U <usuario> -d <banco> < 05b_evidencias_explain.sql > evidencias_explain.txt`
* `06d_comparacao_custos.sql`: tabela comparativa das três versões da matrícula (~30 s).
* `08_verificacao_backup.sql`: impressão digital do schema (usada pelo script de backup).

> **Atenção:** o `01_ddl_inicial.sql` executa `DROP SCHEMA academico CASCADE`; rodá-lo apaga todos os dados do schema. O `06_anomalia_vagas.sql` cria a extensão `dblink` (já inclusa na imagem oficial) e exige superusuário, que é o usuário do contêiner.

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
