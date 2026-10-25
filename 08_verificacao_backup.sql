-----------------------------------------------------------------
-- 08_verificacao_backup.sql  (Marco 2 - Operação: backup e restauração)
-- Gera a "impressão digital" do schema academico em UMA consulta: por tabela,
-- a quantidade de linhas e um hash MD5 do CONTEÚDO (linhas ordenadas), além
-- da materialized view, das sequências e da contagem de objetos (views,
-- índices, policies, constraints...). A última linha é a ASSINATURA GERAL:
-- um MD5 de todas as linhas acima.
--
-- Rode ANTES do backup e DEPOIS da restauração: a saída tem de ser IDÊNTICA
-- (em especial a ASSINATURA GERAL). É o que prova que a restauração recuperou
-- tudo, e não apenas "terminou sem erro". Somente leitura.
-- Rode como dono/superusuário (o RLS não se aplica a eles, então o hash
-- enxerga todas as linhas).
--
-- pgAdmin: execute (F5) e confira a coluna "valor" da última linha. Guarde a
--   assinatura (ou use "Download as CSV") e compare com a de depois da restauração.
-- psql / script de backup:
--   psql -X -A -t -f 08_verificacao_backup.sql > impressao_antes.txt
--
-- TESTE FUNCIONAL DO RLS (rode separado, SELECIONANDO as 3 linhas; deve dar 4):
--   SET ROLE aluno_3;
--   SELECT COUNT(*) FROM academico.tb_historico;
--   RESET ROLE;
-----------------------------------------------------------------
WITH f AS (
    -- Tabelas: linhas e MD5 do conteúdo
    SELECT 1 AS ord, 'tabela' AS secao, c.relname::text AS objeto,
           (xpath('/row/n/text()', query_to_xml(
                format('SELECT count(*) AS n FROM academico.%I', c.relname), false, true, '')))[1]::text
           || ' linhas | md5 '
           || COALESCE((xpath('/row/h/text()', query_to_xml(
                format('SELECT md5(string_agg(x::text, ''|'' ORDER BY x::text)) AS h FROM academico.%I x', c.relname),
                false, true, '')))[1]::text, '-') AS valor
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'academico' AND c.relkind = 'r'

    UNION ALL
    -- Materialized view (sem a coluna atualizado_em, que muda a cada REFRESH)
    SELECT 2, 'materialized view', 'mv_indicadores_disciplina',
           COUNT(*)::text || ' linhas | md5 ' || COALESCE(md5(string_agg(t::text, '|' ORDER BY t::text)), '-')
    FROM (SELECT id_periodo_letivo, id_disciplina, matriculas, aprovados, reprovados_nota,
                 reprovados_falta, cursando, taxa_aprovacao, media_geral_media, frequencia_media
          FROM academico.mv_indicadores_disciplina) t

    UNION ALL
    -- Sequências: posição do próximo id depois da restauração
    SELECT 3, 'sequencia', sequencename::text, COALESCE(last_value::text, '(não usada)')
    FROM pg_sequences
    WHERE schemaname = 'academico'

    UNION ALL
    -- Quantidade de objetos de cada tipo
    SELECT 4, 'objetos', 'tabelas', COUNT(*)::text FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'academico' AND c.relkind = 'r'
    UNION ALL SELECT 4, 'objetos', 'views', COUNT(*)::text FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'academico' AND c.relkind = 'v'
    UNION ALL SELECT 4, 'objetos', 'materialized views', COUNT(*)::text FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'academico' AND c.relkind = 'm'
    UNION ALL SELECT 4, 'objetos', 'índices', COUNT(*)::text FROM pg_indexes WHERE schemaname = 'academico'
    UNION ALL SELECT 4, 'objetos', 'constraints', COUNT(*)::text FROM pg_constraint k JOIN pg_namespace n ON n.oid = k.connamespace WHERE n.nspname = 'academico'
    UNION ALL SELECT 4, 'objetos', 'policies (RLS)', COUNT(*)::text FROM pg_policies WHERE schemaname = 'academico'
    UNION ALL SELECT 4, 'objetos', 'funções/procedures', COUNT(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'academico'
    UNION ALL SELECT 4, 'objetos', 'triggers', COUNT(*)::text FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'academico' AND NOT t.tgisinternal
    UNION ALL SELECT 4, 'objetos', 'tipos (enum/domínio)', COUNT(*)::text FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'academico' AND t.typtype IN ('e', 'd')
    UNION ALL SELECT 4, 'objetos', 'concessões (GRANT) em tabelas', COUNT(*)::text FROM information_schema.role_table_grants WHERE table_schema = 'academico' AND grantee IN ('aluno', 'secretaria', 'coordenacao')
    UNION ALL SELECT 4, 'objetos', 'papéis aluno_N (nível do servidor)', COUNT(*)::text FROM pg_roles WHERE rolname ~ '^aluno_[0-9]+$'

    UNION ALL
    -- RLS ativo nas tabelas sensíveis
    SELECT 5, 'rls', c.relname::text, c.relrowsecurity::text
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'academico' AND c.relname IN ('tb_aluno', 'tb_matricula', 'tb_historico')
)
SELECT ord, secao, objeto, valor
FROM f
UNION ALL
SELECT 9, 'ASSINATURA GERAL', 'md5 de todas as linhas acima',
       md5(string_agg(secao || '|' || objeto || '|' || valor, E'\n' ORDER BY ord, secao, objeto))
FROM f
ORDER BY 1, 2, 3;
