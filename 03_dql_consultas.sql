SET search_path TO academico;

-- Consulta 1
SELECT 
    a.id_aluno AS matricula,
    a.nome_aluno,
    c.nome_curso,
    a.ingresso_aluno
FROM aluno a
JOIN curriculo cur ON a.curriculo_id = cur.id_curriculo
JOIN curso c ON cur.curso_id = c.id_curso
ORDER BY a.nome_aluno;

-- Consulta 2
SELECT 
    t.codigo AS codigo_turma,
    d.nome AS disciplina,
    COUNT(m.id_matricula) AS total_alunos_matriculados,
    ROUND(AVG(h.nota_a1), 2) AS media_nota_a1
FROM turma t
JOIN disciplina d ON t.disciplina_id = d.id_disciplina
JOIN matricula m ON m.turma_id = t.id_turma
JOIN historico h ON h.matricula_id = m.id_matricula
GROUP BY t.codigo, d.nome
ORDER BY media_nota_a1 DESC;

-- Consulta 3: Auto-relacionamento (Self-Join)
SELECT 
    d1.nome AS disciplina_principal,
    d2.nome AS disciplina_pre_requisito,
    pr.vinculo
FROM disciplina d1
JOIN pre_requisito pr ON d1.id_disciplina = pr.disciplina_id
JOIN disciplina d2 ON pr.requisito_id = d2.id_disciplina
ORDER BY d1.nome;

-- Consulta 4: Subconsulta Negativa (NOT IN ou NOT EXISTS)
SELECT 
    id_aluno AS matricula,
    nome_aluno,
    email_aluno
FROM aluno
WHERE id_aluno NOT IN (SELECT aluno_id FROM matricula)
ORDER BY nome_aluno;

-- Consulta 5: Filtro Pós-Agrupamento (HAVING)
SELECT 
    t.codigo AS turma,
    d.nome AS disciplina,
    t.vagas AS limite_vagas,
    COUNT(m.id_matricula) AS total_matriculados
FROM turma t
JOIN disciplina d ON t.disciplina_id = d.id_disciplina
JOIN matricula m ON m.turma_id = t.id_turma
GROUP BY t.codigo, d.nome, t.vagas
HAVING COUNT(m.id_matricula) > 30
ORDER BY total_matriculados DESC;

-- Consulta 6: Junção externa com agregação
SELECT 
    p.nome_professor,
    COUNT(t.id_turma) AS total_turmas_alocadas
FROM professor p
LEFT JOIN turma t ON p.id_professor = t.professor_id
GROUP BY p.id_professor, p.nome_professor
ORDER BY total_turmas_alocadas DESC;

-- Consulta 7: Recursiva para árvore de pré-requisitos
WITH RECURSIVE arvore_prerequisitos AS (
    SELECT 
        disciplina_id, 
        requisito_id, 
        1 AS nivel_profundidade
    FROM pre_requisito
    UNION ALL
    SELECT 
        pr.disciplina_id, 
        ap.requisito_id, 
        ap.nivel_profundidade + 1
    FROM pre_requisito pr
    JOIN arvore_prerequisitos ap ON pr.requisito_id = ap.disciplina_id
)
SELECT 
    d.nome AS disciplina_alvo,
    req.nome AS dependencia,
    ap.nivel_profundidade
FROM arvore_prerequisitos ap
JOIN disciplina d ON ap.disciplina_id = d.id_disciplina
JOIN disciplina req ON ap.requisito_id = req.id_disciplina
ORDER BY d.nome, ap.nivel_profundidade;

-- Consulta 8: Recursiva para disciplinas que um aluno pode cursar
WITH RECURSIVE trilha_aluno AS (
    SELECT 
        curriculo_id, 
        disciplina_id, 
        periodo
    FROM curriculo_disciplina
    WHERE periodo = 1
    UNION ALL
    SELECT 
        cd_next.curriculo_id, 
        cd_next.disciplina_id, 
        cd_next.periodo
    FROM trilha_aluno ta
    JOIN curriculo_disciplina cd_next ON ta.curriculo_id = cd_next.curriculo_id
    WHERE cd_next.periodo = ta.periodo + 1
)
SELECT DISTINCT 
    c.nome_curso,
    ta.periodo,
    d.nome AS disciplina_liberada
FROM trilha_aluno ta
JOIN curriculo cur ON ta.curriculo_id = cur.id_curriculo
JOIN curso c ON cur.curso_id = c.id_curso
JOIN disciplina d ON ta.disciplina_id = d.id_disciplina
ORDER BY c.nome_curso, ta.periodo;

-- Consulta 9: Função de janela com ranking e percentil
SELECT 
    d.nome AS disciplina,
    a.nome_aluno,
    h.media_final,
    RANK() OVER(PARTITION BY d.id_disciplina ORDER BY h.media_final DESC) AS ranking_turma,
    ROUND(PERCENT_RANK() OVER(PARTITION BY d.id_disciplina ORDER BY h.media_final DESC)::numeric, 2) AS percentil
FROM historico h
JOIN matricula m ON h.matricula_id = m.id_matricula
JOIN aluno a ON m.aluno_id = a.id_aluno
JOIN turma t ON m.turma_id = t.id_turma
JOIN disciplina d ON t.disciplina_id = d.id_disciplina;

-- Consulta 10: Função de janela com LAG (evolução do rendimento)
SELECT 
    a.nome_aluno,
    d.nome AS disciplina,
    h.media_final AS nota_atual,
    LAG(h.media_final) OVER(PARTITION BY a.id_aluno ORDER BY t.codigo) AS nota_anterior,
    h.media_final - LAG(h.media_final) OVER(PARTITION BY a.id_aluno ORDER BY t.codigo) AS variacao_rendimento
FROM historico h
JOIN matricula m ON h.matricula_id = m.id_matricula
JOIN aluno a ON m.aluno_id = a.id_aluno
JOIN turma t ON m.turma_id = t.id_turma
JOIN disciplina d ON t.disciplina_id = d.id_disciplina;