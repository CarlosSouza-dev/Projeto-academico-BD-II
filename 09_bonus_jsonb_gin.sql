-----------------------------------------------------------------
-- 09_bonus_jsonb_gin.sql  (BÔNUS: JSONB com índice GIN, até +0,5 na A2)
--
-- tb_log_matricula.detalhe é uma coluna TEXT no diagrama oficial (que não foi
-- alterado). Aqui ela passa a guardar um documento JSON de auditoria e ganha:
--   1) um CHECK que garante que o texto é um JSON válido;
--   2) um índice GIN sobre a EXPRESSÃO (detalhe::jsonb), que acelera
--      buscas por conteúdo do documento (operador @>);
--   3) triggers que gravam o log automaticamente a cada matrícula/mudança
--      de status.
-- Rode APÓS 01 a 07 (idempotente).
--
-- pgAdmin: execute o arquivo INTEIRO (F5). As mensagens do teste do CHECK aparecem em
-- "Messages"; a última consulta (logs_restantes = 0) aparece em "Data Output".
-- Para mostrar cada passo ao vivo, SELECIONE o trecho da demonstração e execute.
--
-- Por que GIN e não B-tree? O B-tree ordena valores inteiros; só serve para
-- igualdade/ordem da coluna toda. O GIN é um índice INVERTIDO: indexa cada
-- chave/valor DENTRO do documento e responde "quais linhas contêm
-- {"id_turma": 1}?" sem ler a tabela. jsonb_path_ops indexa só o que o
-- operador @> usa (hashes de caminho+valor): índice menor e mais rápido que o
-- jsonb_ops padrão, ao custo de não atender os operadores de existência (?, ?|, ?&).
--
-- Evidência de ganho medido (200.000 registros): evidencias_explain.txt, consulta 5.
-----------------------------------------------------------------
SET search_path TO academico, public;

-- 1) detalhe deve ser JSON válido (ou NULL). pg_input_is_valid: PostgreSQL 16+.
ALTER TABLE tb_log_matricula DROP CONSTRAINT IF EXISTS ck_log_detalhe_json;
ALTER TABLE tb_log_matricula
    ADD CONSTRAINT ck_log_detalhe_json CHECK (detalhe IS NULL OR pg_input_is_valid(detalhe, 'jsonb'));

-- 2) Índice GIN sobre a expressão: o texto é convertido para jsonb na indexação.
CREATE INDEX IF NOT EXISTS idx_log_detalhe_gin
    ON tb_log_matricula USING gin ((detalhe::jsonb) jsonb_path_ops);

-- 3) Auditoria automática. SECURITY DEFINER: grava o log mesmo quando quem
--    matricula não tem direito de escrita no log (a trilha não depende de
--    permissão de quem a gera). session_user = quem realmente conectou.
CREATE OR REPLACE FUNCTION fn_log_matricula()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = academico, pg_temp
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO tb_log_matricula (id_matricula, acao, usuario, detalhe)
        VALUES (NEW.id_matricula, 'MATRICULA', session_user,
                jsonb_build_object('origem',      'trigger',
                                   'id_aluno',    NEW.id_aluno,
                                   'id_turma',    NEW.id_turma,
                                   'status_novo', NEW.status_matricula)::text);
    ELSE
        INSERT INTO tb_log_matricula (id_matricula, acao, usuario, detalhe)
        VALUES (NEW.id_matricula, 'STATUS_ALTERADO', session_user,
                jsonb_build_object('origem',          'trigger',
                                   'id_aluno',        NEW.id_aluno,
                                   'id_turma',        NEW.id_turma,
                                   'status_anterior', OLD.status_matricula,
                                   'status_novo',     NEW.status_matricula)::text);
    END IF;
    RETURN NULL;     -- AFTER trigger: o retorno é ignorado
END;
$$;

REVOKE ALL ON FUNCTION fn_log_matricula() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_matricula_log_insert ON tb_matricula;
DROP TRIGGER IF EXISTS trg_matricula_log_status ON tb_matricula;

CREATE TRIGGER trg_matricula_log_insert
    AFTER INSERT ON tb_matricula
    FOR EACH ROW EXECUTE FUNCTION fn_log_matricula();

-- Duas triggers (e não uma "INSERT OR UPDATE") porque a condição WHEN que
-- compara OLD e NEW não pode existir em trigger de INSERT.
CREATE TRIGGER trg_matricula_log_status
    AFTER UPDATE OF status_matricula ON tb_matricula
    FOR EACH ROW
    WHEN (OLD.status_matricula IS DISTINCT FROM NEW.status_matricula)
    EXECUTE FUNCTION fn_log_matricula();

-----------------------------------------------------------------
-- Demonstração (a parte entre BEGIN e ROLLBACK é DESFEITA no final)
-----------------------------------------------------------------
-- COMMIT: confirma o que foi criado acima. Sem ele, o ROLLBACK da demonstração
-- desfaria também o CHECK, o índice e as triggers, porque o pgAdmin envia o
-- arquivo como UMA transação só.
COMMIT;

-- 1) O CHECK recusa texto que não é JSON (mensagem em "Messages")
DO $$
BEGIN
    BEGIN
        INSERT INTO tb_log_matricula (id_matricula, acao, usuario, detalhe)
        VALUES (1, 'TESTE', 'demo', 'isto não é json');
        RAISE EXCEPTION 'FALHA: aceitou texto inválido';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: recusado pelo CHECK ck_log_detalhe_json';
    END;
END $$;

BEGIN;
-- 2) Matricular o aluno 91 na turma 5 e depois cancelar: o log é gravado sozinho
INSERT INTO tb_matricula (id_aluno, id_turma, status_matricula) VALUES (91, 5, 'Ativa');
UPDATE tb_matricula SET status_matricula = 'Cancelada' WHERE id_aluno = 91 AND id_turma = 5;

SELECT acao, usuario, detalhe::jsonb AS detalhe
FROM tb_log_matricula
ORDER BY id_log_matricula;

-- 3) Busca por conteúdo do JSON (operador @>, atendido pelo GIN)
SELECT id_log_matricula, acao, detalhe::jsonb ->> 'status_novo' AS status_novo
FROM tb_log_matricula
WHERE detalhe::jsonb @> '{"id_aluno": 91, "id_turma": 5}';

-- 4) O planner usa o GIN? Com 2 linhas ele prefere varrer a tabela (é mais barato);
--    forçamos o índice só para mostrar o plano. Com 200 mil linhas ele o escolhe
--    sozinho (veja evidencias_explain.txt, consulta 5).
SET LOCAL enable_seqscan = off;
EXPLAIN (COSTS OFF)
SELECT id_log_matricula FROM tb_log_matricula WHERE detalhe::jsonb @> '{"id_aluno": 91}';
ROLLBACK;

-- 5) Estado restaurado: sem logs de demonstração (última consulta; deve dar 0)
SELECT COUNT(*) AS logs_restantes FROM tb_log_matricula;
