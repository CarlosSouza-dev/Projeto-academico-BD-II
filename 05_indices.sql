-----------------------------------------------------------------
-- 05_indices.sql  (Marco 2 - Modelagem Física e Desempenho)
-- 4 índices, cada um ligado a uma consulta real do sistema.
-- A prova do ganho (EXPLAIN ANALYZE antes e depois) está no
-- 05b_evidencias_explain.sql, e o resultado em evidencias_explain.txt.
-- Pode ser executado de novo sem erro (IF NOT EXISTS).
--
-- O que o PostgreSQL JÁ indexa sozinho (não precisa criar):
--   * toda PRIMARY KEY e todo UNIQUE;
--   * por isso tb_matricula já tem índice em (id_turma, id_aluno), que serve
--     para buscar por id_turma (1ª coluna), mas NÃO para buscar só por id_aluno.
-- O PostgreSQL NÃO cria índice sozinho em chave estrangeira.
-----------------------------------------------------------------
SET search_path TO academico;

-- 1) ÍNDICE COMUM em chave estrangeira: matrículas de UM aluno
--    (tela do aluno, v_historico e o filtro do RLS no 07).
CREATE INDEX IF NOT EXISTS idx_matricula_aluno
    ON tb_matricula (id_aluno);

-- 2) ÍNDICE PARCIAL: só as matrículas 'Ativa' entram no índice.
--    Atende a contagem de vagas ocupadas de uma turma, que a matrícula faz
--    toda vez (06) e que a v_vagas mostra. Matrículas de semestres passados
--    ficam de fora, então o índice é bem menor que um índice na tabela toda.
CREATE INDEX IF NOT EXISTS idx_matricula_turma_ativa
    ON tb_matricula (id_turma)
    WHERE status_matricula = 'Ativa';

-- 3) ÍNDICE DE EXPRESSÃO: a secretaria procura o aluno pelo nome sem se
--    preocupar com maiúsculas. Um índice em nome_aluno não serve para
--    WHERE lower(nome_aluno) = '...'; o índice precisa ser na expressão.
CREATE INDEX IF NOT EXISTS idx_aluno_nome_lower
    ON tb_aluno (lower(nome_aluno));

-- 4) ÍNDICE COMPOSTO (2 colunas): lista dos reprovados por falta, da menor
--    para a maior frequência. A 1ª coluna filtra (situacao) e a 2ª já está
--    em ordem (frequencia), então o banco não precisa ordenar.
CREATE INDEX IF NOT EXISTS idx_historico_situacao_freq
    ON tb_historico (situacao, frequencia);

-- Atualiza as estatísticas que o planejador usa para escolher o plano
ANALYZE tb_matricula;
ANALYZE tb_aluno;
ANALYZE tb_historico;

-- Conferência: os 4 índices criados
SELECT tablename AS tabela, indexname AS indice, indexdef AS definicao
FROM pg_indexes
WHERE schemaname = 'academico'
  AND indexname LIKE 'idx%'
ORDER BY tablename, indexname;
