-----------------------------------------------------------------
-- 04_views.sql  (Marco 2 - Administração e Operação)
-- 3 views (oferta, vagas, histórico) + 1 materialized view de indicadores.
-- Rode APÓS 01, 02 e 03. Pode ser reexecutado sem erro.
-----------------------------------------------------------------
SET search_path TO academico;

-----------------------------------------------------------------
-- 1. v_oferta - oferta de turmas
-- O que o aluno vê ao escolher disciplinas: disciplina, professor, turno,
-- vagas e horários já formatados ("Seg 08:15-11:00 (JB1)").
-- Convenção de dia_semana adotada: 1=Dom, 2=Seg, ... 7=Sáb (as turmas da
-- carga usam 2..6, ou seja, segunda a sexta).
-- É uma view comum (executa com os direitos do dono): quem a consulta não
-- precisa de acesso às tabelas-base, e o e-mail do professor não é exposto.
-----------------------------------------------------------------
CREATE OR REPLACE VIEW v_oferta AS
SELECT
    t.id_turma,
    pl.ano,
    pl.semestre,
    (CURRENT_DATE BETWEEN pl.data_inicio AND pl.data_fim) AS periodo_vigente,
    t.codigo              AS codigo_turma,
    d.codigo              AS codigo_disciplina,
    d.nome                AS disciplina,
    d.ch_total_disciplina AS carga_horaria,
    p.nome_professor      AS professor,
    t.turno,
    t.vagas,
    COALESCE(h.horarios, 'A definir') AS horarios
FROM tb_turma t
JOIN tb_periodo_letivo pl ON pl.id_periodo_letivo = t.id_periodo_letivo
JOIN tb_disciplina d      ON d.id_disciplina      = t.id_disciplina
JOIN tb_professor p       ON p.id_professor       = t.id_professor
LEFT JOIN LATERAL (
    SELECT string_agg(
               (ARRAY['Dom','Seg','Ter','Qua','Qui','Sex','Sáb'])[th.dia_semana]
               || ' ' || substring(th.faixa FROM 2 FOR 5)      -- '[08:15:00,11:00:00)' -> 08:15
               || '-'  || substring(th.faixa FROM 11 FOR 5)    --                         -> 11:00
               || ' (' || s.codigo || ')',
               '; ' ORDER BY th.dia_semana, th.faixa) AS horarios
    FROM tb_turma_horario th
    JOIN tb_sala s ON s.id_sala = th.id_sala
    WHERE th.id_turma = t.id_turma
) h ON true;

COMMENT ON VIEW v_oferta IS 'Oferta de turmas por período letivo, com professor, turno, vagas e horários formatados.';

-----------------------------------------------------------------
-- 2. v_vagas - ocupação das turmas
-- Vaga ocupada = matrícula com status 'Ativa' (trancada/cancelada libera a
-- vaga; concluída é de período já encerrado). 'SUPERLOTADA' só aparece se
-- houver overbooking, ou seja, é a view que denuncia a anomalia da última vaga.
-- Também é uma view comum: agrega as matrículas de todos os alunos sem
-- expor dados individuais.
-----------------------------------------------------------------
CREATE OR REPLACE VIEW v_vagas AS
SELECT
    t.id_turma,
    pl.ano,
    pl.semestre,
    t.codigo AS codigo_turma,
    d.nome   AS disciplina,
    t.vagas,
    COALESCE(o.ocupadas, 0)::int            AS ocupadas,
    (t.vagas - COALESCE(o.ocupadas, 0))::int AS livres,
    ROUND(100.0 * COALESCE(o.ocupadas, 0) / NULLIF(t.vagas, 0), 1) AS pct_ocupacao,
    CASE
        WHEN COALESCE(o.ocupadas, 0) > t.vagas  THEN 'SUPERLOTADA'
        WHEN COALESCE(o.ocupadas, 0) = t.vagas  THEN 'LOTADA'
        ELSE 'COM VAGAS'
    END AS situacao_vagas
FROM tb_turma t
JOIN tb_periodo_letivo pl ON pl.id_periodo_letivo = t.id_periodo_letivo
JOIN tb_disciplina d      ON d.id_disciplina      = t.id_disciplina
LEFT JOIN (
    SELECT id_turma, COUNT(*) AS ocupadas
    FROM tb_matricula
    WHERE status_matricula = 'Ativa'
    GROUP BY id_turma
) o ON o.id_turma = t.id_turma;

COMMENT ON VIEW v_vagas IS 'Vagas, ocupadas e livres por turma (ocupada = matrícula Ativa).';

-----------------------------------------------------------------
-- 3. v_historico - histórico acadêmico detalhado
-- security_invoker = true: a view executa com os direitos de QUEM CONSULTA,
-- e não do dono. É isso que faz o row-level security das tabelas-base
-- (07_seguranca.sql) valer também por aqui: um aluno consultando
-- v_historico só enxerga as próprias linhas. Sem essa opção, a view rodaria
-- como o dono e contornaria o RLS.
-----------------------------------------------------------------
CREATE OR REPLACE VIEW v_historico WITH (security_invoker = true) AS
SELECT
    a.id_aluno,
    a.nome_aluno,
    c.nome_curso,
    pl.ano,
    pl.semestre,
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
JOIN tb_curriculo cur     ON cur.id_curriculo     = a.id_curriculo
JOIN tb_curso c           ON c.id_curso           = cur.id_curso
JOIN tb_turma t           ON t.id_turma           = m.id_turma
JOIN tb_disciplina d      ON d.id_disciplina      = t.id_disciplina
JOIN tb_periodo_letivo pl ON pl.id_periodo_letivo = t.id_periodo_letivo;

COMMENT ON VIEW v_historico IS 'Histórico por aluno/disciplina/período (security_invoker: respeita o RLS de quem consulta).';

-----------------------------------------------------------------
-- 4. mv_indicadores_disciplina - MATERIALIZED VIEW de indicadores
-- Por período letivo e disciplina: matrículas, aprovados, reprovados
-- (por nota e por falta), em curso, taxa de aprovação, média geral e
-- frequência média. É uma consulta analítica que varre todo o histórico.
--
-- POLÍTICA DE ATUALIZAÇÃO (e por quê):
--  1) Ritmo: REFRESH diário, de madrugada (02:00, via pg_cron ou cron do
--     sistema chamando CALL sp_atualizar_indicadores()), mais um REFRESH
--     sob demanda logo após o fechamento/lançamento de notas de uma turma.
--  2) Por que não a cada escrita (trigger): o histórico é gravado em rajadas
--     (lançamento de notas). Refazer a agregação inteira a cada linha custaria
--     caro e criaria contenção sobre uma tabela que o fluxo de matrícula
--     usa o tempo todo.
--  3) Por que não uma view comum: cada consulta de painel reprocessaria o
--     histórico inteiro. Indicador de gestão não precisa ser tempo real:
--     um atraso de até um dia é aceitável e o dado mostra 'atualizado_em'.
--  4) Por que CONCURRENTLY: o REFRESH normal bloqueia a leitura durante a
--     reconstrução. CONCURRENTLY mantém a MV legível o tempo todo (custa um
--     pouco mais de processamento) e exige um índice ÚNICO, criado abaixo.
--  5) Dado sensível: a MV não guarda nada individual (só agregados), então
--     pode ser lida pela coordenação sem RLS.
-----------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS mv_indicadores_disciplina;

CREATE MATERIALIZED VIEW mv_indicadores_disciplina AS
SELECT
    pl.id_periodo_letivo,
    pl.ano,
    pl.semestre,
    d.id_disciplina,
    d.codigo AS codigo_disciplina,
    d.nome   AS disciplina,
    COUNT(*)                                                    AS matriculas,
    COUNT(*) FILTER (WHERE h.situacao = 'Aprovado')             AS aprovados,
    COUNT(*) FILTER (WHERE h.situacao = 'Reprovado por Nota')   AS reprovados_nota,
    COUNT(*) FILTER (WHERE h.situacao = 'Reprovado por Falta')  AS reprovados_falta,
    COUNT(*) FILTER (WHERE h.situacao = 'Cursando')             AS cursando,
    ROUND(100.0 * COUNT(*) FILTER (WHERE h.situacao = 'Aprovado')
          / NULLIF(COUNT(*) FILTER (WHERE h.situacao <> 'Cursando'), 0), 1) AS taxa_aprovacao,
    ROUND(AVG(h.media_geral), 2) AS media_geral_media,
    ROUND(AVG(h.frequencia), 1)  AS frequencia_media,
    now() AS atualizado_em
FROM tb_historico h
JOIN tb_matricula m       ON m.id_matricula       = h.id_matricula
JOIN tb_turma t           ON t.id_turma           = m.id_turma
JOIN tb_disciplina d      ON d.id_disciplina      = t.id_disciplina
JOIN tb_periodo_letivo pl ON pl.id_periodo_letivo = t.id_periodo_letivo
GROUP BY pl.id_periodo_letivo, pl.ano, pl.semestre, d.id_disciplina, d.codigo, d.nome
WITH DATA;

-- Índice único: pré-requisito do REFRESH ... CONCURRENTLY.
CREATE UNIQUE INDEX ux_mv_indicadores_disciplina
    ON mv_indicadores_disciplina (id_periodo_letivo, id_disciplina);

COMMENT ON MATERIALIZED VIEW mv_indicadores_disciplina IS
    'Indicadores por período e disciplina. Atualização: REFRESH CONCURRENTLY diário (02:00) + sob demanda após fechamento de notas, via CALL sp_atualizar_indicadores(). Não atualizar por trigger: histórico é gravado em rajadas e a agregação varre a tabela inteira.';

-- Procedimento de atualização. SECURITY DEFINER: quem não é dono da MV
-- (secretaria, coordenação) pode atualizá-la sem receber direitos sobre as
-- tabelas. search_path fixo evita sequestro de nomes (boa prática em DEFINER).
CREATE OR REPLACE PROCEDURE sp_atualizar_indicadores()
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = academico, pg_temp
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_indicadores_disciplina;
END;
$$;

REVOKE ALL ON PROCEDURE sp_atualizar_indicadores() FROM PUBLIC;

-----------------------------------------------------------------
-- Conferência rápida
-----------------------------------------------------------------
SELECT * FROM v_oferta ORDER BY id_turma;

SELECT * FROM v_vagas ORDER BY id_turma;

SELECT nome_aluno, disciplina, ano, semestre, media_geral, frequencia, situacao
FROM v_historico
WHERE id_aluno = 3
ORDER BY ano, semestre, disciplina;

SELECT * FROM mv_indicadores_disciplina ORDER BY disciplina;
