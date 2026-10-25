-----------------------------------------------------------------
-- 05b_evidencias_explain.sql  (Marco 2 - evidências de desempenho)
--
-- Com 300 matrículas o PostgreSQL nem usa índice (varrer 300 linhas é mais
-- barato). Para MEDIR o ganho, este script monta uma cópia do schema
-- (academico_perf) com volume realista, roda EXPLAIN (ANALYZE, BUFFERS)
-- ANTES e DEPOIS de criar cada índice e imprime um resumo com o ganho.
-- Não altera nem lê dados do schema academico (só copia as ESTRUTURAS).
--
-- Pré-requisito: 01 a 05 já executados (as definições dos índices são lidas
-- do próprio banco, a partir do que o 05_indices.sql criou).
--
-- Como gerar o arquivo de evidências (saída = evidencias_explain.txt):
--   psql -U <usuario> -d <banco> -f 05b_evidencias_explain.sql > evidencias_explain.txt
-- Com Docker (CMD):
--   docker compose exec -T <servico> psql -U <usuario> -d <banco> < 05b_evidencias_explain.sql > evidencias_explain.txt
--
-- Os tempos variam de máquina para máquina: gere o arquivo no ambiente
-- Docker oficial antes da apresentação.
-----------------------------------------------------------------
\set ON_ERROR_STOP on
\pset pager off
\pset footer off
\timing off

SELECT to_regclass('academico.idx_matricula_aluno') IS NOT NULL AS indices_ok \gset
\if :indices_ok
\else
  \echo 'ERRO: rode 05_indices.sql antes deste script.'
  \quit
\endif

\echo '================================================================='
\echo ' EVIDÊNCIAS DE DESEMPENHO - EXPLAIN (ANALYZE, BUFFERS)'
\echo '================================================================='
SELECT version() AS servidor, now()::timestamp(0) AS gerado_em;

SET jit = off;                         -- evita ruído de compilação JIT nos tempos
SET client_min_messages = warning;

-----------------------------------------------------------------
-- 1. Schema de volume: mesma estrutura das tabelas reais, sem os índices
--    de otimização (para o "antes" ser honesto).
-----------------------------------------------------------------
DROP SCHEMA IF EXISTS academico_perf CASCADE;
CREATE SCHEMA academico_perf;

DO $$
DECLARE
    t text;
    i regclass;
BEGIN
    FOREACH t IN ARRAY ARRAY['tb_periodo_letivo','tb_disciplina','tb_professor','tb_turma',
                             'tb_aluno','tb_matricula','tb_historico','tb_log_matricula']
    LOOP
        EXECUTE format('CREATE TABLE academico_perf.%I (LIKE academico.%I INCLUDING ALL)', t, t);
    END LOOP;
    -- INCLUDING ALL também copiou os índices de otimização do 05: removê-los.
    -- Ficam só PK/UNIQUE (que existem no banco real desde o 01).
    FOR i IN
        SELECT x.indexrelid::regclass
        FROM pg_index x
        JOIN pg_class c ON c.oid = x.indrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'academico_perf' AND NOT x.indisunique AND NOT x.indisprimary
    LOOP
        EXECUTE format('DROP INDEX %s', i);
    END LOOP;
END $$;

SET search_path TO academico_perf, academico;   -- tipos (enum/domínios) vêm de academico
SELECT setseed(0.42);

-- 10 períodos (2022/1 a 2026/2); o 10 é o vigente.
INSERT INTO tb_periodo_letivo (id_periodo_letivo, ano, semestre, data_inicio, data_fim) OVERRIDING SYSTEM VALUE
SELECT p, 2022 + (p - 1) / 2, ((p - 1) % 2) + 1,
       make_date(2022 + (p - 1) / 2, CASE WHEN (p - 1) % 2 = 0 THEN 2 ELSE 8 END, 1),
       make_date(2022 + (p - 1) / 2, CASE WHEN (p - 1) % 2 = 0 THEN 6 ELSE 12 END, 20)
FROM generate_series(1, 10) AS p;

INSERT INTO tb_disciplina (id_disciplina, codigo, nome, ch_teorico, ch_pratica) OVERRIDING SYSTEM VALUE
SELECT d, 'DSC' || LPAD(d::text, 4, '0'), 'Disciplina ' || d, 30, 30
FROM generate_series(1, 120) AS d;

INSERT INTO tb_professor (id_professor, matricula_professor, nome_professor, email_professor, titulacao) OVERRIDING SYSTEM VALUE
SELECT p, 'P' || LPAD(p::text, 6, '0'), 'Professor ' || p, 'prof' || p || '@perf.test', 'MESTRE'
FROM generate_series(1, 150) AS p;

-- 9.600 turmas: 120 disciplinas x 8 turmas x 10 períodos.
INSERT INTO tb_turma (id_turma, id_disciplina, id_periodo_letivo, id_professor, codigo, turno, vagas) OVERRIDING SYSTEM VALUE
SELECT t, ((t - 1) % 120) + 1, ((t - 1) / 960) + 1, (t % 150) + 1,
       'T' || (((t - 1) / 120) % 8 + 1),
       (ARRAY['Matutino','Vespertino','Noturno'])[t % 3 + 1]::turno_t, 50
FROM generate_series(1, 9600) AS t;

-- 30.000 alunos com nomes brasileiros (para a busca por prefixo).
INSERT INTO tb_aluno (id_aluno, id_curriculo, cpf, nome_aluno, email_aluno, nascimento, ingresso_aluno, ativo_aluno) OVERRIDING SYSTEM VALUE
SELECT i, (i % 4) + 1, LPAD(i::text, 11, '0'),
       (ARRAY['Ana','Beatriz','Bruno','Camila','Carlos','Daniel','Eduardo','Fernanda','Gabriel','Helena',
              'Igor','Juliana','Larissa','Lucas','Mariana','Mateus','Nicolas','Rafaela','Thiago','Vitória'])[(i % 20) + 1]
       || ' ' ||
       (ARRAY['Silva','Santos','Oliveira','Souza','Lima','Pereira','Costa','Rodrigues','Almeida','Nascimento','Carvalho'])[(i % 11) + 1]
       || ' ' ||
       (ARRAY['Ferreira','Ribeiro','Martins','Araújo','Barbosa','Gomes','Cavalcanti','Moreira','Rocha','Dias','Teixeira','Machado','Monteiro'])[(i % 13) + 1],
       'aluno' || i || '@perf.test', DATE '1995-01-01' + (i % 4000), 2018 + (i % 9), true
FROM generate_series(1, 30000) AS i;

-- 240.000 matrículas (8 por aluno). Só as turmas do período 10 são 'Ativa'
-- (10% do total); o resto é histórico 'Concluida' (com ~2% 'Cancelada').
INSERT INTO tb_matricula (id_aluno, id_turma, data_matricula, status_matricula)
SELECT a.i, t.id,
       DATE '2022-02-01' + ((t.id - 1) / 960) * 182,
       CASE WHEN t.id > 8640 THEN 'Ativa'::status_mat_t
            WHEN (a.i + k) % 50 = 0 THEN 'Cancelada'::status_mat_t
            ELSE 'Concluida'::status_mat_t END
FROM generate_series(1, 30000) AS a(i)
CROSS JOIN generate_series(0, 7) AS k
CROSS JOIN LATERAL (SELECT ((a.i * 37 + k * 449) % 9600) + 1 AS id) AS t;

-- Um histórico por matrícula. Reprovação por falta ~3% (a seletividade que
-- justifica o índice parcial).
-- (random() fica na lista de colunas da subconsulta para ser sorteado POR LINHA;
--  num LATERAL sem referência à linha externa ele seria avaliado uma vez só.)
INSERT INTO tb_historico (id_matricula, nota_a1, nota_a2, nota_p3, frequencia, situacao)
SELECT n.id_matricula,
       n.a1, n.a2, NULL,
       CASE WHEN n.sorteio < 0.03 THEN ROUND((40 + n.r2 * 34)::numeric, 2)
            ELSE ROUND((75 + n.r2 * 25)::numeric, 2) END,
       CASE WHEN n.status_matricula = 'Ativa'     THEN 'Cursando'::situacao_t
            WHEN n.status_matricula = 'Cancelada' THEN NULL
            WHEN n.sorteio < 0.03                 THEN 'Reprovado por Falta'::situacao_t
            WHEN n.sorteio < 0.13                 THEN 'Reprovado por Nota'::situacao_t
            ELSE 'Aprovado'::situacao_t END
FROM (SELECT m.id_matricula, m.status_matricula,
             ROUND((random() * 10)::numeric, 2) AS a1,
             ROUND((random() * 10)::numeric, 2) AS a2,
             random() AS sorteio,
             random() AS r2
      FROM tb_matricula m) AS n;

-- 200.000 registros de log com detalhe em JSON (usado na evidência do GIN, bônus).
INSERT INTO tb_log_matricula (id_matricula, acao, usuario, detalhe)
SELECT ((i * 7) % 240000) + 1,
       (ARRAY['MATRICULA','STATUS_ALTERADO'])[(i % 2) + 1],
       'sistema',
       jsonb_build_object('origem',   (ARRAY['portal','secretaria','app'])[(i % 3) + 1],
                          'id_turma', ((i * 13) % 9600) + 1,
                          'ip',       '10.0.' || (i % 250) || '.' || (i % 200))::text
FROM generate_series(1, 200000) AS i;

VACUUM (ANALYZE) tb_periodo_letivo;
VACUUM (ANALYZE) tb_disciplina;
VACUUM (ANALYZE) tb_professor;
VACUUM (ANALYZE) tb_turma;
VACUUM (ANALYZE) tb_aluno;
VACUUM (ANALYZE) tb_matricula;
VACUUM (ANALYZE) tb_historico;
VACUUM (ANALYZE) tb_log_matricula;

\echo
\echo '-- Volume de teste (schema academico_perf):'
SELECT (SELECT COUNT(*) FROM tb_aluno)         AS alunos,
       (SELECT COUNT(*) FROM tb_turma)         AS turmas,
       (SELECT COUNT(*) FROM tb_matricula)     AS matriculas,
       (SELECT COUNT(*) FROM tb_matricula WHERE status_matricula = 'Ativa') AS matriculas_ativas,
       (SELECT COUNT(*) FROM tb_historico)     AS historicos,
       (SELECT COUNT(*) FROM tb_historico WHERE situacao = 'Reprovado por Falta') AS reprovados_falta,
       (SELECT COUNT(*) FROM tb_log_matricula) AS logs;

-----------------------------------------------------------------
-- 2. Consultas medidas e função de medição
-----------------------------------------------------------------
CREATE TEMP TABLE consultas (id int PRIMARY KEY, titulo text, sql text);

INSERT INTO consultas VALUES
(1, 'Histórico completo de um aluno',
 $q$SELECT d.nome, pl.ano, pl.semestre, h.media_geral, h.situacao
    FROM tb_matricula m
    JOIN tb_historico h ON h.id_matricula = m.id_matricula
    JOIN tb_turma t ON t.id_turma = m.id_turma
    JOIN tb_disciplina d ON d.id_disciplina = t.id_disciplina
    JOIN tb_periodo_letivo pl ON pl.id_periodo_letivo = t.id_periodo_letivo
    WHERE m.id_aluno = 12345
    ORDER BY pl.ano, pl.semestre$q$),
(2, 'Vagas ocupadas por turma (matrículas Ativas) - núcleo de v_vagas',
 $q$SELECT id_turma, COUNT(*) AS ocupadas
    FROM tb_matricula
    WHERE status_matricula = 'Ativa'
    GROUP BY id_turma$q$),
(3, 'Busca da secretaria por prefixo do nome (sem diferenciar maiúsculas)',
 $q$SELECT id_aluno, nome_aluno, email_aluno
    FROM tb_aluno
    WHERE lower(nome_aluno) LIKE 'mariana silva%'
    ORDER BY nome_aluno$q$),
(4, 'Os 20 casos mais graves de infrequência entre os reprovados por falta',
 $q$SELECT id_matricula, frequencia
    FROM tb_historico
    WHERE situacao = 'Reprovado por Falta'
    ORDER BY frequencia
    LIMIT 20$q$),
(5, '(bônus JSONB) Logs de uma turma originados na secretaria',
 $q$SELECT COUNT(*) AS registros
    FROM tb_log_matricula
    WHERE detalhe::jsonb @> '{"origem": "secretaria", "id_turma": 1234}'$q$);

CREATE TEMP TABLE resultados (indice text, consulta int, fase text, ms numeric, buffers bigint, nos_de_leitura text);

-- Executa a consulta 1x para aquecer o cache e mede 5x (guarda o MENOR tempo).
-- Lê tempo e buffers do EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON).
CREATE FUNCTION pg_temp.medir(q text, OUT ms numeric, OUT buffers bigint, OUT nos text)
LANGUAGE plpgsql AS $$
DECLARE
    j jsonb;
    t numeric;
BEGIN
    ms := NULL;
    FOR n IN 0..5 LOOP
        EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || q INTO j;
        t := (j -> 0 ->> 'Execution Time')::numeric;
        IF n > 0 AND (ms IS NULL OR t < ms) THEN
            ms := t;
            buffers := (j -> 0 -> 'Plan' ->> 'Shared Hit Blocks')::bigint
                     + (j -> 0 -> 'Plan' ->> 'Shared Read Blocks')::bigint;
        END IF;
    END LOOP;
    SELECT string_agg(DISTINCT x #>> '{}', ', ') INTO nos
    FROM jsonb_path_query(j, '$.**."Node Type"') AS x
    WHERE x #>> '{}' LIKE '%Scan%';
END $$;

-----------------------------------------------------------------
-- 3. Antes e depois de cada índice
-----------------------------------------------------------------
-- Cada bloco: [ANTES] EXPLAIN, mede -> CREATE INDEX -> [DEPOIS] EXPLAIN, mede.

\echo
\echo '#################################################################'
\echo '# ÍNDICE 1: idx_matricula_aluno  (consulta 1)'
\echo '#################################################################'
\echo '--- ANTES (sem o índice) ---'
SELECT 'EXPLAIN (ANALYZE, BUFFERS) ' || sql FROM consultas WHERE id = 1 \gexec
INSERT INTO resultados SELECT 'idx_matricula_aluno', 1, 'antes', m.ms, m.buffers, m.nos FROM pg_temp.medir((SELECT sql FROM consultas WHERE id = 1)) m;
SELECT replace(pg_get_indexdef('academico.idx_matricula_aluno'::regclass), ' ON academico.', ' ON academico_perf.') \gexec
ANALYZE tb_matricula;
\echo '--- DEPOIS (com o índice) ---'
SELECT 'EXPLAIN (ANALYZE, BUFFERS) ' || sql FROM consultas WHERE id = 1 \gexec
INSERT INTO resultados SELECT 'idx_matricula_aluno', 1, 'depois', m.ms, m.buffers, m.nos FROM pg_temp.medir((SELECT sql FROM consultas WHERE id = 1)) m;

\echo
\echo '#################################################################'
\echo '# ÍNDICE 2 (PARCIAL): idx_matricula_turma_ativa  (consulta 2)'
\echo '#################################################################'
\echo '--- ANTES (sem o índice) ---'
SELECT 'EXPLAIN (ANALYZE, BUFFERS) ' || sql FROM consultas WHERE id = 2 \gexec
INSERT INTO resultados SELECT 'idx_matricula_turma_ativa', 2, 'antes', m.ms, m.buffers, m.nos FROM pg_temp.medir((SELECT sql FROM consultas WHERE id = 2)) m;
SELECT replace(pg_get_indexdef('academico.idx_matricula_turma_ativa'::regclass), ' ON academico.', ' ON academico_perf.') \gexec
VACUUM (ANALYZE) tb_matricula;      -- mapa de visibilidade atualizado: permite index-only scan
\echo '--- DEPOIS (com o índice) ---'
SELECT 'EXPLAIN (ANALYZE, BUFFERS) ' || sql FROM consultas WHERE id = 2 \gexec
INSERT INTO resultados SELECT 'idx_matricula_turma_ativa', 2, 'depois', m.ms, m.buffers, m.nos FROM pg_temp.medir((SELECT sql FROM consultas WHERE id = 2)) m;
\echo '--- Tamanho: o índice parcial é muito menor que o total ---'
SELECT pg_size_pretty(pg_relation_size('academico_perf.idx_matricula_turma_ativa')) AS indice_parcial_ativas,
       pg_size_pretty(pg_relation_size('academico_perf.idx_matricula_aluno'))       AS indice_total_por_aluno,
       pg_size_pretty(pg_relation_size('academico_perf.tb_matricula'))              AS tabela;

\echo
\echo '#################################################################'
\echo '# ÍNDICE 3 (expressão): idx_aluno_nome_lower  (consulta 3)'
\echo '#################################################################'
\echo '--- ANTES (sem o índice) ---'
SELECT 'EXPLAIN (ANALYZE, BUFFERS) ' || sql FROM consultas WHERE id = 3 \gexec
INSERT INTO resultados SELECT 'idx_aluno_nome_lower', 3, 'antes', m.ms, m.buffers, m.nos FROM pg_temp.medir((SELECT sql FROM consultas WHERE id = 3)) m;
SELECT replace(pg_get_indexdef('academico.idx_aluno_nome_lower'::regclass), ' ON academico.', ' ON academico_perf.') \gexec
ANALYZE tb_aluno;
\echo '--- DEPOIS (com o índice) ---'
SELECT 'EXPLAIN (ANALYZE, BUFFERS) ' || sql FROM consultas WHERE id = 3 \gexec
INSERT INTO resultados SELECT 'idx_aluno_nome_lower', 3, 'depois', m.ms, m.buffers, m.nos FROM pg_temp.medir((SELECT sql FROM consultas WHERE id = 3)) m;

\echo
\echo '#################################################################'
\echo '# ÍNDICE 4 (PARCIAL + INCLUDE): idx_historico_reprovado_falta  (consulta 4)'
\echo '#################################################################'
\echo '--- ANTES (sem o índice) ---'
SELECT 'EXPLAIN (ANALYZE, BUFFERS) ' || sql FROM consultas WHERE id = 4 \gexec
INSERT INTO resultados SELECT 'idx_historico_reprovado_falta', 4, 'antes', m.ms, m.buffers, m.nos FROM pg_temp.medir((SELECT sql FROM consultas WHERE id = 4)) m;
SELECT replace(pg_get_indexdef('academico.idx_historico_reprovado_falta'::regclass), ' ON academico.', ' ON academico_perf.') \gexec
VACUUM (ANALYZE) tb_historico;
\echo '--- DEPOIS (com o índice) ---'
SELECT 'EXPLAIN (ANALYZE, BUFFERS) ' || sql FROM consultas WHERE id = 4 \gexec
INSERT INTO resultados SELECT 'idx_historico_reprovado_falta', 4, 'depois', m.ms, m.buffers, m.nos FROM pg_temp.medir((SELECT sql FROM consultas WHERE id = 4)) m;

\echo
\echo '#################################################################'
\echo '# BÔNUS - ÍNDICE GIN sobre JSONB: idx_log_detalhe_gin  (consulta 5)'
\echo '# (mesma definição de 09_bonus_jsonb_gin.sql)'
\echo '#################################################################'
\echo '--- ANTES (sem o índice) ---'
SELECT 'EXPLAIN (ANALYZE, BUFFERS) ' || sql FROM consultas WHERE id = 5 \gexec
INSERT INTO resultados SELECT 'idx_log_detalhe_gin', 5, 'antes', m.ms, m.buffers, m.nos FROM pg_temp.medir((SELECT sql FROM consultas WHERE id = 5)) m;
CREATE INDEX idx_log_detalhe_gin ON tb_log_matricula USING gin ((detalhe::jsonb) jsonb_path_ops);
ANALYZE tb_log_matricula;
\echo '--- DEPOIS (com o índice) ---'
SELECT 'EXPLAIN (ANALYZE, BUFFERS) ' || sql FROM consultas WHERE id = 5 \gexec
INSERT INTO resultados SELECT 'idx_log_detalhe_gin', 5, 'depois', m.ms, m.buffers, m.nos FROM pg_temp.medir((SELECT sql FROM consultas WHERE id = 5)) m;

-----------------------------------------------------------------
-- 4. Resumo do ganho medido
-----------------------------------------------------------------
\echo
\echo '================================================================='
\echo ' RESUMO DO GANHO MEDIDO (melhor de 5 execuções após 1 de aquecimento)'
\echo ' ms = Execution Time do EXPLAIN ANALYZE; buffers = blocos 8kB lidos (hit+read)'
\echo '================================================================='
\pset format aligned
SELECT a.indice,
       a.consulta                       AS q,
       a.ms                             AS antes_ms,
       d.ms                             AS depois_ms,
       ROUND(a.ms / NULLIF(d.ms, 0), 1) AS ganho_vezes,
       a.buffers                        AS antes_buffers,
       d.buffers                        AS depois_buffers,
       a.nos_de_leitura                 AS plano_antes,
       d.nos_de_leitura                 AS plano_depois
FROM resultados a
JOIN resultados d ON d.indice = a.indice AND d.fase = 'depois'
WHERE a.fase = 'antes'
ORDER BY a.consulta;

-----------------------------------------------------------------
-- 5. Limpeza (a cópia de volume não é mais necessária)
-----------------------------------------------------------------
RESET search_path;
DROP SCHEMA academico_perf CASCADE;
\echo
\echo 'Schema academico_perf removido. Fim das evidências.'
