-----------------------------------------------------------------
-- 08_verificacao_backup.sql  (Marco 2 - Operação: backup e restauração)
-- Conferência do banco ANTES do backup e DEPOIS da restauração.
-- A saída tem de ser IGUAL nas duas vezes: é o que prova que a restauração
-- trouxe tudo de volta, e não só que "terminou sem erro".
-- Somente leitura. Rode como bd2 (o dono não é filtrado pelo RLS).
-- O passo a passo do backup está em docs/backup_restauracao.md.
-----------------------------------------------------------------
SET search_path TO academico;

-- Linhas por tabela, quantidade de objetos e uma soma de controle das notas
SELECT 'tabela'  AS tipo, 'tb_campus'               AS objeto, COUNT(*) AS quantidade FROM tb_campus
UNION ALL SELECT 'tabela', 'tb_curso',                COUNT(*) FROM tb_curso
UNION ALL SELECT 'tabela', 'tb_curriculo',            COUNT(*) FROM tb_curriculo
UNION ALL SELECT 'tabela', 'tb_curriculo_disciplina', COUNT(*) FROM tb_curriculo_disciplina
UNION ALL SELECT 'tabela', 'tb_disciplina',           COUNT(*) FROM tb_disciplina
UNION ALL SELECT 'tabela', 'tb_pre_requisito',        COUNT(*) FROM tb_pre_requisito
UNION ALL SELECT 'tabela', 'tb_feriado',              COUNT(*) FROM tb_feriado
UNION ALL SELECT 'tabela', 'tb_periodo_letivo',       COUNT(*) FROM tb_periodo_letivo
UNION ALL SELECT 'tabela', 'tb_professor',            COUNT(*) FROM tb_professor
UNION ALL SELECT 'tabela', 'tb_sala',                 COUNT(*) FROM tb_sala
UNION ALL SELECT 'tabela', 'tb_turma',                COUNT(*) FROM tb_turma
UNION ALL SELECT 'tabela', 'tb_turma_horario',        COUNT(*) FROM tb_turma_horario
UNION ALL SELECT 'tabela', 'tb_aluno',                COUNT(*) FROM tb_aluno
UNION ALL SELECT 'tabela', 'tb_matricula',            COUNT(*) FROM tb_matricula
UNION ALL SELECT 'tabela', 'tb_historico',            COUNT(*) FROM tb_historico
UNION ALL SELECT 'tabela', 'tb_log_matricula',        COUNT(*) FROM tb_log_matricula
UNION ALL SELECT 'materialized view', 'mv_indicadores_disciplina', COUNT(*) FROM mv_indicadores_disciplina
UNION ALL SELECT 'objetos', 'views',      COUNT(*) FROM information_schema.views WHERE table_schema = 'academico'
UNION ALL SELECT 'objetos', 'índices',    COUNT(*) FROM pg_indexes  WHERE schemaname = 'academico'
UNION ALL SELECT 'objetos', 'policies',   COUNT(*) FROM pg_policies WHERE schemaname = 'academico'
UNION ALL SELECT 'objetos', 'procedures/funções', COUNT(*) FROM information_schema.routines WHERE routine_schema = 'academico'
UNION ALL SELECT 'objetos', 'triggers',   COUNT(*) FROM information_schema.triggers WHERE trigger_schema = 'academico'
UNION ALL SELECT 'controle', 'soma das notas A1 x 100', ROUND(SUM(nota_a1) * 100) FROM tb_historico
UNION ALL SELECT 'controle', 'soma dos ids de matrícula', SUM(id_matricula) FROM tb_matricula;

-- Teste do RLS no banco restaurado (selecione as 3 linhas e execute; deve dar 4):
-- SET ROLE aluno_3;
-- SELECT COUNT(*) FROM tb_historico;
-- RESET ROLE;
