-----------------------------------------------------------------
-- 06c_correcao_isolamento.sql  (Marco 2 - Correção 2: NÍVEL DE ISOLAMENTO)
--
-- IDEIA (concorrência OTIMISTA): ninguém espera. Todas as transações rodam
-- em SERIALIZABLE; o PostgreSQL (Serializable Snapshot Isolation, SSI)
-- registra o que cada uma LEU (a contagem de ocupadas) e o que ESCREVEU
-- (a nova matrícula). Se detecta que o resultado não equivale a nenhuma
-- execução uma-por-vez, ABORTA uma das transações com
--     ERROR 40001: could not serialize access due to read/write dependencies
-- A aplicação PRECISA capturar o erro e REPETIR a transação inteira. Na
-- repetição a vaga já foi tomada e a resposta correta (SEM_VAGA) aparece.
--
-- Repare: o corpo da função é IDÊNTICO ao da versão ingênua. A correção está
-- toda no nível de isolamento (e no laço de retentativa de quem chama),
-- não em uma mudança de lógica.
--
-- Rode APÓS 06_anomalia_vagas.sql (que cria o laboratório sp_simular_disputa).
-----------------------------------------------------------------
SET search_path TO academico, public;

CREATE OR REPLACE FUNCTION sp_matricular_serializable(p_id_aluno int, p_id_turma int, p_pausa numeric DEFAULT 0)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_vagas    int;
    v_ocupadas int;
BEGIN
    -- Trava de segurança: sem SERIALIZABLE, esta função teria a anomalia do 06.
    IF current_setting('transaction_isolation') <> 'serializable' THEN
        RAISE EXCEPTION 'sp_matricular_serializable exige transação SERIALIZABLE (atual: %)',
                        current_setting('transaction_isolation');
    END IF;

    SELECT vagas INTO v_vagas FROM tb_turma WHERE id_turma = p_id_turma;
    IF NOT FOUND THEN
        RETURN 'TURMA_INEXISTENTE';
    END IF;

    SELECT COUNT(*) INTO v_ocupadas
    FROM tb_matricula
    WHERE id_turma = p_id_turma AND status_matricula = 'Ativa';

    IF v_ocupadas >= v_vagas THEN
        RETURN 'SEM_VAGA';
    END IF;

    PERFORM pg_sleep(p_pausa);

    INSERT INTO tb_matricula (id_aluno, id_turma, status_matricula)
    VALUES (p_id_aluno, p_id_turma, 'Ativa');
    RETURN 'MATRICULADO';
END;
$$;

-- COMO A APLICAÇÃO USA (pseudocódigo do laço de retentativa que o
-- laboratório sp_simular_disputa executa por você):
--
--   repita:
--       BEGIN ISOLATION LEVEL SERIALIZABLE;
--       SELECT sp_matricular_serializable(:aluno, :turma);
--       COMMIT;                          -- o erro 40001 pode vir no INSERT ou no COMMIT
--   se erro SQLSTATE 40001 (serialization_failure) ou 40P01 (deadlock_detected):
--       ROLLBACK e repita desde o BEGIN (com limite de tentativas)

-----------------------------------------------------------------
-- Mesmo experimento do 06: 10 alunos disputam a última vaga da turma 1
-----------------------------------------------------------------
\echo '--- Disputa simultânea (10 sessões) com a correção por SERIALIZABLE + retentativa ---'
SELECT * FROM sp_simular_disputa('serializable');

\echo '--- Depois: turma lotada, sem overbooking ---'
SELECT id_turma, codigo_turma, disciplina, vagas, ocupadas, livres, situacao_vagas
FROM v_vagas WHERE id_turma = 1;

\echo '--- Quem conseguiu a vaga (exatamente 1 dos 10) ---'
SELECT a.id_aluno, a.nome_aluno, m.status_matricula
FROM tb_matricula m
JOIN tb_aluno a ON a.id_aluno = m.id_aluno
WHERE m.id_turma = 1 AND m.id_aluno BETWEEN 91 AND 100;

\echo '--- A trava de segurança funciona: chamar fora de SERIALIZABLE é recusado ---'
DO $$
BEGIN
    PERFORM sp_matricular_serializable(91, 1);
EXCEPTION WHEN raise_exception THEN
    RAISE NOTICE 'OK, recusado: %', SQLERRM;
END $$;

-- Restaura o estado original
SELECT sp_limpar_disputa();
