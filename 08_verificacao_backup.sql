-----------------------------------------------------------------
-- 08_verificacao_backup.sql  (Marco 2 - Operação: backup e restauração)
-- Gera a "impressão digital" do schema academico: por tabela, a quantidade
-- de linhas e um hash MD5 do CONTEÚDO (linhas ordenadas), além da
-- contagem de objetos (views, índices, policies, constraints...).
-- Rode ANTES do backup e DEPOIS da restauração: as duas saídas têm de ser
-- idênticas. É o que prova que a restauração recuperou tudo, e não apenas
-- "terminou sem erro". Somente leitura. Rode como dono/superusuário (o RLS
-- não se aplica a eles, então o hash enxerga todas as linhas).
--
--   psql -X -A -t -f 08_verificacao_backup.sql > impressao_antes.txt
-----------------------------------------------------------------
SET search_path TO academico, public;

\echo '== TABELAS: linhas e hash do conteúdo =='
SELECT c.relname AS tabela,
       (xpath('/row/n/text()', query_to_xml(
            format('SELECT count(*) AS n FROM academico.%I', c.relname), false, true, '')))[1]::text AS linhas,
       COALESCE((xpath('/row/h/text()', query_to_xml(
            format('SELECT md5(string_agg(x::text, ''|'' ORDER BY x::text)) AS h FROM academico.%I x', c.relname),
            false, true, '')))[1]::text, '-') AS md5_conteudo
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'academico' AND c.relkind = 'r'
ORDER BY c.relname;

\echo '== MATERIALIZED VIEW =='
SELECT 'mv_indicadores_disciplina' AS objeto,
       COUNT(*)::text              AS linhas,
       md5(string_agg(t::text, '|' ORDER BY t::text)) AS md5_conteudo
FROM (SELECT id_periodo_letivo, id_disciplina, matriculas, aprovados, reprovados_nota,
             reprovados_falta, cursando, taxa_aprovacao, media_geral_media, frequencia_media
      FROM mv_indicadores_disciplina) t;

\echo '== SEQUÊNCIAS (próximo id após a restauração) =='
SELECT sequencename, COALESCE(last_value::text, '(não usada)') AS ultimo_valor
FROM pg_sequences
WHERE schemaname = 'academico'
ORDER BY sequencename;

\echo '== OBJETOS DO SCHEMA =='
SELECT 'tabelas'          AS objeto, COUNT(*)::text AS qtd FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'academico' AND c.relkind = 'r'
UNION ALL SELECT 'views',               COUNT(*)::text FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'academico' AND c.relkind = 'v'
UNION ALL SELECT 'materialized views',  COUNT(*)::text FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'academico' AND c.relkind = 'm'
UNION ALL SELECT 'índices',             COUNT(*)::text FROM pg_indexes WHERE schemaname = 'academico'
UNION ALL SELECT 'constraints',         COUNT(*)::text FROM pg_constraint k JOIN pg_namespace n ON n.oid = k.connamespace WHERE n.nspname = 'academico'
UNION ALL SELECT 'policies (RLS)',      COUNT(*)::text FROM pg_policies WHERE schemaname = 'academico'
UNION ALL SELECT 'funções/procedures',  COUNT(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'academico'
UNION ALL SELECT 'tipos (enum/domínio)',COUNT(*)::text FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'academico' AND t.typtype IN ('e', 'd')
UNION ALL SELECT 'concessões (GRANT) em tabelas', COUNT(*)::text FROM information_schema.role_table_grants WHERE table_schema = 'academico' AND grantee IN ('aluno', 'secretaria', 'coordenacao')
ORDER BY 1;

\echo '== RLS ATIVO NAS TABELAS SENSÍVEIS =='
SELECT c.relname AS tabela, c.relrowsecurity AS rls_ativo
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'academico' AND c.relname IN ('tb_aluno', 'tb_matricula', 'tb_historico')
ORDER BY c.relname;

\echo '== TESTE FUNCIONAL: o RLS continua valendo (aluno_3 deve ver 4 linhas de histórico) =='
DO $$
DECLARE
    n int;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'aluno_3') THEN
        RAISE NOTICE 'papel aluno_3 não existe (rode 07_seguranca.sql); teste de RLS ignorado';
        RETURN;
    END IF;
    SET LOCAL ROLE aluno_3;
    SELECT COUNT(*) INTO n FROM tb_historico;
    RESET ROLE;
    RAISE NOTICE 'aluno_3 enxerga % linhas de histórico', n;
END $$;
