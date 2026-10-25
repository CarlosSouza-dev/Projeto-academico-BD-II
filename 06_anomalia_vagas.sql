-----------------------------------------------------------------
-- 06_anomalia_vagas.sql  (Marco 2 - Transações e Concorrência)
-- Reprodução da ANOMALIA na disputa pela última vaga de uma turma.
--
-- CENÁRIO (vem da carga do Marco 1): a turma 1 (Banco de Dados II) tem
-- 51 vagas e 50 alunos ativos: sobra 1 vaga. Os alunos 91 a 100 não têm
-- matrícula nenhuma e tentam entrar AO MESMO TEMPO nessa última vaga.
--
-- A ANOMALIA ("checar e depois agir", ou write skew):
--     1) SELECT count(*) ... -> vê 50 de 51, "tem vaga!"
--     2) INSERT INTO tb_matricula ...
--   Em READ COMMITTED (padrão do PostgreSQL) as duas sessões fazem o passo 1
--   antes de qualquer uma fazer o passo 2 (o INSERT de uma ainda não foi
--   confirmado, logo a outra não o enxerga). As duas inserem: 52, 53... em
--   51 vagas. Nenhuma constraint do modelo impede isso: o UNIQUE só impede o
--   MESMO aluno duas vezes, e o CHECK de vagas é por linha, não por contagem.
--
-- COMO ESTE SCRIPT REPRODUZ A DISPUTA EM SQL PURO (qualquer cliente):
--   usa a extensão dblink para abrir N conexões independentes e disparar as
--   N matrículas em paralelo (dblink_send_query é assíncrono). Cada conexão
--   é uma sessão/transação distinta, como N usuários reais.
--   Requisitos: extensão dblink (vem no contrib da imagem oficial do
--   PostgreSQL) e usuário com direito de criá-la (superusuário no Docker).
--   Se a conexão local pedir senha, passe p_conninfo, ex.:
--     SELECT * FROM sp_simular_disputa('ingenuo', p_conninfo => 'host=localhost user=bd2 password=... dbname=bd2');
--
-- ALTERNATIVA MANUAL (2 janelas do cliente), para explicar ao vivo:
--   Sessão A                                  Sessão B
--   BEGIN;                                    BEGIN;
--   SELECT count(*) FROM tb_matricula
--    WHERE id_turma=1 AND status_matricula='Ativa';  -- 50
--                                             SELECT count(*) ... ;  -- 50
--   INSERT INTO tb_matricula (id_aluno,id_turma,status_matricula) VALUES (91,1,'Ativa');
--                                             INSERT ... VALUES (92,1,'Ativa');
--   COMMIT;                                   COMMIT;
--   SELECT * FROM v_vagas WHERE id_turma=1;   -- ocupadas = 52 > vagas = 51
--
-- Rode APÓS 01 a 04. Este arquivo cria o laboratório (harness) usado
-- também por 06b, 06c e 06d. Ao final, devolve a turma ao estado original.
-----------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS dblink;      -- fica em public: sobrevive ao DROP SCHEMA academico
SET search_path TO academico, public;

-----------------------------------------------------------------
-- 1. Matrícula VERSÃO INGÊNUA (a que contém a anomalia)
-- p_pausa simula o tempo de processamento entre a verificação e a gravação
-- (validações, chamada a outro sistema...). Em produção a janela existe
-- mesmo sem pausa: ela só fica menor e o erro aparece de vez em quando.
-----------------------------------------------------------------
CREATE OR REPLACE FUNCTION sp_matricular_ingenuo(p_id_aluno int, p_id_turma int, p_pausa numeric DEFAULT 0)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_vagas    int;
    v_ocupadas int;
BEGIN
    SELECT vagas INTO v_vagas FROM tb_turma WHERE id_turma = p_id_turma;
    IF NOT FOUND THEN
        RETURN 'TURMA_INEXISTENTE';
    END IF;

    SELECT COUNT(*) INTO v_ocupadas                     -- (1) CHECA
    FROM tb_matricula
    WHERE id_turma = p_id_turma AND status_matricula = 'Ativa';

    IF v_ocupadas >= v_vagas THEN
        RETURN 'SEM_VAGA';
    END IF;

    PERFORM pg_sleep(p_pausa);                          -- janela da corrida

    INSERT INTO tb_matricula (id_aluno, id_turma, status_matricula)   -- (2) AGE
    VALUES (p_id_aluno, p_id_turma, 'Ativa');
    RETURN 'MATRICULADO';
END;
$$;

-----------------------------------------------------------------
-- 2. Limpeza: remove as matrículas criadas pelo experimento e devolve o
--    estado original (turma com 1 vaga livre, alunos 91-100 sem matrícula).
--    SEGURANÇA: só apaga matrículas SEM histórico. As matrículas reais da
--    carga têm linha em tb_historico; as do experimento não. Assim, mesmo
--    que alguém passe ids de alunos errados, nenhuma matrícula real é apagada.
-----------------------------------------------------------------
CREATE OR REPLACE FUNCTION sp_limpar_disputa(
    p_id_turma int   DEFAULT 1,
    p_alunos   int[] DEFAULT ARRAY[91,92,93,94,95,96,97,98,99,100])
RETURNS void
LANGUAGE sql
SET search_path = academico, public     -- também é chamada por sessões dblink, que não herdam o search_path
AS $$
    DELETE FROM tb_log_matricula
     WHERE id_matricula IN (SELECT m.id_matricula FROM tb_matricula m
                             WHERE m.id_turma = p_id_turma AND m.id_aluno = ANY (p_alunos)
                               AND NOT EXISTS (SELECT 1 FROM tb_historico h WHERE h.id_matricula = m.id_matricula));
    DELETE FROM tb_matricula m
     WHERE m.id_turma = p_id_turma AND m.id_aluno = ANY (p_alunos)
       AND NOT EXISTS (SELECT 1 FROM tb_historico h WHERE h.id_matricula = m.id_matricula);
$$;

-----------------------------------------------------------------
-- 3. Laboratório: sp_simular_disputa
-- Dispara, em paralelo, uma matrícula por aluno de p_alunos na mesma turma
-- e mede o resultado. Modos: 'ingenuo' (06), 'bloqueio' (06b) e
-- 'serializable' (06c) -> chama sp_matricular_<modo>.
--
--   p_vagas_livres : quantas vagas livres a turma tem durante o teste
--                    (1 = a "última vaga"; as vagas originais são restauradas)
--   p_pausa        : pausa dentro da matrícula (segundos)
--   p_max_rodadas  : limite de rodadas de retentativa (modo serializable)
--
-- Usa uma conexão de CONTROLE separada para preparar/ler/restaurar o estado,
-- porque as sessões concorrentes só enxergam dados já CONFIRMADOS (COMMIT).
-- Retentativa: quando a transação falha com serialization_failure (40001) ou
-- deadlock_detected (40P01), o laboratório refaz a chamada, como faria uma
-- aplicação correta.
-----------------------------------------------------------------
CREATE OR REPLACE FUNCTION sp_simular_disputa(
    p_modo         text,
    p_id_turma     int     DEFAULT 1,
    p_alunos       int[]   DEFAULT ARRAY[91,92,93,94,95,96,97,98,99,100],
    p_vagas_livres int     DEFAULT 1,
    p_pausa        numeric DEFAULT 0.3,
    p_max_rodadas  int     DEFAULT 30,
    p_conninfo     text    DEFAULT NULL)
RETURNS TABLE (
    modo                  text,
    concorrentes          int,
    vagas_livres_iniciais int,
    matriculados          int,
    sem_vaga              int,
    retentativas          int,
    vagas_no_teste        int,
    ocupadas_final        int,
    overbooking           int,
    duracao_ms            numeric,
    resultado             text)
LANGUAGE plpgsql
AS $$
DECLARE
    v_conn        text;
    v_fn          text := format('academico.sp_matricular_%s', p_modo);
    v_n           int  := cardinality(p_alunos);
    v_vagas_orig  int;
    v_ocup_base   bigint;
    v_ocup_final  bigint;
    v_pend        int[];
    v_novos       int[];
    v_i           int;
    v_r           text;
    v_c           text;
    v_ok          int := 0;
    v_sem         int := 0;
    v_ret         int := 0;
    v_rodada      int := 0;
    v_t0          timestamptz;
    v_t1          timestamptz;
    v_vagas_teste int;
    v_over        int;
BEGIN
    IF p_modo NOT IN ('ingenuo', 'bloqueio', 'serializable') THEN
        RAISE EXCEPTION 'modo inválido: % (use ingenuo, bloqueio ou serializable)', p_modo;
    END IF;

    -- Conexão das sessões concorrentes: por padrão, o MESMO servidor (socket
    -- unix e porta do servidor atual), mesmo banco e mesmo usuário.
    IF p_conninfo IS NOT NULL THEN
        v_conn := p_conninfo;
    ELSE
        v_conn := format('dbname=%s user=%s port=%s', current_database(), session_user, current_setting('port'));
        BEGIN
            v_conn := v_conn || ' host=' || trim(split_part(current_setting('unix_socket_directories'), ',', 1));
        EXCEPTION WHEN OTHERS THEN
            NULL;       -- sem permissão para ler a configuração: usa o socket padrão do libpq
        END;
    END IF;

    -- Sobras de uma execução anterior interrompida
    FOREACH v_c IN ARRAY COALESCE(dblink_get_connections(), '{}') LOOP
        IF v_c = 'ctl' OR v_c LIKE 'disp\_%' THEN
            PERFORM dblink_disconnect(v_c);
        END IF;
    END LOOP;

    SELECT t.vagas INTO v_vagas_orig FROM tb_turma t WHERE t.id_turma = p_id_turma;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'turma % não existe', p_id_turma;
    END IF;

    -- Proteção: o laboratório apaga as matrículas dos concorrentes na turma
    -- para partir do zero. Recusa se alguma for uma matrícula REAL (com histórico).
    PERFORM 1
    FROM tb_matricula m
    JOIN tb_historico h ON h.id_matricula = m.id_matricula
    WHERE m.id_turma = p_id_turma AND m.id_aluno = ANY (p_alunos);
    IF FOUND THEN
        RAISE EXCEPTION 'algum aluno de p_alunos já tem matrícula real (com histórico) na turma %; use alunos sem matrícula (91 a 100 na carga padrão)', p_id_turma;
    END IF;

    BEGIN
        -- Conexão de controle (cada comando dela é confirmado na hora)
        PERFORM dblink_connect('ctl', v_conn);
        PERFORM dblink_exec('ctl', 'SET search_path TO academico, public');

        -- Estado inicial: sem matrículas (de experimento) dos concorrentes na turma
        PERFORM 1 FROM dblink('ctl', format(
            'SELECT academico.sp_limpar_disputa(%s, %L)', p_id_turma, p_alunos)) AS x(r text);

        SELECT x.n INTO v_ocup_base
        FROM dblink('ctl', format(
            'SELECT count(*) FROM academico.tb_matricula WHERE id_turma = %s AND status_matricula = ''Ativa''',
            p_id_turma)) AS x(n bigint);

        -- Durante o teste, a turma tem exatamente p_vagas_livres vagas sobrando
        v_vagas_teste := v_ocup_base + p_vagas_livres;
        PERFORM dblink_exec('ctl', format(
            'UPDATE academico.tb_turma SET vagas = %s WHERE id_turma = %s', v_vagas_teste, p_id_turma));

        -- Uma sessão independente por aluno concorrente
        FOR v_i IN 1..v_n LOOP
            PERFORM dblink_connect('disp_' || v_i, v_conn);
            PERFORM dblink_exec('disp_' || v_i, 'SET search_path TO academico, public');
            IF p_modo = 'serializable' THEN
                -- cada comando dessa sessão roda em uma transação SERIALIZABLE
                PERFORM dblink_exec('disp_' || v_i, 'SET default_transaction_isolation TO serializable');
            END IF;
        END LOOP;

        -- Rodadas: dispara todos os pendentes em paralelo e recolhe os resultados
        v_pend := ARRAY(SELECT generate_series(1, v_n));
        v_t0   := clock_timestamp();
        WHILE cardinality(v_pend) > 0 AND v_rodada < p_max_rodadas LOOP
            v_rodada := v_rodada + 1;

            FOREACH v_i IN ARRAY v_pend LOOP
                PERFORM dblink_send_query('disp_' || v_i,
                    format('SELECT %s(%s, %s, %s)', v_fn, p_alunos[v_i], p_id_turma, p_pausa));
            END LOOP;

            v_novos := '{}';
            FOREACH v_i IN ARRAY v_pend LOOP
                BEGIN
                    SELECT x.r INTO v_r FROM dblink_get_result('disp_' || v_i, true) AS x(r text);
                    PERFORM 1 FROM dblink_get_result('disp_' || v_i, true) AS x(r text);  -- drena o fim do resultado
                    IF v_r = 'MATRICULADO' THEN
                        v_ok := v_ok + 1;
                    ELSIF v_r = 'SEM_VAGA' THEN
                        v_sem := v_sem + 1;
                    END IF;
                EXCEPTION WHEN serialization_failure OR deadlock_detected THEN
                    v_ret   := v_ret + 1;                 -- falhou por conflito: precisa tentar de novo
                    v_novos := v_novos || v_i;
                    BEGIN
                        PERFORM 1 FROM dblink_get_result('disp_' || v_i, false) AS x(r text);  -- limpa a conexão
                    EXCEPTION WHEN OTHERS THEN NULL;
                    END;
                END;
            END LOOP;
            v_pend := v_novos;
        END LOOP;
        v_t1 := clock_timestamp();

        -- Resultado final (lido pela conexão de controle) e restauração das vagas
        SELECT x.n INTO v_ocup_final
        FROM dblink('ctl', format(
            'SELECT count(*) FROM academico.tb_matricula WHERE id_turma = %s AND status_matricula = ''Ativa''',
            p_id_turma)) AS x(n bigint);
        PERFORM dblink_exec('ctl', format(
            'UPDATE academico.tb_turma SET vagas = %s WHERE id_turma = %s', v_vagas_orig, p_id_turma));

        FOR v_i IN 1..v_n LOOP
            PERFORM dblink_disconnect('disp_' || v_i);
        END LOOP;
        PERFORM dblink_disconnect('ctl');
    EXCEPTION WHEN OTHERS THEN
        -- Qualquer erro: restaura as vagas e fecha as conexões antes de propagar
        BEGIN
            IF 'ctl' = ANY (COALESCE(dblink_get_connections(), '{}')) THEN
                PERFORM dblink_exec('ctl', format(
                    'UPDATE academico.tb_turma SET vagas = %s WHERE id_turma = %s', v_vagas_orig, p_id_turma));
            END IF;
            FOREACH v_c IN ARRAY COALESCE(dblink_get_connections(), '{}') LOOP
                IF v_c = 'ctl' OR v_c LIKE 'disp\_%' THEN
                    PERFORM dblink_disconnect(v_c);
                END IF;
            END LOOP;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
        RAISE;
    END;

    v_over := GREATEST(v_ocup_final - v_vagas_teste, 0);
    RETURN QUERY SELECT
        p_modo,
        v_n,
        p_vagas_livres,
        v_ok,
        v_sem,
        v_ret,
        v_vagas_teste,
        v_ocup_final::int,
        v_over,
        ROUND(EXTRACT(epoch FROM (v_t1 - v_t0)) * 1000, 0),
        CASE WHEN v_over > 0 THEN 'ANOMALIA: overbooking de ' || v_over || ' matrícula(s)'
             WHEN cardinality(v_pend) > 0 THEN 'INCOMPLETO: ' || cardinality(v_pend) || ' sessão(ões) sem resposta'
             ELSE 'OK: nenhuma vaga além do limite' END;
END;
$$;

-----------------------------------------------------------------
-- 4. REPRODUZINDO A ANOMALIA: 10 alunos disputam a última vaga da turma 1
-----------------------------------------------------------------
\echo '--- Antes: turma 1 com 1 vaga livre ---'
SELECT id_turma, codigo_turma, disciplina, vagas, ocupadas, livres, situacao_vagas
FROM v_vagas WHERE id_turma = 1;

\echo '--- Disputa simultânea (10 sessões, versão ingênua, READ COMMITTED) ---'
SELECT * FROM sp_simular_disputa('ingenuo');

\echo '--- Depois: a view v_vagas denuncia o overbooking (ocupadas > vagas) ---'
SELECT id_turma, codigo_turma, disciplina, vagas, ocupadas, livres, situacao_vagas
FROM v_vagas WHERE id_turma = 1;

-- Restaura o estado original (alunos 91-100 sem matrícula na turma 1)
SELECT sp_limpar_disputa();
