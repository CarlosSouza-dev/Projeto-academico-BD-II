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
-- COMO EXECUTAR
--   pgAdmin (Query Tool): abra o arquivo e execute TUDO (F5). Leva cerca de 10 s.
--     * Aba "Messages": os planos EXPLAIN completos (antes/depois de cada índice).
--     * Aba "Data Output": o quadro-resumo do ganho (é a última consulta).
--     * Os planos também ficam na tabela temporária "planos": execute
--         SELECT linha FROM planos ORDER BY ordem;
--       e use o botão "Download as CSV" para guardar como evidência.
--   psql / Docker (gera o arquivo evidencias_explain.txt):
--     docker compose exec -T <servico> psql -q -U <usuario> -d <banco> < 05b_evidencias_explain.sql > evidencias_explain.txt 2>&1
--     (no psql os planos saem como "NOTICE:" e o aviso "no transaction in progress" do COMMIT é inofensivo)
--
-- Este arquivo é SQL puro (sem comandos \ do psql), por isso roda no pgAdmin.
-- O pgAdmin envia o arquivo inteiro como UM comando, e por isso:
--   * os COMMIT abaixo são necessários (tornam a carga visível à outra sessão,
--     que executa o VACUUM; o VACUUM não pode rodar dentro de transação);
--   * só o resultado da ÚLTIMA consulta aparece em "Data Output".
--
-- Os tempos variam de máquina para máquina: gere a evidência no ambiente
-- Docker oficial antes da apresentação.
-----------------------------------------------------------------
-- dblink: usado apenas para rodar o VACUUM numa sessão separada.
DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS dblink;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'dblink indisponivel (%): o VACUUM será pulado e o plano 2 usará Index Scan em vez de Index Only Scan', SQLERRM;
END $$;

DO $$
BEGIN
    IF to_regclass('academico.idx_matricula_aluno') IS NULL THEN
        RAISE EXCEPTION 'Rode 01 a 05 (principalmente 05_indices.sql) antes deste script.';
    END IF;
    RAISE NOTICE '=================================================================';
    RAISE NOTICE ' EVIDÊNCIAS DE DESEMPENHO - EXPLAIN (ANALYZE, BUFFERS)';
    RAISE NOTICE ' Servidor: %', version();
    RAISE NOTICE ' Gerado em: %', now()::timestamp(0);
    RAISE NOTICE '=================================================================';
END $$;

SET jit = off;                         -- evita ruído de compilação JIT nos tempos
SET client_min_messages = notice;

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
DO $$ BEGIN PERFORM setseed(0.42); END $$;       -- sorteios reproduzíveis

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

-- COMMIT: a carga precisa estar confirmada para a OUTRA sessão (dblink) enxergá-la.
COMMIT;

-- VACUUM (ANALYZE) não pode rodar dentro de transação nem em comando múltiplo
-- (caso do pgAdmin); por isso roda numa sessão separada via dblink. Ele grava o
-- "mapa de visibilidade", que permite o Index Only Scan nos índices 2 e 4.
CREATE OR REPLACE FUNCTION pg_temp.vacuum_externo(p_tabelas text[]) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_conn text;
    t      text;
BEGIN
    v_conn := format('dbname=%s user=%s port=%s', current_database(), session_user, current_setting('port'));
    BEGIN
        v_conn := v_conn || ' host=' || trim(split_part(current_setting('unix_socket_directories'), ',', 1));
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    FOREACH t IN ARRAY p_tabelas LOOP
        PERFORM public.dblink_exec(v_conn, format('VACUUM (ANALYZE) academico_perf.%I', t));
    END LOOP;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'VACUUM externo não executado (%). Seguindo só com ANALYZE.', SQLERRM;
    FOREACH t IN ARRAY p_tabelas LOOP
        EXECUTE format('ANALYZE academico_perf.%I', t);
    END LOOP;
END $$;

DO $$
BEGIN
    PERFORM pg_temp.vacuum_externo(ARRAY['tb_periodo_letivo','tb_disciplina','tb_professor','tb_turma',
                                         'tb_aluno','tb_matricula','tb_historico','tb_log_matricula']);
END $$;

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '-- Volume de teste (schema academico_perf): % alunos, % turmas, % matrículas (% ativas), % históricos (% reprovados por falta), % logs',
        (SELECT COUNT(*) FROM academico_perf.tb_aluno),
        (SELECT COUNT(*) FROM academico_perf.tb_turma),
        (SELECT COUNT(*) FROM academico_perf.tb_matricula),
        (SELECT COUNT(*) FROM academico_perf.tb_matricula WHERE status_matricula = 'Ativa'),
        (SELECT COUNT(*) FROM academico_perf.tb_historico),
        (SELECT COUNT(*) FROM academico_perf.tb_historico WHERE situacao = 'Reprovado por Falta'),
        (SELECT COUNT(*) FROM academico_perf.tb_log_matricula);
END $$;

-----------------------------------------------------------------
-- 2. Consultas medidas e função de medição
-----------------------------------------------------------------
DROP TABLE IF EXISTS pg_temp.consultas, pg_temp.resultados, pg_temp.planos;
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
CREATE TEMP TABLE planos (ordem serial, linha text);

-- Executa a consulta 1x para aquecer o cache e mede 5x (guarda o MENOR tempo).
-- Lê tempo e buffers do EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON).
CREATE OR REPLACE FUNCTION pg_temp.medir(q text, OUT ms numeric, OUT buffers bigint, OUT nos text)
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
-- pg_temp.escrever: mostra uma linha na aba Messages e guarda em "planos".
CREATE OR REPLACE FUNCTION pg_temp.escrever(p_linha text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    RAISE NOTICE '%', p_linha;
    INSERT INTO pg_temp.planos (linha) VALUES (p_linha);
END $$;

-- pg_temp.explicar: executa EXPLAIN (ANALYZE, BUFFERS) e escreve o plano.
-- (substitui o \gexec do psql, que o pgAdmin não entende)
CREATE OR REPLACE FUNCTION pg_temp.explicar(p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    r record;
BEGIN
    FOR r IN EXECUTE 'EXPLAIN (ANALYZE, BUFFERS) ' || p_sql LOOP
        PERFORM pg_temp.escrever(r."QUERY PLAN");
    END LOOP;
END $$;

-- pg_temp.prova: [ANTES] explica e mede -> cria o índice -> [DEPOIS] explica e mede.
-- p_ddl NULL = lê a definição do índice criado pelo 05_indices.sql (trocando o
-- schema para academico_perf).
CREATE OR REPLACE PROCEDURE pg_temp.prova(p_titulo text, p_indice text, p_consulta int, p_tabela text, p_ddl text DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE
    v_sql text := (SELECT sql FROM pg_temp.consultas WHERE id = p_consulta);
BEGIN
    PERFORM pg_temp.escrever('');
    PERFORM pg_temp.escrever('#################################################################');
    PERFORM pg_temp.escrever('# ' || p_titulo);
    PERFORM pg_temp.escrever('#################################################################');
    PERFORM pg_temp.escrever('--- ANTES (sem o índice) ---');
    PERFORM pg_temp.explicar(v_sql);
    INSERT INTO pg_temp.resultados SELECT p_indice, p_consulta, 'antes', m.ms, m.buffers, m.nos FROM pg_temp.medir(v_sql) m;

    IF p_ddl IS NULL THEN
        EXECUTE replace(pg_get_indexdef(('academico.' || p_indice)::regclass), ' ON academico.', ' ON academico_perf.');
    ELSE
        EXECUTE p_ddl;
    END IF;
    EXECUTE 'ANALYZE academico_perf.' || p_tabela;

    PERFORM pg_temp.escrever('--- DEPOIS (com o índice) ---');
    PERFORM pg_temp.explicar(v_sql);
    INSERT INTO pg_temp.resultados SELECT p_indice, p_consulta, 'depois', m.ms, m.buffers, m.nos FROM pg_temp.medir(v_sql) m;
END $$;

CALL pg_temp.prova('ÍNDICE 1: idx_matricula_aluno  (consulta 1)',
                   'idx_matricula_aluno', 1, 'tb_matricula');

CALL pg_temp.prova('ÍNDICE 2 (PARCIAL): idx_matricula_turma_ativa  (consulta 2)',
                   'idx_matricula_turma_ativa', 2, 'tb_matricula');

DO $$
BEGIN
    PERFORM pg_temp.escrever('--- Tamanho: o índice parcial é muito menor que o total ---');
    PERFORM pg_temp.escrever(format('índice parcial (ativas): %s | índice total por aluno: %s | tabela: %s',
        pg_size_pretty(pg_relation_size('academico_perf.idx_matricula_turma_ativa')),
        pg_size_pretty(pg_relation_size('academico_perf.idx_matricula_aluno')),
        pg_size_pretty(pg_relation_size('academico_perf.tb_matricula'))));
END $$;

CALL pg_temp.prova('ÍNDICE 3 (expressão): idx_aluno_nome_lower  (consulta 3)',
                   'idx_aluno_nome_lower', 3, 'tb_aluno');

CALL pg_temp.prova('ÍNDICE 4 (PARCIAL + INCLUDE): idx_historico_reprovado_falta  (consulta 4)',
                   'idx_historico_reprovado_falta', 4, 'tb_historico');

CALL pg_temp.prova('BÔNUS - ÍNDICE GIN sobre JSONB: idx_log_detalhe_gin  (consulta 5; mesma definição do 09_bonus_jsonb_gin.sql)',
                   'idx_log_detalhe_gin', 5, 'tb_log_matricula',
                   'CREATE INDEX idx_log_detalhe_gin ON academico_perf.tb_log_matricula USING gin ((detalhe::jsonb) jsonb_path_ops)');

-----------------------------------------------------------------
-- 4. Limpeza (a cópia de volume não é mais necessária) e resumo do ganho
-- O resumo é a ÚLTIMA instrução de propósito: é o que o pgAdmin mostra em
-- "Data Output". Os dados dele estão na tabela temporária "resultados".
-----------------------------------------------------------------
RESET search_path;
DROP SCHEMA academico_perf CASCADE;

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE 'Schema academico_perf removido. RESUMO DO GANHO MEDIDO = último resultado (melhor de 5 execuções após 1 de aquecimento).';
    RAISE NOTICE 'ms = Execution Time do EXPLAIN ANALYZE; buffers = blocos de 8 kB lidos (hit + read).';
END $$;

SELECT a.indice,
       a.consulta                       AS q,
       a.ms                             AS antes_ms,
       d.ms                             AS depois_ms,
       ROUND(a.ms / NULLIF(d.ms, 0), 1) AS ganho_vezes,
       a.buffers                        AS antes_buffers,
       d.buffers                        AS depois_buffers,
       a.nos_de_leitura                 AS plano_antes,
       d.nos_de_leitura                 AS plano_depois
FROM pg_temp.resultados a
JOIN pg_temp.resultados d ON d.indice = a.indice AND d.fase = 'depois'
WHERE a.fase = 'antes'
ORDER BY a.consulta;
