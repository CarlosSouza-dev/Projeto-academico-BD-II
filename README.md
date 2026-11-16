# Sistema de Matrícula Acadêmica - IESB

Projeto da disciplina de Banco de Dados II (CCO072), semestre 2026/2. Implementa o banco de um sistema de matrícula sobre o modelo lógico fornecido pelo professor, com integridade garantida por restrições, desempenho com índices, controle de concorrência, segurança e backup.

## Equipe

| Frente | Responsável | Scripts |
|---|---|---|
| 1. Modelagem Física e Desempenho | Carlos Eduardo Ferreira de Souza | `01`, `02`, `03`, `05`, `05b` e o bônus `09` |
| 2. Transações e Concorrência | Ana Luiza | `06`, `06b`, `06c` |
| 3. Administração e Operação | Lucas Pessoa Ranieri | `04`, `07`, `08` e o backup |

Detalhes e matrículas em [`AUTORES.md`](AUTORES.md).

> **Situação da `main`:** já estão aqui a frente 1 completa (Marco 1, índices e bônus) e a frente 2 (`06`, `06b`, `06c` e `docs/comparacao_concorrencia.md`), além do relatório em `docs/`. Os scripts da frente 3 (`04`, `07`, `08`) estão na branch [`CARLOS`](https://github.com/CarlosSouza-dev/Projeto-academico-BD-II/tree/CARLOS) e entram na `main` quando o responsável integrar a sua parte. Os scripts `06`, `06b` e `06c` consultam a view `v_vagas`, criada no `04_views.sql`: rode o `04` antes deles.

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

Cole cada arquivo no Query Tool e execute o arquivo inteiro com **F5**.

| # | Arquivo | O que faz | Marco |
|---|---|---|---|
| 1 | `01_ddl_inicial.sql` | Recria o schema `academico`: tipos (ENUM), domínios, tabelas `tb_*`, chaves e restrições | 1 |
| 2 | `02_dml_carga.sql` | Carga: 100 alunos, 6 turmas, 300 matrículas, cursos, currículos, salas e horários | 1 |
| 3 | `03_dql_consultas.sql` | 10 consultas (junções, subconsulta, CTE recursiva, funções de janela) | 1 |
| 4 | `05_indices.sql` | 4 índices: comum, parcial, de expressão e composto | 2 |
| 5 | `06_anomalia_vagas.sql` | Procedure de matrícula sem controle (a anomalia da última vaga) | 2 |
| 6 | `06b_correcao_bloqueio.sql` | Correção 1: `SELECT ... FOR UPDATE` | 2 |
| 7 | `06c_correcao_isolamento.sql` | Correção 2: nível `SERIALIZABLE` + retentativa | 2 |
| 8 | `09_bonus_jsonb_gin.sql` | Bônus: log em JSONB com índice GIN e trigger de auditoria | 2 |

Scripts de apoio (não alteram os dados): `01_ddl(b).sql`, a demonstração ao vivo das restrições (cada comando dá erro de propósito; selecione um de cada vez), e `05b_evidencias_explain.sql`, a prova do ganho de cada índice (`EXPLAIN (ANALYZE, BUFFERS)` antes e depois) numa massa de teste de 500 mil linhas, que é apagada no fim. O resultado, gerado no PostgreSQL 17, está em [`evidencias_explain.txt`](evidencias_explain.txt).

> **Atenção:** o `01_ddl_inicial.sql` executa `DROP SCHEMA academico CASCADE`, ou seja, apaga todos os dados do schema.

### Como os arquivos estão organizados

Cada arquivo tem duas partes:
1. **Criação**: o que roda com F5 no arquivo inteiro. Termina com uma consulta de conferência, que é o que o pgAdmin mostra em *Data Output* (o pgAdmin só mostra o resultado da **última** consulta).
2. **Demonstração ao vivo**: quando existe, fica dentro de um comentário `/* ... */` no fim do arquivo, para não rodar no F5. Selecione só as linhas do passo e aperte F5 (o pgAdmin executa só a seleção).

## Ganho medido dos índices (PostgreSQL 17)

| Índice | Antes | Depois |
|---|---|---|
| comum (`id_aluno`) | Seq Scan, 7,7 ms | Index Scan, 0,03 ms |
| parcial (turma, só `Ativa`) | Seq Scan, 7,4 ms | Bitmap Index Scan, 0,05 ms |
| expressão (`lower(nome_aluno)`) | Seq Scan, 15,6 ms | Index Scan, 0,02 ms |
| composto (situação, frequência) | Seq Scan + ordenação, 9,2 ms | Index Scan já ordenado, 0,04 ms |
| GIN no JSONB (bônus) | Seq Scan, 26,2 ms | Bitmap Index Scan, 0,55 ms |
