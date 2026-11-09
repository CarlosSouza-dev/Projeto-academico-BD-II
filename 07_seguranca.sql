-----------------------------------------------------------------
-- 07_seguranca.sql  (Marco 2 - Segurança e Controle de Acesso)
-- Papéis (roles), GRANT/REVOKE e Row-Level Security (RLS).
-- Rode APÓS 01 a 06b, com o usuário do contêiner (bd2, que é o dono das
-- tabelas). Pode ser executado de novo sem erro.
--
-- QUEM PODE O QUÊ
--   aluno        -> vê a oferta e as vagas, e SÓ o próprio cadastro,
--                   as próprias matrículas e o próprio histórico (RLS)
--   secretaria   -> lê tudo, matricula e lança notas; não apaga histórico
--   coordenacao  -> só leitura, inclusive os indicadores
--
-- COMO O BANCO SABE QUAL ALUNO ESTÁ CONECTADO?
--   O diagrama não tem coluna de usuário (e não foi alterado). Convenção:
--   cada aluno entra com um papel chamado aluno_<id_aluno> (ex.: aluno_3),
--   que é membro do papel de grupo "aluno". A regra do RLS compara o nome do
--   papel conectado (current_user) com 'aluno_' || id_aluno.
--   Aqui criamos os papéis de 3 alunos para a demonstração; num sistema real,
--   o papel do aluno seria criado junto com o cadastro dele.
-----------------------------------------------------------------
SET search_path TO academico;

-----------------------------------------------------------------
-- 1. Papéis
-- Papel de grupo: NOLOGIN (ninguém entra com ele; ele só agrupa permissões).
-- Papel não pertence a um banco, e sim ao servidor; por isso o 01 (DROP
-- SCHEMA) não os apaga, e o IF NOT EXISTS evita erro ao rodar de novo.
-----------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'aluno') THEN
        CREATE ROLE aluno NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'secretaria') THEN
        CREATE ROLE secretaria NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'coordenacao') THEN
        CREATE ROLE coordenacao NOLOGIN;
    END IF;

    -- alunos da demonstração (membros do grupo "aluno"). NOLOGIN: na
    -- demonstração usamos SET ROLE; para o aluno entrar de verdade seria
    -- ALTER ROLE aluno_3 LOGIN PASSWORD '...';
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'aluno_3') THEN
        CREATE ROLE aluno_3 NOLOGIN IN ROLE aluno;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'aluno_4') THEN
        CREATE ROLE aluno_4 NOLOGIN IN ROLE aluno;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'aluno_91') THEN
        CREATE ROLE aluno_91 NOLOGIN IN ROLE aluno;
    END IF;
END;
$$;

-----------------------------------------------------------------
-- 2. GRANT / REVOKE (cada papel recebe só o que precisa)
-----------------------------------------------------------------
GRANT USAGE ON SCHEMA academico TO aluno, secretaria, coordenacao;

-- aluno: as views de oferta e vagas, e as tabelas que a v_historico usa.
-- As três tabelas com dados pessoais (aluno, matrícula, histórico) são
-- filtradas pelo RLS logo abaixo.
GRANT SELECT ON v_oferta, v_vagas, v_historico TO aluno;
GRANT SELECT ON tb_aluno, tb_matricula, tb_historico,
                tb_turma, tb_disciplina, tb_periodo_letivo TO aluno;

-- secretaria: lê tudo; matricula, lança notas e ajusta turmas.
-- (UPDATE em tb_turma também é exigido pelo SELECT ... FOR UPDATE do 06b)
GRANT SELECT ON ALL TABLES IN SCHEMA academico TO secretaria;
GRANT INSERT, UPDATE ON tb_aluno, tb_matricula, tb_historico, tb_turma TO secretaria;
GRANT INSERT ON tb_log_matricula TO secretaria;      -- a trigger do 09 grava o log
-- O histórico nunca é apagado: a matrícula é cancelada mudando o status.
REVOKE DELETE ON tb_aluno, tb_matricula, tb_historico FROM secretaria;

-- coordenacao: só leitura (inclui a materialized view de indicadores).
GRANT SELECT ON ALL TABLES IN SCHEMA academico TO coordenacao;

-- Procedures: por padrão QUALQUER papel (PUBLIC) pode executar.
-- Tiramos isso e deixamos a matrícula segura só para a secretaria.
REVOKE EXECUTE ON PROCEDURE sp_matricular_ingenuo(INT, INT)  FROM PUBLIC;
REVOKE EXECUTE ON PROCEDURE sp_matricular_bloqueio(INT, INT) FROM PUBLIC;
GRANT  EXECUTE ON PROCEDURE sp_matricular_bloqueio(INT, INT) TO secretaria;

-----------------------------------------------------------------
-- 3. ROW-LEVEL SECURITY (RLS)
-- Com o RLS ligado, cada papel só vê as linhas que uma POLICY libera para ele.
-- Papel sem policy não vê nenhuma linha. O dono das tabelas (bd2) não é
-- afetado pelo RLS; por isso a demonstração usa SET ROLE para "virar" o aluno.
-----------------------------------------------------------------
ALTER TABLE tb_aluno     ENABLE ROW LEVEL SECURITY;
ALTER TABLE tb_matricula ENABLE ROW LEVEL SECURITY;
ALTER TABLE tb_historico ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_aluno_cadastro   ON tb_aluno;
DROP POLICY IF EXISTS pol_aluno_matriculas ON tb_matricula;
DROP POLICY IF EXISTS pol_aluno_historico  ON tb_historico;
DROP POLICY IF EXISTS pol_equipe           ON tb_aluno;
DROP POLICY IF EXISTS pol_equipe           ON tb_matricula;
DROP POLICY IF EXISTS pol_equipe           ON tb_historico;

-- aluno: só a linha em que o id é o dele (aluno_3 -> id_aluno = 3)
CREATE POLICY pol_aluno_cadastro ON tb_aluno
    FOR SELECT TO aluno
    USING (current_user = 'aluno_' || id_aluno);

CREATE POLICY pol_aluno_matriculas ON tb_matricula
    FOR SELECT TO aluno
    USING (current_user = 'aluno_' || id_aluno);

-- tb_historico não tem id_aluno: o dono da linha vem pela matrícula
CREATE POLICY pol_aluno_historico ON tb_historico
    FOR SELECT TO aluno
    USING (id_matricula IN (SELECT id_matricula
                              FROM tb_matricula
                             WHERE current_user = 'aluno_' || id_aluno));

-- secretaria e coordenação: todas as linhas (o que cada uma pode FAZER
-- já foi limitado pelos GRANTs acima)
CREATE POLICY pol_equipe ON tb_aluno     TO secretaria, coordenacao USING (true) WITH CHECK (true);
CREATE POLICY pol_equipe ON tb_matricula TO secretaria, coordenacao USING (true) WITH CHECK (true);
CREATE POLICY pol_equipe ON tb_historico TO secretaria, coordenacao USING (true) WITH CHECK (true);

-----------------------------------------------------------------
-- 4. Conferência (SET ROLE troca o papel da sessão; RESET ROLE volta ao bd2)
-----------------------------------------------------------------
SET ROLE aluno_3;
SELECT current_user AS papel, COUNT(*) AS linhas_de_historico FROM tb_historico;   -- 4 (sem RLS: 300)
RESET ROLE;

-- Policies criadas (último resultado, o que o pgAdmin mostra)
SELECT tablename AS tabela, policyname AS policy, roles AS papeis
FROM pg_policies
WHERE schemaname = 'academico'
ORDER BY tablename, policyname;


/*-----------------------------------------------------------------
DEMONSTRAÇÃO AO VIVO (selecione cada trecho e aperte F5)

-- (a) O aluno 3 vê só o que é dele
SET ROLE aluno_3;
SELECT * FROM v_historico;                         -- só as 4 linhas do aluno 3
SELECT COUNT(*) FROM tb_historico;                 -- 4 (sem o RLS seriam 300)
SELECT * FROM v_historico WHERE id_aluno = 4;      -- 0 linhas: não vê o colega
SELECT * FROM v_vagas;                             -- a oferta e as vagas ele vê
RESET ROLE;

-- (b) ERRO DE PROPÓSITO: o aluno não altera notas (permission denied)
SET ROLE aluno_3;
UPDATE tb_historico SET nota_a1 = 10;
RESET ROLE;

-- (c) ERRO DE PROPÓSITO: o aluno não lê a tabela de professores (permission denied)
SET ROLE aluno_3;
SELECT * FROM tb_professor;
RESET ROLE;

-- (d) ERRO DE PROPÓSITO: a secretaria não apaga histórico (permission denied)
SET ROLE secretaria;
DELETE FROM tb_historico WHERE id_historico = 1;
RESET ROLE;

-- (e) A secretaria matricula pela procedure segura; o aluno não pode
SET ROLE secretaria;
CALL sp_matricular_bloqueio(91, 5);                -- matricula o aluno 91 na turma 5
RESET ROLE;
SET ROLE aluno_91;
CALL sp_matricular_bloqueio(91, 6);                -- ERRO DE PROPÓSITO: permission denied
RESET ROLE;
-- limpeza do item (e)
DELETE FROM tb_log_matricula WHERE id_matricula IN (SELECT id_matricula FROM tb_matricula WHERE id_aluno = 91);
DELETE FROM tb_matricula WHERE id_aluno = 91;

Se algum comando der erro no meio de um trecho, rode RESET ROLE; antes de continuar.
-----------------------------------------------------------------*/
