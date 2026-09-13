-- ==============================================================================
-- ARQUIVO: 04_dql_consultas.sql
-- FRENTE: Consultas (DQL) - Marco 1
-- ==============================================================================

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

-- Consulta 6: Busca Ociosa (LEFT JOIN exclusivo)
SELECT 
    c.nome_campus AS campus,
    s.codigo AS sala,
    s.tipo
FROM sala s
JOIN campus c ON s.campus_id = c.id_campus
LEFT JOIN turma_horario th ON th.sala_id = s.id_sala
WHERE th.id_turma_horario IS NULL
ORDER BY c.nome_campus, s.codigo;

-- Consulta 7: Funções de Data e Idade
SELECT 
    c.nome_curso,
    ROUND(AVG(EXTRACT(YEAR FROM AGE(CURRENT_DATE, a.nascimento))), 1) AS media_idade_curso
FROM aluno a
JOIN curriculo cur ON a.curriculo_id = cur.id_curriculo
JOIN curso c ON cur.curso_id = c.id_curso
GROUP BY c.nome_curso
ORDER BY media_idade_curso;

-- Consulta 8: Lógica Condicional (CASE WHEN)
SELECT 
    a.nome_aluno,
    d.nome AS disciplina,
    h.nota_a1,
    h.nota_a2,
    ((h.nota_a1 + h.nota_a2) / 2) AS media_calculada,
    CASE 
        WHEN ((h.nota_a1 + h.nota_a2) / 2) >= 7 THEN 'Aprovado Direto'
        WHEN ((h.nota_a1 + h.nota_a2) / 2) >= 5 THEN 'Exame Final'
        ELSE 'Reprovado'
    END AS status_projetado
FROM historico h
JOIN matricula m ON h.matricula_id = m.id_matricula
JOIN aluno a ON m.aluno_id = a.id_aluno
JOIN turma t ON m.turma_id = t.id_turma
JOIN disciplina d ON t.disciplina_id = d.id_disciplina
ORDER BY a.nome_aluno, d.nome;

-- Consulta 9: Múltiplos Joins (O Boletim Completo)
SELECT 
    a.id_aluno AS matricula,
    a.nome_aluno AS aluno,
    c.nome_curso AS curso,
    d.nome AS disciplina,
    p.nome_professor AS professor,
    h.frequencia
FROM aluno a
JOIN curriculo cur ON a.curriculo_id = cur.id_curriculo
JOIN curso c ON cur.curso_id = c.id_curso
JOIN matricula m ON m.aluno_id = a.id_aluno
JOIN historico h ON h.matricula_id = m.id_matricula
JOIN turma t ON m.turma_id = t.id_turma
JOIN disciplina d ON t.disciplina_id = d.id_disciplina
JOIN professor p ON t.professor_id = p.id_professor
WHERE h.frequencia < 75.00
ORDER BY h.frequencia ASC;

-- Consulta 10: Funções de Janela (Window Functions)
SELECT 
    disciplina,
    aluno,
    media,
    posicao_ranking
FROM (
    SELECT 
        d.nome AS disciplina,
        a.nome_aluno AS aluno,
        ((h.nota_a1 + h.nota_a2) / 2) AS media,
        RANK() OVER(PARTITION BY d.nome ORDER BY ((h.nota_a1 + h.nota_a2) / 2) DESC) AS posicao_ranking
    FROM historico h
    JOIN matricula m ON h.matricula_id = m.id_matricula
    JOIN aluno a ON m.aluno_id = a.id_aluno
    JOIN turma t ON m.turma_id = t.id_turma
    JOIN disciplina d ON t.disciplina_id = d.id_disciplina
) AS ranking_disciplina
WHERE posicao_ranking <= 3;