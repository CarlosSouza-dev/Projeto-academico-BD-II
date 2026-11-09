-----------------------------------------------------------------
-- 06c_correcao_isolamento.sql  (Marco 2 - Correção 2: NÍVEL DE ISOLAMENTO)
--
-- IDEIA: não muda NADA no código. Usa a MESMA sp_matricular_ingenuo do 06,
-- mas com a transação no nível SERIALIZABLE, o mais rígido do PostgreSQL.
-- Nele, o banco garante que o resultado final seja o mesmo que se as
-- transações tivessem rodado uma de cada vez. Ninguém espera: as duas
-- matrículas rodam juntas, e quando o banco percebe que as duas contaram as
-- mesmas 50 e as duas inseriram, ele CANCELA uma delas com o erro
--     ERROR: could not serialize access due to read/write dependencies
--     (SQLSTATE 40001)
-- Quem recebeu o erro precisa REPETIR a matrícula. Na repetição, a vaga já
-- foi tomada e a resposta certa aparece: "sem vaga".
--
-- Rode APÓS o 06_anomalia_vagas.sql. Este arquivo não cria nada: ele só
-- mostra os níveis de isolamento e traz a demonstração.
-----------------------------------------------------------------
SET search_path TO academico;

-- Nível de isolamento atual (padrão: read committed)
SHOW transaction_isolation;


/*-----------------------------------------------------------------
DEMONSTRAÇÃO AO VIVO (2 abas do Query Tool)

PASSO 0 - nas DUAS abas: muda o nível de isolamento desta sessão
SET search_path TO academico;
SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL SERIALIZABLE;

O SET vale a partir da PRÓXIMA execução. Por isso confira em um F5 separado
(nas duas abas tem de aparecer "serializable"):
SHOW transaction_isolation;

PASSO 1 - Aba A:
CALL sp_matricular_ingenuo(91, 1);

PASSO 2 - Aba B, em menos de 5 segundos:
CALL sp_matricular_ingenuo(92, 1);

Resultado: a Aba A matricula. A Aba B NÃO espera, mas no fim recebe o erro
40001 "could not serialize access". A matrícula dela foi desfeita.

PASSO 3 - Aba B: a aplicação repete a mesma transação (RETENTATIVA)
CALL sp_matricular_ingenuo(92, 1);
Agora a Aba B recebe "Turma 1 sem vaga: 51 ocupadas de 51 vagas".

PASSO 4 - ocupadas = 51 para 51 vagas -> LOTADA, sem overbooking
SELECT * FROM v_vagas WHERE id_turma = 1;

PASSO 5 - limpeza e volta ao nível padrão (nas duas abas)
DELETE FROM tb_log_matricula WHERE id_matricula IN
    (SELECT id_matricula FROM tb_matricula WHERE id_turma = 1 AND id_aluno BETWEEN 91 AND 100);
DELETE FROM tb_matricula WHERE id_turma = 1 AND id_aluno BETWEEN 91 AND 100;
SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL READ COMMITTED;
-----------------------------------------------------------------*/
