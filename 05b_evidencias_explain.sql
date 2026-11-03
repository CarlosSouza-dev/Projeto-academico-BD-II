-----------------------------------------------------------------
-- 05b_evidencias_explain.sql  (Marco 2 - prova do ganho dos índices)
--
-- POR QUE UM SCRIPT SEPARADO: com 300 matrículas o PostgreSQL nem usa
-- índice (ler 300 linhas direto é mais barato). Para MEDIR o ganho, este
-- script cria um schema de teste com muitas linhas (generate_series),
-- roda EXPLAIN (ANALYZE, BUFFERS) ANTES do índice, cria o índice (o mesmo
-- do 05_indices.sql) e roda o EXPLAIN de novo DEPOIS. No fim, apaga o
-- schema de teste. O schema academico não é tocado.
--
-- COMO LER O EXPLAIN (ANALYZE, BUFFERS):
--   Seq Scan          = leu a tabela inteira
--   Index Scan        = foi direto às linhas pelo índice
--   Bitmap Index Scan = usou o índice para marcar as páginas e depois as leu
--   Execution Time    = tempo real da consulta
--   Buffers: shared   = páginas de 8 kB lidas (menos páginas = menos trabalho)
--
-- COMO EXECUTAR
--   pgAdmin: selecione cada bloco (ANTES / CREATE INDEX / DEPOIS) e aperte F5.
--     O plano aparece em Data Output. Executando o arquivo inteiro, o pgAdmin
--     só mostra o último resultado.
--   Terminal (gera o arquivo de evidências com todos os planos):
--     docker exec -i bd2_aluno_postgres psql -U bd2 -d matricula < 05b_evidencias_explain.sql > evidencias_explain.txt
-----------------------------------------------------------------
SELECT version();

DROP SCHEMA IF EXISTS teste_desempenho CASCADE;
CREATE SCHEMA teste_desempenho;
SET search_path TO teste_desempenho;

-----------------------------------------------------------------
-- 1. Massa de teste (só as colunas que as consultas usam)
--    100 mil alunos, 500 mil matrículas (10% Ativas), 500 mil históricos
-----------------------------------------------------------------
CREATE TABLE tb_aluno AS
SELECT i AS id_aluno,
       'Aluno Teste ' || i AS nome_aluno
FROM generate_series(1, 100000) AS i;

CREATE TABLE tb_matricula AS
SELECT i AS id_matricula,
       (i % 100000) + 1 AS id_aluno,                                       -- 5 matrículas por aluno
       (i % 2000) + 1   AS id_turma,                                       -- 2.000 turmas, 250 matrículas cada
       CASE WHEN (i / 2000) % 10 = 0 THEN 'Ativa' ELSE 'Concluida' END AS status_matricula  -- 25 ativas por turma
FROM generate_series(1, 500000) AS i;

CREATE TABLE tb_historico AS
SELECT i AS id_matricula,
       CASE WHEN i % 33 = 0 THEN 'Reprovado por Falta' ELSE 'Aprovado' END AS situacao,  -- ~3% por falta
       (40 + (i % 60))::numeric(5,2) AS frequencia
FROM generate_series(1, 500000) AS i;

ANALYZE tb_aluno;
ANALYZE tb_matricula;
ANALYZE tb_historico;

-----------------------------------------------------------------
-- ÍNDICE 1 (comum, chave estrangeira): matrículas de um aluno
-----------------------------------------------------------------
-- ANTES
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM tb_matricula WHERE id_aluno = 12345;

CREATE INDEX idx_matricula_aluno ON tb_matricula (id_aluno);
ANALYZE tb_matricula;

-- DEPOIS
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM tb_matricula WHERE id_aluno = 12345;

-----------------------------------------------------------------
-- ÍNDICE 2 (PARCIAL): vagas ocupadas de uma turma (só matrículas Ativas)
-----------------------------------------------------------------
-- ANTES
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM tb_matricula WHERE id_turma = 770 AND status_matricula = 'Ativa';

CREATE INDEX idx_matricula_turma_ativa ON tb_matricula (id_turma) WHERE status_matricula = 'Ativa';
ANALYZE tb_matricula;

-- DEPOIS
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM tb_matricula WHERE id_turma = 770 AND status_matricula = 'Ativa';

-- Tamanho: o índice parcial guarda só 10% das linhas
SELECT pg_size_pretty(pg_relation_size('idx_matricula_turma_ativa')) AS indice_parcial,
       pg_size_pretty(pg_relation_size('idx_matricula_aluno'))       AS indice_tabela_toda;

-----------------------------------------------------------------
-- ÍNDICE 3 (EXPRESSÃO): busca pelo nome sem diferenciar maiúsculas
-----------------------------------------------------------------
-- ANTES
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM tb_aluno WHERE lower(nome_aluno) = 'aluno teste 54321';

CREATE INDEX idx_aluno_nome_lower ON tb_aluno (lower(nome_aluno));
ANALYZE tb_aluno;

-- DEPOIS
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM tb_aluno WHERE lower(nome_aluno) = 'aluno teste 54321';

-----------------------------------------------------------------
-- ÍNDICE 4 (COMPOSTO): os 20 reprovados por falta com menor frequência
-----------------------------------------------------------------
-- ANTES
EXPLAIN (ANALYZE, BUFFERS)
SELECT id_matricula, frequencia
FROM tb_historico
WHERE situacao = 'Reprovado por Falta'
ORDER BY frequencia
LIMIT 20;

CREATE INDEX idx_historico_situacao_freq ON tb_historico (situacao, frequencia);
ANALYZE tb_historico;

-- DEPOIS
EXPLAIN (ANALYZE, BUFFERS)
SELECT id_matricula, frequencia
FROM tb_historico
WHERE situacao = 'Reprovado por Falta'
ORDER BY frequencia
LIMIT 20;

-----------------------------------------------------------------
-- BÔNUS (GIN sobre JSONB, ver 09_bonus_jsonb_gin.sql): logs de uma turma
-----------------------------------------------------------------
CREATE TABLE tb_log_matricula AS
SELECT i AS id_log_matricula,
       jsonb_build_object('id_aluno', (i % 100000) + 1,
                          'id_turma', (i % 2000) + 1,
                          'status',   'Ativa') AS detalhe
FROM generate_series(1, 200000) AS i;
ANALYZE tb_log_matricula;

-- ANTES
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM tb_log_matricula WHERE detalhe @> '{"id_turma": 770}';

CREATE INDEX idx_log_detalhe_gin ON tb_log_matricula USING gin (detalhe);
ANALYZE tb_log_matricula;

-- DEPOIS
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM tb_log_matricula WHERE detalhe @> '{"id_turma": 770}';

-----------------------------------------------------------------
-- Limpeza: a massa de teste não é mais necessária
-----------------------------------------------------------------
RESET search_path;
DROP SCHEMA teste_desempenho CASCADE;
