-----------------------------------------------------------------
-- 04_views.sql  (Marco 2 - Administração e Operação)
-- 3 views (oferta, vagas, histórico) + 1 materialized view de indicadores.
-- Rode APÓS 01 e 02. Pode ser executado de novo sem erro.
-----------------------------------------------------------------
SET search_path TO academico;

-----------------------------------------------------------------
-- 1. v_oferta - oferta de turmas
-- O que o aluno vê ao escolher disciplinas: disciplina, professor, turno,
-- vagas, dia e horário de cada aula. Esconde os 6 JOINs de quem consulta.
-- dia_semana segue a convenção 1 = domingo ... 7 = sábado.
-----------------------------------------------------------------
CREATE OR REPLACE VIEW v_oferta AS
SELECT
    t.id_turma,
    pl.ano || '/' || pl.semestre AS periodo,
    t.codigo              AS codigo_turma,
    d.codigo              AS codigo_disciplina,
    d.nome                AS disciplina,
    d.ch_total_disciplina AS carga_horaria,
    p.nome_professor      AS professor,
    t.turno,
    t.vagas,
    th.dia_semana,
    th.faixa              AS horario,
    s.codigo              AS sala
FROM tb_turma t
JOIN tb_periodo_letivo pl ON pl.id_periodo_letivo = t.id_periodo_letivo
JOIN tb_disciplina d      ON d.id_disciplina      = t.id_disciplina
JOIN tb_professor p       ON p.id_professor       = t.id_professor
LEFT JOIN tb_turma_horario th ON th.id_turma = t.id_turma   -- LEFT: turma sem horário também aparece
LEFT JOIN tb_sala s           ON s.id_sala   = th.id_sala;

-----------------------------------------------------------------
-- 2. v_vagas - ocupação das turmas
-- Vaga ocupada = matrícula com status 'Ativa' (trancada ou cancelada libera
-- a vaga). 'SUPERLOTADA' só aparece se houver mais matrículas que vagas:
-- é a view que denuncia a anomalia da última vaga (06_anomalia_vagas.sql).
-----------------------------------------------------------------
CREATE OR REPLACE VIEW v_vagas AS
SELECT
    t.id_turma,
    t.codigo AS codigo_turma,
    d.nome   AS disciplina,
    t.vagas,
    COUNT(m.id_matricula) FILTER (WHERE m.status_matricula = 'Ativa')           AS ocupadas,
    t.vagas - COUNT(m.id_matricula) FILTER (WHERE m.status_matricula = 'Ativa') AS livres,
    CASE
        WHEN COUNT(m.id_matricula) FILTER (WHERE m.status_matricula = 'Ativa') > t.vagas THEN 'SUPERLOTADA'
        WHEN COUNT(m.id_matricula) FILTER (WHERE m.status_matricula = 'Ativa') = t.vagas THEN 'LOTADA'
        ELSE 'COM VAGAS'
    END AS situacao_vagas
FROM tb_turma t
JOIN tb_disciplina d ON d.id_disciplina = t.id_disciplina
LEFT JOIN tb_matricula m ON m.id_turma = t.id_turma        -- LEFT: turma vazia aparece com 0
GROUP BY t.id_turma, t.codigo, d.nome, t.vagas;

-----------------------------------------------------------------
-- 3. v_historico - histórico acadêmico detalhado
-- security_invoker = true: a view roda com as permissões de QUEM CONSULTA,
-- e não do dono. Assim o row-level security do 07_seguranca.sql vale também
-- por aqui: o aluno que consulta a view só vê as próprias linhas.
-- Sem essa opção, a view rodaria como o dono e mostraria o histórico de todos.
-----------------------------------------------------------------
CREATE OR REPLACE VIEW v_historico WITH (security_invoker = true) AS
SELECT
    a.id_aluno,
    a.nome_aluno,
    pl.ano || '/' || pl.semestre AS periodo,
    d.codigo AS codigo_disciplina,
    d.nome   AS disciplina,
    t.codigo AS codigo_turma,
    m.status_matricula,
    h.nota_a1,
    h.nota_a2,
    h.nota_p3,
    h.media_geral,
    h.frequencia,
    h.situacao
FROM tb_historico h
JOIN tb_matricula m       ON m.id_matricula       = h.id_matricula
JOIN tb_aluno a           ON a.id_aluno           = m.id_aluno
JOIN tb_turma t           ON t.id_turma           = m.id_turma
JOIN tb_disciplina d      ON d.id_disciplina      = t.id_disciplina
JOIN tb_periodo_letivo pl ON pl.id_periodo_letivo = t.id_periodo_letivo;

-----------------------------------------------------------------
-- 4. mv_indicadores_disciplina - MATERIALIZED VIEW de indicadores
-- Por disciplina: matrículas, aprovados, reprovados (por nota e por falta),
-- média geral e frequência média. O resultado fica GRAVADO em disco.
--
-- POLÍTICA DE ATUALIZAÇÃO (e por quê):
--   * Quando: um REFRESH por dia (de madrugada) e outro logo depois que as
--     notas de uma turma são lançadas.
--   * Por que não uma view comum: o painel da coordenação recalcularia todo
--     o histórico a cada consulta. Indicador de gestão não precisa ser em
--     tempo real; um dia de atraso é aceitável.
--   * Por que não atualizar a cada matrícula (trigger): as notas são lançadas
--     em lote; refazer a agregação a cada linha gravada seria desperdício.
--   * Por que CONCURRENTLY: o REFRESH normal bloqueia a leitura da MV enquanto
--     ela é reconstruída; o CONCURRENTLY deixa a MV legível o tempo todo.
--     Ele EXIGE um índice único na MV (criado abaixo).
-----------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS mv_indicadores_disciplina;

CREATE MATERIALIZED VIEW mv_indicadores_disciplina AS
SELECT
    d.id_disciplina,
    d.codigo AS codigo_disciplina,
    d.nome   AS disciplina,
    COUNT(*)                                                   AS matriculas,
    COUNT(*) FILTER (WHERE h.situacao = 'Aprovado')            AS aprovados,
    COUNT(*) FILTER (WHERE h.situacao = 'Reprovado por Nota')  AS reprovados_nota,
    COUNT(*) FILTER (WHERE h.situacao = 'Reprovado por Falta') AS reprovados_falta,
    COUNT(*) FILTER (WHERE h.situacao = 'Cursando')            AS cursando,
    ROUND(AVG(h.media_geral), 2) AS media_geral,
    ROUND(AVG(h.frequencia), 1)  AS frequencia_media
FROM tb_historico h
JOIN tb_matricula m  ON m.id_matricula  = h.id_matricula
JOIN tb_turma t      ON t.id_turma      = m.id_turma
JOIN tb_disciplina d ON d.id_disciplina = t.id_disciplina
GROUP BY d.id_disciplina, d.codigo, d.nome;

-- Índice único: exigido pelo REFRESH ... CONCURRENTLY
CREATE UNIQUE INDEX ux_mv_indicadores_disciplina ON mv_indicadores_disciplina (id_disciplina);

-- Como atualizar (é o comando que a política acima manda executar):
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_indicadores_disciplina;

-----------------------------------------------------------------
-- Conferência (o pgAdmin mostra o resultado da última consulta;
-- para ver as outras, selecione a linha e execute)
-----------------------------------------------------------------
SELECT * FROM v_oferta ORDER BY id_turma;

SELECT * FROM v_historico WHERE id_aluno = 3 ORDER BY disciplina;

SELECT * FROM mv_indicadores_disciplina ORDER BY disciplina;

SELECT * FROM v_vagas ORDER BY id_turma;
