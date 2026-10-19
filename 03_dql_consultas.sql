-----------------------------------------------------------------
-- 03_dql_consultas.sql
-- 10 consultas de complexidade crescente (Marco 1)
-- Rode APÓS 01_ddl_inicial.sql e 02_dml_carga.sql.
-----------------------------------------------------------------
SET search_path TO academico;

-- Consulta 1: Junção simples encadeada
-- Lista cada aluno com o curso em que está matriculado (aluno -> currículo -> curso).
SELECT
    a.id_aluno,
    a.nome_aluno,
    c.nome_curso,
    a.ingresso_aluno
FROM tb_aluno a
JOIN tb_curriculo cur ON a.id_curriculo = cur.id_curriculo
JOIN tb_curso c ON cur.id_curso = c.id_curso
ORDER BY a.nome_aluno;

-- Consulta 2: Agregação com múltiplas junções
-- Por turma: quantidade de alunos com histórico e média da nota A1.
SELECT
    t.codigo AS codigo_turma,
    d.nome AS disciplina,
    COUNT(m.id_matricula) AS total_alunos_matriculados,
    ROUND(AVG(h.nota_a1), 2) AS media_nota_a1
FROM tb_turma t
JOIN tb_disciplina d ON t.id_disciplina = d.id_disciplina
JOIN tb_matricula m ON m.id_turma = t.id_turma
JOIN tb_historico h ON h.id_matricula = m.id_matricula
GROUP BY t.id_turma, t.codigo, d.nome
ORDER BY media_nota_a1 DESC, t.id_turma;

-- Consulta 3: Auto-relacionamento (Self-Join)
-- Cada disciplina com seus pré-requisitos diretos (tb_disciplina aparece duas vezes).
SELECT
    d1.nome AS disciplina_principal,
    d2.nome AS disciplina_pre_requisito,
    pr.vinculo
FROM tb_disciplina d1
JOIN tb_pre_requisito pr ON d1.id_disciplina = pr.id_disciplina
JOIN tb_disciplina d2 ON pr.id_requisito = d2.id_disciplina
ORDER BY d1.nome, d2.nome;

-- Consulta 4: Subconsulta negativa (NOT EXISTS)
-- Alunos que ainda não possuem nenhuma matrícula.
-- (NOT EXISTS é preferível a NOT IN: não quebra se a subconsulta devolver NULL.)
SELECT
    a.id_aluno,
    a.nome_aluno,
    a.email_aluno
FROM tb_aluno a
WHERE NOT EXISTS (
    SELECT 1
    FROM tb_matricula m
    WHERE m.id_aluno = a.id_aluno
)
ORDER BY a.nome_aluno;

-- Consulta 5: Filtro pós-agrupamento (HAVING)
-- Turmas com mais de 30 matrículas, mostrando também a ocupação das vagas.
SELECT
    t.codigo AS turma,
    d.nome AS disciplina,
    t.vagas AS limite_vagas,
    COUNT(m.id_matricula) AS total_matriculados,
    ROUND(100.0 * COUNT(m.id_matricula) / t.vagas, 1) AS pct_ocupacao
FROM tb_turma t
JOIN tb_disciplina d ON t.id_disciplina = d.id_disciplina
JOIN tb_matricula m ON m.id_turma = t.id_turma
GROUP BY t.id_turma, t.codigo, t.vagas, d.nome
HAVING COUNT(m.id_matricula) > 30
ORDER BY total_matriculados DESC, t.id_turma;

-- Consulta 6: Junção externa com agregação
-- Quantidade de turmas por professor (LEFT JOIN mantém professor sem turma, com 0).
SELECT
    p.nome_professor,
    COUNT(t.id_turma) AS total_turmas_alocadas
FROM tb_professor p
LEFT JOIN tb_turma t ON p.id_professor = t.id_professor
GROUP BY p.id_professor, p.nome_professor
ORDER BY total_turmas_alocadas DESC, p.nome_professor;

-- Consulta 7: Recursiva - árvore de pré-requisitos
-- Fecho transitivo: nível 1 = pré-requisito direto; nível 2 = pré-requisito do pré-requisito...
-- A trava de profundidade (< 10) evita laço infinito caso haja ciclo nos dados.
WITH RECURSIVE arvore_prerequisitos AS (
    SELECT
        id_disciplina,
        id_requisito,
        1 AS nivel_profundidade
    FROM tb_pre_requisito
    UNION ALL
    SELECT
        pr.id_disciplina,
        ap.id_requisito,
        ap.nivel_profundidade + 1
    FROM tb_pre_requisito pr
    JOIN arvore_prerequisitos ap ON pr.id_requisito = ap.id_disciplina
    WHERE ap.nivel_profundidade < 10
)
SELECT
    d.nome AS disciplina_alvo,
    req.nome AS dependencia,
    ap.nivel_profundidade
FROM arvore_prerequisitos ap
JOIN tb_disciplina d ON ap.id_disciplina = d.id_disciplina
JOIN tb_disciplina req ON ap.id_requisito = req.id_disciplina
ORDER BY d.nome, ap.nivel_profundidade, req.nome;

-- Consulta 8: Recursiva - disciplinas que um aluno já pode cursar
-- 1) a CTE recursiva calcula TODOS os pré-requisitos (diretos e indiretos) obrigatórios;
-- 2) a CTE "aprovadas" lista o que cada aluno já concluiu com aprovação;
-- 3) uma disciplina do currículo do aluno está liberada se ele ainda não foi aprovado nela
--    e já foi aprovado em todos os seus pré-requisitos.
-- Troque o id do aluno em "a.id_aluno = 3" (aluno 3 pertence ao currículo 1 de CCO).
WITH RECURSIVE cadeia_prerequisitos AS (
    SELECT id_disciplina, id_requisito
    FROM tb_pre_requisito
    WHERE vinculo = 'OBRIGATORIA'
    UNION
    SELECT pr.id_disciplina, cp.id_requisito
    FROM tb_pre_requisito pr
    JOIN cadeia_prerequisitos cp ON pr.id_requisito = cp.id_disciplina
    WHERE pr.vinculo = 'OBRIGATORIA'
),
aprovadas AS (
    SELECT m.id_aluno, t.id_disciplina
    FROM tb_historico h
    JOIN tb_matricula m ON m.id_matricula = h.id_matricula
    JOIN tb_turma t ON t.id_turma = m.id_turma
    WHERE h.situacao = 'Aprovado'
)
SELECT
    a.id_aluno,
    a.nome_aluno,
    c.nome_curso,
    cd.periodo,
    d.nome AS disciplina_liberada
FROM tb_aluno a
JOIN tb_curriculo cur ON cur.id_curriculo = a.id_curriculo
JOIN tb_curso c ON c.id_curso = cur.id_curso
JOIN tb_curriculo_disciplina cd ON cd.id_curriculo = a.id_curriculo
JOIN tb_disciplina d ON d.id_disciplina = cd.id_disciplina
WHERE a.id_aluno = 3
  AND NOT EXISTS (                       -- ainda não aprovado na própria disciplina
        SELECT 1 FROM aprovadas ap
        WHERE ap.id_aluno = a.id_aluno
          AND ap.id_disciplina = cd.id_disciplina)
  AND NOT EXISTS (                       -- nenhum pré-requisito pendente
        SELECT 1 FROM cadeia_prerequisitos cp
        WHERE cp.id_disciplina = cd.id_disciplina
          AND NOT EXISTS (
                SELECT 1 FROM aprovadas ap
                WHERE ap.id_aluno = a.id_aluno
                  AND ap.id_disciplina = cp.id_requisito))
ORDER BY cd.periodo, d.nome;

-- Consulta 9: Função de janela - ranking e percentil por turma
-- RANK: 1 = maior média da turma. PERCENT_RANK em ordem crescente:
-- 1,00 = melhor aluno da turma, 0,00 = pior.
SELECT
    t.codigo AS turma,
    d.nome AS disciplina,
    a.nome_aluno,
    h.media_geral,
    RANK() OVER (PARTITION BY t.id_turma ORDER BY h.media_geral DESC) AS ranking_turma,
    ROUND(PERCENT_RANK() OVER (PARTITION BY t.id_turma ORDER BY h.media_geral ASC)::numeric, 2) AS percentil
FROM tb_historico h
JOIN tb_matricula m ON h.id_matricula = m.id_matricula
JOIN tb_aluno a ON m.id_aluno = a.id_aluno
JOIN tb_turma t ON m.id_turma = t.id_turma
JOIN tb_disciplina d ON t.id_disciplina = d.id_disciplina
ORDER BY t.id_turma, ranking_turma, a.nome_aluno;

-- Consulta 10: Função de janela - LAG (evolução do rendimento)
-- Para cada aluno, compara a média de cada matrícula com a anterior em ordem
-- cronológica (ano, semestre do período letivo; desempate pelo id da turma).
WITH rendimento AS (
    SELECT
        a.id_aluno,
        a.nome_aluno,
        d.nome AS disciplina,
        pl.ano,
        pl.semestre,
        t.id_turma,
        t.codigo AS turma,
        h.media_geral AS nota_atual,
        LAG(h.media_geral) OVER (
            PARTITION BY a.id_aluno
            ORDER BY pl.ano, pl.semestre, t.id_turma
        ) AS nota_anterior
    FROM tb_historico h
    JOIN tb_matricula m ON h.id_matricula = m.id_matricula
    JOIN tb_aluno a ON m.id_aluno = a.id_aluno
    JOIN tb_turma t ON m.id_turma = t.id_turma
    JOIN tb_periodo_letivo pl ON t.id_periodo_letivo = pl.id_periodo_letivo
    JOIN tb_disciplina d ON t.id_disciplina = d.id_disciplina
)
SELECT
    nome_aluno,
    turma,
    disciplina,
    ano,
    semestre,
    nota_atual,
    nota_anterior,
    nota_atual - nota_anterior AS variacao_rendimento
FROM rendimento
ORDER BY id_aluno, ano, semestre, id_turma;