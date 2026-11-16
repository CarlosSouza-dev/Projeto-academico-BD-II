-----------------------------------------------------------------
-- 06_anomalia_vagas.sql  (Marco 2 - Transações e Concorrência)
-- Reprodução da ANOMALIA na disputa pela última vaga de uma turma.
--
-- CENÁRIO (vem da carga do 02): a turma 1 tem 51 vagas e 50 matrículas
-- ativas, então sobra 1 vaga. Os alunos 91 a 100 não têm matrícula.
--
-- A MATRÍCULA FAZ DOIS PASSOS:
--   1) CHECA: conta as matrículas ativas e compara com as vagas;
--   2) AGE:   se tem vaga, insere a matrícula.
-- No nível de isolamento padrão do PostgreSQL (READ COMMITTED), uma sessão
-- não enxerga o que a outra ainda não confirmou (COMMIT). Se duas sessões
-- fizerem o passo 1 ao mesmo tempo, as duas contam 50, as duas acham que
-- tem vaga e as duas inserem: 52 matrículas em 51 vagas (overbooking).
-- Nenhuma constraint impede isso: o UNIQUE só barra o MESMO aluno duas vezes,
-- e o CHECK (vagas >= 0) olha uma linha, não a contagem.
--
-- COMO EXECUTAR: rode o arquivo inteiro (F5) para criar a procedure.
-- A demonstração está no bloco comentado no fim (precisa de 2 abas).
-----------------------------------------------------------------
SET search_path TO academico;

-- Matrícula SEM controle de concorrência (a versão com o problema).
-- O pg_sleep(5) simula o tempo que o sistema leva entre checar e gravar
-- (validações, pagamento...). Sem ele o problema também acontece, mas a
-- janela é tão curta que fica difícil de reproduzir com as mãos.
CREATE OR REPLACE PROCEDURE sp_matricular_ingenuo(p_id_aluno INT, p_id_turma INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_vagas    INT;
    v_ocupadas INT;
BEGIN
    SELECT vagas INTO v_vagas
      FROM tb_turma
     WHERE id_turma = p_id_turma;

    -- (1) CHECA
    SELECT COUNT(*) INTO v_ocupadas
      FROM tb_matricula
     WHERE id_turma = p_id_turma
       AND status_matricula = 'Ativa';

    IF v_ocupadas >= v_vagas THEN
        RAISE EXCEPTION 'Turma % sem vaga: % ocupadas de % vagas', p_id_turma, v_ocupadas, v_vagas;
    END IF;

    PERFORM pg_sleep(5);      -- PERFORM: executa a função e descarta o resultado

    -- (2) AGE
    INSERT INTO tb_matricula (id_aluno, id_turma, status_matricula)
    VALUES (p_id_aluno, p_id_turma, 'Ativa');

    RAISE NOTICE 'Aluno % matriculado na turma % (viu % ocupadas de % vagas)', p_id_aluno, p_id_turma, v_ocupadas, v_vagas;
END;
$$;

-- Situação da turma 1 antes da disputa: 50 de 51, COM VAGAS
SELECT * FROM v_vagas WHERE id_turma = 1;


/*-----------------------------------------------------------------
DEMONSTRAÇÃO AO VIVO (selecione cada trecho SEM os comentários e aperte F5)
Abra DUAS abas do Query Tool (cada aba é uma sessão diferente, como dois
alunos em computadores diferentes). Nas duas, rode antes:

SET search_path TO academico;

PASSO 1 - Aba A:
CALL sp_matricular_ingenuo(91, 1);

PASSO 2 - Aba B, em menos de 5 segundos depois do passo 1:
CALL sp_matricular_ingenuo(92, 1);

Resultado: as DUAS abas mostram "matriculado". As duas viram 50 ocupadas.

PASSO 3 - em qualquer aba: ocupadas = 52 para 51 vagas -> SUPERLOTADA
SELECT * FROM v_vagas WHERE id_turma = 1;

PASSO 4 - limpeza: volta a turma 1 para 50 de 51
DELETE FROM tb_log_matricula WHERE id_matricula IN
    (SELECT id_matricula FROM tb_matricula WHERE id_turma = 1 AND id_aluno BETWEEN 91 AND 100);
DELETE FROM tb_matricula WHERE id_turma = 1 AND id_aluno BETWEEN 91 AND 100;
-----------------------------------------------------------------*/
