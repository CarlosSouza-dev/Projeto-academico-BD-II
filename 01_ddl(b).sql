-----------------------------------------------------------------
-- 01_ddl(b).sql
-- Demonstração AO VIVO das restrições de integridade do 01_ddl_inicial.sql.
-- Rode antes o 01 e o 02 (o banco tem de ser o `matricula`).
--
-- COMO USAR: selecione UM comando por vez (com o comentário da linha de
-- cima, se quiser) e aperte F5 no Query Tool. TODOS DÃO ERRO DE PROPÓSITO:
-- é o banco recusando o dado errado. Nenhum comando altera os dados.
-- As tabelas já levam o `academico.` na frente, então cada comando
-- funciona sozinho, sem o SET search_path.
-----------------------------------------------------------------

-- 1) CHECK: semestre só pode ser 1 ou 2
-- Erro esperado: violates check constraint "tb_periodo_letivo_semestre_check"
INSERT INTO academico.tb_periodo_letivo (ano, semestre, data_inicio, data_fim) VALUES (2027, 3, '2027-02-01', '2027-06-30');

-- 2) DOMAIN: nota de 0 a 10
-- Erro esperado: value for domain nota_t violates check constraint
UPDATE academico.tb_historico SET nota_a1 = 11 WHERE id_historico = 1;

-- 3) UNIQUE: o aluno 1 já está na turma 1? (UNIQUE id_turma + id_aluno)
-- Erro esperado: duplicate key value violates unique constraint
INSERT INTO academico.tb_matricula (id_aluno, id_turma, status_matricula)
SELECT id_aluno, id_turma, 'Ativa' FROM academico.tb_matricula WHERE id_matricula = 1;

-- 4) FK: turma que não existe
-- Erro esperado: violates foreign key constraint
INSERT INTO academico.tb_matricula (id_aluno, id_turma, status_matricula) VALUES (91, 999, 'Ativa');

-- 5) Coluna gerada: não aceita valor digitado
-- Erro esperado: column "ch_total_disciplina" can only be updated to DEFAULT
UPDATE academico.tb_disciplina SET ch_total_disciplina = 100 WHERE id_disciplina = 1;

-- 6) CHECK: disciplina não pode ser pré-requisito de si mesma
-- Erro esperado: violates check constraint "tb_pre_requisito_check"
INSERT INTO academico.tb_pre_requisito (id_disciplina, id_requisito, vinculo) VALUES (1, 1, 'OBRIGATORIA');

-- Se aparecer `relation ... does not exist`, não é o erro esperado: o Query
-- Tool está no banco errado (tem de ser `matricula`) ou o 01 e o 02 não rodaram.
