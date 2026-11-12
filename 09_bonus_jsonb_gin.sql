-----------------------------------------------------------------
-- 09_bonus_jsonb_gin.sql  (BÔNUS: JSONB com índice GIN, até +0,5 na A2)
--
-- tb_log_matricula guarda a auditoria das matrículas. A coluna detalhe
-- passa de TEXT para JSONB (JSON guardado em formato binário, que o banco
-- entende e consegue pesquisar por dentro). Depois ela ganha:
--   1) um índice GIN, que acelera a busca por conteúdo do JSON (operador @>);
--   2) uma trigger que grava o log sozinha a cada nova matrícula.
--
-- Por que GIN e não o índice comum (B-tree)? O B-tree ordena o valor inteiro
-- da coluna; serve para =, <, >. O GIN é um índice "invertido": guarda cada
-- chave e valor de DENTRO do documento e responde rápido "quais linhas têm
-- id_turma = 1?". A prova do ganho está no 05b_evidencias_explain.sql.
--
-- Rode APÓS 01 a 07. Pode ser executado de novo sem erro.
-----------------------------------------------------------------
SET search_path TO academico;

-- 1) TEXT -> JSONB (a tabela está vazia; o USING diz como converter)
ALTER TABLE tb_log_matricula
    ALTER COLUMN detalhe TYPE jsonb USING detalhe::jsonb;

-- 2) Índice GIN na coluna JSONB
CREATE INDEX IF NOT EXISTS idx_log_detalhe_gin
    ON tb_log_matricula USING gin (detalhe);

-- 3) Trigger de auditoria (dois objetos: a função e a trigger)
CREATE OR REPLACE FUNCTION fn_log_matricula()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- NEW é a matrícula que acabou de entrar
    INSERT INTO tb_log_matricula (id_matricula, acao, usuario, detalhe)
    VALUES (NEW.id_matricula,
            'MATRICULA',
            current_user,
            jsonb_build_object('id_aluno', NEW.id_aluno,
                               'id_turma', NEW.id_turma,
                               'status',   NEW.status_matricula));
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_matricula_log ON tb_matricula;

CREATE TRIGGER trg_matricula_log
  AFTER INSERT ON tb_matricula
FOR EACH ROW
EXECUTE FUNCTION fn_log_matricula();

-- Conferência: a coluna agora é jsonb e a trigger existe
SELECT c.column_name AS coluna, c.data_type AS tipo,
       (SELECT COUNT(*) FROM information_schema.triggers
         WHERE event_object_table = 'tb_matricula') AS triggers_em_tb_matricula
FROM information_schema.columns c
WHERE c.table_schema = 'academico'
  AND c.table_name = 'tb_log_matricula'
  AND c.column_name = 'detalhe';


/*-----------------------------------------------------------------
DEMONSTRAÇÃO AO VIVO (selecione o trecho e aperte F5)
BEGIN ... ROLLBACK: tudo é desfeito no final, o banco fica como estava.

BEGIN;
-- a trigger grava o log sozinha
INSERT INTO tb_matricula (id_aluno, id_turma, status_matricula) VALUES (91, 5, 'Ativa');
SELECT * FROM tb_log_matricula;

-- busca por conteúdo do JSON (@> = "contém"); é a busca que o GIN acelera
SELECT * FROM tb_log_matricula WHERE detalhe @> '{"id_turma": 5}';

-- ->> lê um campo do JSON como texto
SELECT detalhe ->> 'id_aluno' AS aluno, detalhe ->> 'status' AS status FROM tb_log_matricula;
ROLLBACK;
-----------------------------------------------------------------*/
