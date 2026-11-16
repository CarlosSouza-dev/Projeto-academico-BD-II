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


/*-----------------------------------------------------------------
BACKUP, DESASTRE E RESTAURAÇÃO (demonstração ao vivo, ~3 minutos)
Os comandos abaixo são do TERMINAL (CMD ou PowerShell), não do Query Tool.
O contêiner do ambiente oficial se chama bd2_aluno_postgres.
Se usar o Git Bash, rode antes: export MSYS_NO_PATHCONV=1

PASSO 1 - ANTES: rode este arquivo no pgAdmin (F5) e guarde o resultado
          (300 matrículas, 6 policies...).

PASSO 2 - SALVAR o banco (backup lógico, formato custom, só o schema academico):
docker exec bd2_aluno_postgres pg_dump -U bd2 -d matricula -n academico -Fc -f /tmp/academico.dump

          Para guardar uma cópia FORA do contêiner:
docker cp bd2_aluno_postgres:/tmp/academico.dump .

PASSO 3 - APAGAR o schema inteiro (o desastre):
docker exec bd2_aluno_postgres psql -U bd2 -d matricula -c "DROP SCHEMA academico CASCADE"

          No Query Tool, a conferência agora dá erro (a tabela não existe):
SELECT COUNT(*) FROM academico.tb_matricula;

PASSO 4 - RECUPERAR o banco a partir do backup:
docker exec bd2_aluno_postgres pg_restore -U bd2 -d matricula /tmp/academico.dump

PASSO 5 - DEPOIS: rode este arquivo de novo (F5). Os números têm de ser
          IGUAIS aos do passo 1. E o RLS continua valendo (deve dar 4):
SET ROLE aluno_3;
SELECT COUNT(*) FROM academico.tb_historico;
RESET ROLE;

OBSERVAÇÃO: os papéis (aluno, secretaria, coordenacao, aluno_3...) NÃO vão
no backup do schema, porque pertencem ao servidor. Neste desastre eles
continuam lá. Em um servidor novo, rode o 07_seguranca.sql (ou use
pg_dumpall --roles-only) ANTES do pg_restore.

PELO pgAdmin (sem terminal): botão direito no schema academico > Backup...
(formato Custom); depois DROP SCHEMA academico CASCADE; e por fim botão
direito no banco matricula > Restore... (formato Custom).
Explicação completa em docs/backup_restauracao.md.
-----------------------------------------------------------------*/
