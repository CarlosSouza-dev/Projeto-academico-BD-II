# Sistema de Matrícula Acadêmica - IESB

Projeto da disciplina de Banco de Dados II (CCO072), semestre 2026/2. Implementa o banco de um sistema de matrícula sobre o modelo lógico fornecido pelo professor, com integridade garantida por restrições, desempenho com índices, controle de concorrência, segurança e backup.

## Equipe

| Frente | Responsável | Scripts |
|---|---|---|
| 1. Modelagem Física e Desempenho | Carlos Eduardo Ferreira de Souza | `01`, `02`, `03`, `05`, `05b` e o bônus `09` |
| 2. Transações e Concorrência | Ana Luiza | `06`, `06b`, `06c` |
| 3. Administração e Operação | Lucas Pessoa Ranieri | `04`, `07`, `08` e o backup |

Detalhes e matrículas em [`AUTORES.md`](AUTORES.md).

## Pré-requisitos
* [Docker Desktop](https://www.docker.com/) instalado.
* O ambiente oficial da disciplina (`ambiente_aluno`, com o `docker-compose.yml` do professor): PostgreSQL 17 e pgAdmin.

## Passo 1: subir o ambiente

Na pasta `ambiente_aluno`, no terminal:

```
docker compose up -d
```

| Serviço | Endereço | Acesso |
|---|---|---|
| PostgreSQL 17 | `localhost:5432` | usuário `bd2`, senha `bd2`, banco `matricula` |
| pgAdmin | `http://localhost:8080` | `admin@iesb.br` / `admin` |

No pgAdmin, cadastre o servidor com host `postgres` (o nome do serviço no `docker-compose.yml`), usuário `bd2` e senha `bd2`. Depois abra o banco `matricula` e use **Tools > Query Tool**.

## Passo 2: rodar os scripts, nesta ordem

Abra cada arquivo no Query Tool (ícone de pasta) e execute o arquivo inteiro com **F5**.

| # | Arquivo | O que faz | Marco |
|---|---|---|---|
| 1 | `01_ddl_inicial.sql` | Recria o schema `academico`: tipos (ENUM), domínios, tabelas `tb_*`, chaves e restrições | 1 |
| 2 | `02_dml_carga.sql` | Carga: 100 alunos, 6 turmas, 300 matrículas, cursos, currículos, salas e horários | 1 |
| 3 | `03_dql_consultas.sql` | 10 consultas (junções, subconsulta, CTE recursiva, funções de janela) | 1 |
| 4 | `04_views.sql` | Views `v_oferta`, `v_vagas`, `v_historico` e a materialized view `mv_indicadores_disciplina` | 2 |
| 5 | `05_indices.sql` | 4 índices: comum, parcial, de expressão e composto | 2 |
| 6 | `06_anomalia_vagas.sql` | Procedure de matrícula sem controle (a anomalia da última vaga) | 2 |
| 7 | `06b_correcao_bloqueio.sql` | Correção 1: `SELECT ... FOR UPDATE` | 2 |
| 8 | `06c_correcao_isolamento.sql` | Correção 2: nível `SERIALIZABLE` + retentativa | 2 |
| 9 | `07_seguranca.sql` | Papéis, `GRANT`/`REVOKE` e row-level security | 2 |
| 10 | `09_bonus_jsonb_gin.sql` | Bônus: log em JSONB com índice GIN e trigger de auditoria | 2 |

Scripts de apoio (não alteram os dados):
* `05b_evidencias_explain.sql`: prova do ganho de cada índice (`EXPLAIN (ANALYZE, BUFFERS)` antes e depois) numa massa de teste de 500 mil linhas, que é apagada no fim. O resultado está em [`evidencias_explain.txt`](evidencias_explain.txt).
* `08_verificacao_backup.sql`: conferência do banco antes do backup e depois da restauração (a saída tem de ser igual).

> **Atenção:** o `01_ddl_inicial.sql` executa `DROP SCHEMA academico CASCADE`, ou seja, apaga todos os dados do schema.

### Como os arquivos estão organizados

Cada arquivo tem duas partes:
1. **Criação**: o que roda com F5 no arquivo inteiro (tabelas, views, procedures...). Termina com uma consulta de conferência, que é o que o pgAdmin mostra em *Data Output* (o pgAdmin só mostra o resultado da **última** consulta).
2. **Demonstração ao vivo**: fica dentro de um comentário `/* ... */` no fim do arquivo, para não rodar no F5. Na apresentação, **selecione** só as linhas do passo e aperte F5 (o pgAdmin executa só a seleção). Alguns passos dão erro **de propósito** (está indicado no comentário).

## Demonstrações da apresentação

| O que mostrar | Onde |
|---|---|
| Restrições de integridade | `01_ddl_inicial.sql` (CHECK, UNIQUE, FK, domínios, colunas geradas) |
| Anomalia da última vaga e as correções | Blocos de demonstração do `06`, `06b` e `06c` (duas abas do Query Tool) |
| Plano de execução com `EXPLAIN ANALYZE` | `05b_evidencias_explain.sql` (selecione um bloco ANTES/DEPOIS) |
| Row-level security | Bloco de demonstração do `07_seguranca.sql` |
| Restauração de backup ao vivo | [`docs/backup_restauracao.md`](docs/backup_restauracao.md) |

## Backup e restauração

Pelo terminal (o contêiner se chama `bd2_aluno_postgres`):

```
docker exec bd2_aluno_postgres pg_dump -U bd2 -d matricula -n academico -Fc -f /tmp/academico.dump
docker exec bd2_aluno_postgres psql -U bd2 -d matricula -c "DROP SCHEMA academico CASCADE"
docker exec bd2_aluno_postgres pg_restore -U bd2 -d matricula /tmp/academico.dump
```

Rode o `08_verificacao_backup.sql` antes e depois: os números têm de ser iguais. Explicação, justificativa e o caminho pelo pgAdmin em [`docs/backup_restauracao.md`](docs/backup_restauracao.md).

## Documentação
* [`docs/roteiro_apresentacao.md`](docs/roteiro_apresentacao.md): passo a passo da demonstração (subir, rodar, mostrar cada requisito) e respostas às perguntas prováveis.
* [`docs/comparacao_concorrencia.md`](docs/comparacao_concorrencia.md): a anomalia da última vaga, as duas correções e a comparação entre elas.
* [`docs/backup_restauracao.md`](docs/backup_restauracao.md): estratégia de backup, passo a passo e roteiro da demonstração.
* [`docs/guia_explicativo.md`](docs/guia_explicativo.md): como cada script funciona, com perguntas prováveis da arguição.
