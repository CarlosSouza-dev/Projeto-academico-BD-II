-----------------------------------------------------------------
-- 06b_correcao_bloqueio.sql  (Marco 2 - Correção 1: BLOQUEIO EXPLÍCITO)
--
-- IDEIA: antes de checar as vagas, a matrícula TRAVA a linha da turma com
-- SELECT ... FOR UPDATE. Uma segunda matrícula na MESMA turma fica
-- ESPERANDO nesse SELECT até a primeira terminar (COMMIT). Quando ela
-- continua, a contagem já inclui a matrícula da primeira: 51 de 51, sem vaga.
-- Checar + agir passa a acontecer um de cada vez por turma.
--
-- Por que travar a linha da turma?
--   * é o recurso disputado (as vagas daquela turma);
--   * só trava matrículas da MESMA turma: as outras turmas seguem normais;
--   * a trava é solta sozinha no fim da transação (COMMIT ou ROLLBACK).
--
-- Rode APÓS o 06_anomalia_vagas.sql.
-----------------------------------------------------------------
SET search_path TO academico;

-- Igual à sp_matricular_ingenuo, com UMA diferença: o FOR UPDATE.
CREATE OR REPLACE PROCEDURE sp_matricular_bloqueio(p_id_aluno INT, p_id_turma INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_vagas    INT;
    v_ocupadas INT;
BEGIN
    -- CORREÇÃO: trava a linha da turma. Quem chegar depois espera aqui.
    SELECT vagas INTO v_vagas
      FROM tb_turma
     WHERE id_turma = p_id_turma
       FOR UPDATE;

    SELECT COUNT(*) INTO v_ocupadas
      FROM tb_matricula
     WHERE id_turma = p_id_turma
       AND status_matricula = 'Ativa';

    IF v_ocupadas >= v_vagas THEN
        RAISE EXCEPTION 'Turma % sem vaga: % ocupadas de % vagas', p_id_turma, v_ocupadas, v_vagas;
    END IF;

    PERFORM pg_sleep(5);      -- a mesma demora do 06, agora DENTRO da trava

    INSERT INTO tb_matricula (id_aluno, id_turma, status_matricula)
    VALUES (p_id_aluno, p_id_turma, 'Ativa');

    RAISE NOTICE 'Aluno % matriculado na turma % (viu % ocupadas de % vagas)', p_id_aluno, p_id_turma, v_ocupadas, v_vagas;
END;
$$;

SELECT * FROM v_vagas WHERE id_turma = 1;


/*-----------------------------------------------------------------
DEMONSTRAÇÃO AO VIVO (2 abas do Query Tool; nas duas: SET search_path TO academico;)

PASSO 1 - Aba A:
CALL sp_matricular_bloqueio(91, 1);

PASSO 2 - Aba B, logo em seguida:
CALL sp_matricular_bloqueio(92, 1);

Resultado: a Aba B fica "rodando" (esperando a trava) até a Aba A terminar.
Depois a Aba B recebe o erro "Turma 1 sem vaga: 51 ocupadas de 51 vagas".

PASSO 3 - ocupadas = 51 para 51 vagas -> LOTADA, sem overbooking
SELECT * FROM v_vagas WHERE id_turma = 1;

PASSO 4 - limpeza
DELETE FROM tb_log_matricula WHERE id_matricula IN
    (SELECT id_matricula FROM tb_matricula WHERE id_turma = 1 AND id_aluno BETWEEN 91 AND 100);
DELETE FROM tb_matricula WHERE id_turma = 1 AND id_aluno BETWEEN 91 AND 100;
-----------------------------------------------------------------*/
