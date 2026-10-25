-----------------------------------------------------------------
-- 06d_comparacao_custos.sql  (Marco 2 - Comparação fundamentada)
-- Roda o MESMO experimento nos 3 modos (ingênuo, bloqueio, serializable)
-- em cenários de contenção diferentes, várias vezes, e resume:
--   * correção:     overbooking (houve vaga além do limite?)
--   * custo:        duração média (tempo até todos receberem resposta)
--   * contenção e retentativas: quantas transações abortaram e foram repetidas
-- A análise escrita está em docs/comparacao_concorrencia.md.
--
-- Cenários (10 alunos concorrentes, todos na turma 1):
--   A) 1 vaga livre,  pausa 0,2 s  -> a "última vaga": disputa total
--   B) 5 vagas livres, pausa 0,2 s -> disputa parcial: cabem 5 dos 10
--   C) 10 vagas livres, pausa 0,2 s -> há vaga para todos: contenção "à toa"
--   D) 1 vaga livre,  SEM pausa    -> janela mínima: o erro ainda acontece?
--
-- Rode APÓS 06, 06b e 06c. Demora cerca de 1 minuto. No pgAdmin execute o arquivo
-- inteiro (F5): a tabela comparativa é a última consulta. Os tempos variam por
-- máquina; o que não varia é a correção (overbooking) e a ordem de grandeza
-- das retentativas.
-----------------------------------------------------------------
SET search_path TO academico, public;

DROP TABLE IF EXISTS pg_temp.rodadas;
CREATE TEMP TABLE rodadas (
    cenario text, repeticao int, modo text, concorrentes int, vagas_livres int, pausa numeric,
    matriculados int, sem_vaga int, retentativas int, overbooking int, duracao_ms numeric);

DO $$
DECLARE
    c       record;
    m       text;
    r       int;
    reps    int;
    res     record;
BEGIN
    FOR c IN SELECT * FROM (VALUES
                ('A', 1,  0.2::numeric, 3),
                ('B', 5,  0.2::numeric, 3),
                ('C', 10, 0.2::numeric, 3),
                ('D', 1,  0::numeric,   10)
            ) AS v(cenario, vagas_livres, pausa, repeticoes)
    LOOP
        FOREACH m IN ARRAY ARRAY['ingenuo', 'bloqueio', 'serializable'] LOOP
            FOR r IN 1..c.repeticoes LOOP
                SELECT * INTO res FROM sp_simular_disputa(m, 1, ARRAY[91,92,93,94,95,96,97,98,99,100],
                                                          c.vagas_livres, c.pausa);
                INSERT INTO rodadas VALUES (c.cenario, r, m, res.concorrentes, c.vagas_livres, c.pausa,
                                            res.matriculados, res.sem_vaga, res.retentativas,
                                            res.overbooking, res.duracao_ms);
            END LOOP;
        END LOOP;
    END LOOP;
    PERFORM sp_limpar_disputa();
END $$;

-- Estado final restaurado: a turma 1 volta a ter 1 vaga livre (deve mostrar COM VAGAS)
SELECT id_turma, vagas, ocupadas, livres, situacao_vagas FROM v_vagas WHERE id_turma = 1;

-- RESUMO por cenário e modo (média das repetições): última consulta
SELECT cenario,
       vagas_livres,
       pausa,
       modo,
       COUNT(*)                                        AS execucoes,
       ROUND(AVG(matriculados), 1)                     AS matriculados_medio,
       ROUND(AVG(retentativas), 1)                     AS retentativas_medias,
       MAX(overbooking)                                AS overbooking_maximo,
       COUNT(*) FILTER (WHERE overbooking > 0)         AS execucoes_com_anomalia,
       ROUND(AVG(duracao_ms), 0)                       AS duracao_media_ms
FROM rodadas
GROUP BY cenario, vagas_livres, pausa, modo
ORDER BY cenario, CASE modo WHEN 'ingenuo' THEN 1 WHEN 'bloqueio' THEN 2 ELSE 3 END;
