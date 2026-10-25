-----------------------------------------------------------------
-- 06b_correcao_bloqueio.sql  (Marco 2 - Correção 1: BLOQUEIO EXPLÍCITO)
--
-- IDEIA (concorrência PESSIMISTA): quem vai decidir "ainda tem vaga?" primeiro
-- TRAVA a linha da turma (SELECT ... FOR UPDATE). As outras matrículas
-- para a mesma turma ESPERAM no próprio FOR UPDATE. Quando a primeira
-- confirma e libera o bloqueio, a seguinte executa o passo "checar" já
-- enxergando a matrícula recém-confirmada (em READ COMMITTED cada comando
-- tira uma foto nova) e responde SEM_VAGA. Resultado: checar+agir passa a ser
-- atômico por turma.
--
-- Por que a linha de tb_turma e não uma tabela inteira?
--   * é o recurso realmente disputado (as vagas da turma);
--   * só bloqueia matrículas DA MESMA TURMA: turmas diferentes não esperam
--     umas pelas outras (LOCK TABLE travaria o sistema todo);
--   * o bloqueio dura só até o fim da transação (COMMIT/ROLLBACK), então não
--     há como "esquecer" de soltar.
-- Alternativas equivalentes: pg_advisory_xact_lock(id_turma) ou
-- FOR NO KEY UPDATE (não conflita com os FOR KEY SHARE das chaves
-- estrangeiras de outras transações).
--
-- Rode APÓS 06_anomalia_vagas.sql (que cria o laboratório sp_simular_disputa).
-----------------------------------------------------------------
SET search_path TO academico, public;

CREATE OR REPLACE FUNCTION sp_matricular_bloqueio(p_id_aluno int, p_id_turma int, p_pausa numeric DEFAULT 0)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    v_vagas    int;
    v_ocupadas int;
BEGIN
    -- >>> CORREÇÃO: trava a turma ANTES de checar. Quem chegar depois espera aqui.
    SELECT vagas INTO v_vagas
    FROM tb_turma
    WHERE id_turma = p_id_turma
    FOR UPDATE;
    IF NOT FOUND THEN
        RETURN 'TURMA_INEXISTENTE';
    END IF;

    SELECT COUNT(*) INTO v_ocupadas
    FROM tb_matricula
    WHERE id_turma = p_id_turma AND status_matricula = 'Ativa';

    IF v_ocupadas >= v_vagas THEN
        RETURN 'SEM_VAGA';
    END IF;

    PERFORM pg_sleep(p_pausa);       -- a mesma pausa do experimento: agora ela fica DENTRO do bloqueio

    INSERT INTO tb_matricula (id_aluno, id_turma, status_matricula)
    VALUES (p_id_aluno, p_id_turma, 'Ativa');
    RETURN 'MATRICULADO';
END;
$$;

-----------------------------------------------------------------
-- Mesmo experimento do 06: 10 alunos disputam a última vaga da turma 1
-----------------------------------------------------------------
\echo '--- Disputa simultânea (10 sessões) com a correção por BLOQUEIO (FOR UPDATE) ---'
SELECT * FROM sp_simular_disputa('bloqueio');

\echo '--- Depois: turma lotada, sem overbooking ---'
SELECT id_turma, codigo_turma, disciplina, vagas, ocupadas, livres, situacao_vagas
FROM v_vagas WHERE id_turma = 1;

\echo '--- Quem conseguiu a vaga (exatamente 1 dos 10) ---'
SELECT a.id_aluno, a.nome_aluno, m.status_matricula
FROM tb_matricula m
JOIN tb_aluno a ON a.id_aluno = m.id_aluno
WHERE m.id_turma = 1 AND m.id_aluno BETWEEN 91 AND 100;

-- Restaura o estado original
SELECT sp_limpar_disputa();
