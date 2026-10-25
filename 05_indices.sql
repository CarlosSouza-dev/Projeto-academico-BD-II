-----------------------------------------------------------------
-- 05_indices.sql  (Marco 2 - Modelagem Física e Desempenho)
-- Índices de otimização. Cada um responde a uma consulta real do sistema
-- e tem sua evidência EXPLAIN (ANALYZE, BUFFERS) antes/depois em
-- evidencias_explain.txt (gerado por 05b_evidencias_explain.sql).
-- Pode ser reexecutado sem erro (IF NOT EXISTS).
--
-- O que o PostgreSQL JÁ indexa sozinho (não duplicar):
--   * PK e UNIQUE de todas as tabelas;
--   * tb_matricula UNIQUE (id_turma, id_aluno): atende buscas por id_turma
--     (coluna líder), mas NÃO buscas só por id_aluno;
--   * tb_historico UNIQUE (id_matricula).
-- O PostgreSQL NÃO cria índice automático em coluna de chave estrangeira.
-----------------------------------------------------------------
SET search_path TO academico;

-- 1) Histórico/matrículas de UM aluno (tela do aluno, v_historico, RLS).
--    O UNIQUE (id_turma, id_aluno) não serve aqui: id_aluno é a 2ª coluna.
CREATE INDEX IF NOT EXISTS idx_matricula_aluno
    ON tb_matricula (id_aluno);

-- 2) ÍNDICE PARCIAL: vagas ocupadas por turma (v_vagas e a disputa pela
--    última vaga). Só indexa as matrículas 'Ativas' (o período corrente),
--    uma fração pequena da tabela, que cresce com o histórico de períodos
--    encerrados. É menor, mais barato de manter e permite index-only scan
--    na contagem de ocupação.
CREATE INDEX IF NOT EXISTS idx_matricula_turma_ativa
    ON tb_matricula (id_turma)
    WHERE status_matricula = 'Ativa';

-- 3) Busca da secretaria por prefixo do nome, sem diferenciar maiúsculas.
--    Índice sobre EXPRESSÃO lower(nome_aluno); text_pattern_ops permite
--    LIKE 'prefixo%' em qualquer collation (o btree comum não permitiria
--    em collations diferentes de "C", como en_US.utf8).
CREATE INDEX IF NOT EXISTS idx_aluno_nome_lower
    ON tb_aluno (lower(nome_aluno) text_pattern_ops);

-- 4) SEGUNDO ÍNDICE PARCIAL (cobrindo): os casos mais graves de infrequência
--    entre os reprovados por falta (lista de contato da secretaria / evasão).
--    Só ~3% do histórico atende ao predicado, então o índice é minúsculo.
--    Indexa 'frequencia' (a ordenação pedida) e carrega id_matricula via
--    INCLUDE: a consulta "ORDER BY frequencia LIMIT 20" é respondida só pelo
--    índice (index-only scan), já em ordem, sem ler a tabela nem ordenar.
CREATE INDEX IF NOT EXISTS idx_historico_reprovado_falta
    ON tb_historico (frequencia) INCLUDE (id_matricula)
    WHERE situacao = 'Reprovado por Falta';

-- Atualiza as estatísticas para o planner considerar os novos índices.
ANALYZE tb_matricula;
ANALYZE tb_aluno;
ANALYZE tb_historico;

-- Conferência
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'academico'
  AND indexname LIKE 'idx\_%'
ORDER BY indexname;
