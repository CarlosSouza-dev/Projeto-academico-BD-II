-----------------------------------------------------------------
-- 07_seguranca.sql  (Marco 2 - Segurança e Controle de Acesso)
-- Papéis (roles), GRANT/REVOKE e Row-Level Security (RLS).
-- Rode APÓS 01 a 06 (usa views, MV e funções criadas antes) como o dono
-- do schema / superusuário. Pode ser reexecutado sem erro.
--
-- pgAdmin: execute o arquivo INTEIRO (F5). Os testes (OK / FALHA) aparecem na aba
-- "Messages"; a última consulta (as policies criadas) aparece em "Data Output".
-- Para mostrar o RLS ao vivo, selecione só o trecho da seção 4 e execute.
-- Se um teste falhar, o script inteiro é desfeito (o pgAdmin o executa como uma só transação).
--
-- MODELO DE ACESSO
--   aluno        -> só enxerga o que é SEU (RLS) + oferta e vagas (views)
--   secretaria   -> opera matrículas/notas; lê tudo; nunca apaga histórico
--   coordenacao  -> só leitura de tudo + indicadores
--
-- COMO O BANCO SABE QUEM É O ALUNO?
--   O modelo (diagrama) não tem coluna de usuário em tb_aluno e não foi
--   alterado. Convenção: cada aluno acessa com um login chamado aluno_<id_aluno>
--   (ex.: aluno_3), que é MEMBRO do papel de grupo "aluno". A função
--   fn_id_aluno_logado() extrai o id desse nome. Isso é seguro porque o
--   nome do papel corrente (current_user) não pode ser trocado pelo próprio
--   usuário (diferente de uma variável de sessão tipo SET app.aluno = 3,
--   que qualquer um poderia alterar).
--
-- OBSERVAÇÕES DE SEGURANÇA
--   * O RLS não vale para superusuário nem para o dono das tabelas (por
--     padrão). Por isso a demonstração usa SET ROLE para virar o aluno.
--   * v_historico é security_invoker: sem isso ela executaria como o dono e
--     furaria o RLS. v_oferta e v_vagas são views comuns de propósito: expõem
--     só dados não sensíveis/agregados (sem e-mail de professor, sem CPF).
-----------------------------------------------------------------
SET search_path TO academico, public;

-----------------------------------------------------------------
-- 1. Papéis de grupo (sem login) e logins individuais dos alunos
-----------------------------------------------------------------
DO $$
DECLARE
    r text;
BEGIN
    FOREACH r IN ARRAY ARRAY['aluno', 'secretaria', 'coordenacao'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', r);
        END IF;
    END LOOP;
END $$;

-- Cria (ou reaproveita) o papel individual aluno_<id> como membro de "aluno".
-- NOLOGIN por padrão (ninguém entra sem a administração liberar). Para
-- liberar o acesso: CALL sp_provisionar_login_aluno(3, 'senha-forte');
CREATE OR REPLACE PROCEDURE sp_provisionar_login_aluno(p_id_aluno int, p_senha text DEFAULT NULL)
LANGUAGE plpgsql
AS $$
DECLARE
    v_role text := 'aluno_' || p_id_aluno;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM tb_aluno WHERE id_aluno = p_id_aluno) THEN
        RAISE EXCEPTION 'aluno % não existe', p_id_aluno;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_role) THEN
        EXECUTE format('CREATE ROLE %I NOLOGIN IN ROLE aluno', v_role);
    ELSE
        EXECUTE format('GRANT aluno TO %I', v_role);
    END IF;
    IF p_senha IS NOT NULL THEN
        EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', v_role, p_senha);
    END IF;
END;
$$;

DO $$
DECLARE
    a record;
BEGIN
    FOR a IN SELECT id_aluno FROM tb_aluno ORDER BY id_aluno LOOP
        CALL sp_provisionar_login_aluno(a.id_aluno);
    END LOOP;
END $$;

-- Quem está logado como aluno? (NULL para qualquer papel que não seja aluno_<id>)
-- STABLE: avaliada uma vez por consulta, o que permite o planner usar índice
-- (idx_matricula_aluno) no filtro do RLS. Sem SECURITY DEFINER de propósito:
-- current_user precisa ser quem está consultando.
CREATE OR REPLACE FUNCTION fn_id_aluno_logado()
RETURNS int
LANGUAGE sql
STABLE
AS $$
    SELECT substring(current_user FROM '^aluno_([0-9]+)$')::int
$$;

-----------------------------------------------------------------
-- 2. GRANT / REVOKE  (princípio do menor privilégio)
-----------------------------------------------------------------
-- 2.1 Ponto de partida: ninguém herda nada por ser PUBLIC.
REVOKE ALL ON SCHEMA academico FROM PUBLIC;
REVOKE ALL ON ALL TABLES    IN SCHEMA academico FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA academico FROM PUBLIC;   -- funções vêm com EXECUTE para PUBLIC
REVOKE ALL ON ALL PROCEDURES IN SCHEMA academico FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA academico REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

GRANT USAGE ON SCHEMA academico TO aluno, secretaria, coordenacao;
GRANT EXECUTE ON FUNCTION fn_id_aluno_logado() TO aluno, secretaria, coordenacao;   -- usada nas policies

-- 2.2 aluno: oferta, vagas e as próprias informações.
--     v_historico (security_invoker) exige leitura das tabelas-base; as
--     sensíveis (aluno, matrícula, histórico) ficam restritas pelo RLS.
GRANT SELECT ON v_oferta, v_vagas, v_historico TO aluno;
GRANT SELECT ON tb_aluno, tb_matricula, tb_historico,
                tb_turma, tb_disciplina, tb_periodo_letivo, tb_curriculo, tb_curso TO aluno;

-- 2.3 secretaria: lê tudo e opera matrículas e notas.
GRANT SELECT ON ALL TABLES IN SCHEMA academico TO secretaria;
GRANT SELECT ON mv_indicadores_disciplina TO secretaria;
GRANT INSERT, UPDATE, DELETE ON tb_aluno, tb_matricula, tb_historico, tb_turma, tb_turma_horario TO secretaria;
GRANT INSERT ON tb_log_matricula TO secretaria;
-- REVOKE: o histórico acadêmico e as matrículas NUNCA são apagados (a matrícula
-- é cancelada mudando o status; o log guarda a trilha). Concede-se DELETE
-- acima só em tabelas operacionais; aqui ele é retirado das auditáveis.
REVOKE DELETE ON tb_aluno, tb_matricula, tb_historico FROM secretaria;
GRANT EXECUTE ON PROCEDURE sp_atualizar_indicadores() TO secretaria;

-- 2.4 coordenacao: somente leitura, inclusive indicadores.
GRANT SELECT ON ALL TABLES IN SCHEMA academico TO coordenacao;
GRANT SELECT ON mv_indicadores_disciplina TO coordenacao;
GRANT EXECUTE ON PROCEDURE sp_atualizar_indicadores() TO coordenacao;

-- 2.5 Matrícula pela função segura (06b), se já criada: só a secretaria executa.
DO $$
BEGIN
    IF to_regprocedure('academico.sp_matricular_bloqueio(integer,integer,numeric)') IS NOT NULL THEN
        GRANT EXECUTE ON FUNCTION sp_matricular_bloqueio(integer, integer, numeric) TO secretaria;
    END IF;
END $$;

-----------------------------------------------------------------
-- 3. ROW-LEVEL SECURITY
-- Sem policy aplicável a um papel, ele não vê NENHUMA linha (negação por
-- padrão). Cada policy abre exatamente o que aquele papel pode ver.
-----------------------------------------------------------------
ALTER TABLE tb_aluno     ENABLE ROW LEVEL SECURITY;
ALTER TABLE tb_matricula ENABLE ROW LEVEL SECURITY;
ALTER TABLE tb_historico ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_aluno_proprio_cadastro   ON tb_aluno;
DROP POLICY IF EXISTS pol_aluno_proprias_matriculas ON tb_matricula;
DROP POLICY IF EXISTS pol_aluno_proprio_historico   ON tb_historico;
DROP POLICY IF EXISTS pol_secretaria_tudo           ON tb_aluno;
DROP POLICY IF EXISTS pol_secretaria_tudo           ON tb_matricula;
DROP POLICY IF EXISTS pol_secretaria_tudo           ON tb_historico;
DROP POLICY IF EXISTS pol_coordenacao_leitura       ON tb_aluno;
DROP POLICY IF EXISTS pol_coordenacao_leitura       ON tb_matricula;
DROP POLICY IF EXISTS pol_coordenacao_leitura       ON tb_historico;

-- aluno: só a própria linha de cadastro, as próprias matrículas e o próprio histórico.
CREATE POLICY pol_aluno_proprio_cadastro ON tb_aluno
    FOR SELECT TO aluno
    USING (id_aluno = fn_id_aluno_logado());

CREATE POLICY pol_aluno_proprias_matriculas ON tb_matricula
    FOR SELECT TO aluno
    USING (id_aluno = fn_id_aluno_logado());

-- O histórico não tem id_aluno: o dono é descoberto pela matrícula. A subconsulta
-- passa pelo RLS de tb_matricula também (defesa em profundidade).
CREATE POLICY pol_aluno_proprio_historico ON tb_historico
    FOR SELECT TO aluno
    USING (EXISTS (SELECT 1
                   FROM tb_matricula m
                   WHERE m.id_matricula = tb_historico.id_matricula
                     AND m.id_aluno = fn_id_aluno_logado()));

-- secretaria: acesso total às linhas (os comandos permitidos já são limitados pelos GRANTs).
CREATE POLICY pol_secretaria_tudo ON tb_aluno     FOR ALL TO secretaria USING (true) WITH CHECK (true);
CREATE POLICY pol_secretaria_tudo ON tb_matricula FOR ALL TO secretaria USING (true) WITH CHECK (true);
CREATE POLICY pol_secretaria_tudo ON tb_historico FOR ALL TO secretaria USING (true) WITH CHECK (true);

-- coordenacao: leitura de todas as linhas.
CREATE POLICY pol_coordenacao_leitura ON tb_aluno     FOR SELECT TO coordenacao USING (true);
CREATE POLICY pol_coordenacao_leitura ON tb_matricula FOR SELECT TO coordenacao USING (true);
CREATE POLICY pol_coordenacao_leitura ON tb_historico FOR SELECT TO coordenacao USING (true);

-----------------------------------------------------------------
-- 4. DEMONSTRAÇÃO (para a apresentação): o aluno 3 vê só o que é dele
-- Execute cada bloco SELECIONANDO-O (o pgAdmin mostra o resultado da última
-- consulta do trecho selecionado). SET ROLE "vira" o aluno; RESET ROLE volta.
-----------------------------------------------------------------
-- 4.1 Como dono/superusuário: todo o histórico (300 linhas)
SELECT COUNT(*) AS linhas_de_historico, COUNT(DISTINCT m.id_aluno) AS alunos
FROM tb_historico h JOIN tb_matricula m ON m.id_matricula = h.id_matricula;

-- 4.2 Como aluno_3: só as próprias linhas (4)
SET ROLE aluno_3;
SELECT current_user AS papel, fn_id_aluno_logado() AS id_aluno_logado,
       (SELECT COUNT(*) FROM tb_historico) AS linhas_de_historico_visiveis,
       (SELECT COUNT(*) FROM v_historico)  AS linhas_pela_view,
       (SELECT COUNT(*) FROM v_historico WHERE id_aluno = 4) AS linhas_do_aluno_4,
       (SELECT COUNT(*) FROM tb_aluno)     AS cadastros_visiveis;
RESET ROLE;

-- 4.3 Como coordenacao: lê tudo, não escreve
SET ROLE coordenacao;
SELECT (SELECT COUNT(*) FROM tb_historico) AS linhas_de_historico_visiveis,
       (SELECT COUNT(*) FROM mv_indicadores_disciplina) AS linhas_de_indicadores;
RESET ROLE;

-----------------------------------------------------------------
-- 5. TESTES AUTOMÁTICOS (falham com erro se algo estiver aberto demais)
-----------------------------------------------------------------
-- Cada teste tenta algo e confere o resultado. Mensagens OK/FALHA: aba "Messages".
DO $$
DECLARE
    v_total_hist   int;
    v_hist_3       int;
    v_n            int;
    v_matric_4     int[];
BEGIN
    SELECT COUNT(*) INTO v_total_hist FROM tb_historico;
    SELECT COUNT(*) INTO v_hist_3
        FROM tb_historico h JOIN tb_matricula m ON m.id_matricula = h.id_matricula WHERE m.id_aluno = 3;
    SELECT array_agg(id_matricula) INTO v_matric_4 FROM tb_matricula WHERE id_aluno = 4;

    ---------------- ALUNO ----------------
    BEGIN
        SET LOCAL ROLE aluno_3;
        SELECT COUNT(*) INTO v_n FROM tb_historico;
        IF v_n <> v_hist_3 OR v_n = v_total_hist THEN
            RAISE EXCEPTION 'FALHA RLS: aluno_3 vê % linhas de histórico (esperado %)', v_n, v_hist_3;
        END IF;
        RAISE NOTICE 'OK  aluno_3 vê % de % linhas de histórico (só as dele)', v_n, v_total_hist;

        SELECT COUNT(*) INTO v_n FROM tb_historico WHERE id_matricula = ANY (v_matric_4);
        IF v_n <> 0 THEN RAISE EXCEPTION 'FALHA RLS: aluno_3 leu o histórico do aluno 4'; END IF;
        RAISE NOTICE 'OK  aluno_3 não lê o histórico do aluno 4 (0 linhas)';

        SELECT COUNT(*) INTO v_n FROM v_historico WHERE id_aluno <> 3;
        IF v_n <> 0 THEN RAISE EXCEPTION 'FALHA: v_historico vazou linhas de outro aluno'; END IF;
        SELECT COUNT(*) INTO v_n FROM v_historico;
        IF v_n <> v_hist_3 THEN RAISE EXCEPTION 'FALHA: v_historico mostra % linhas (esperado %)', v_n, v_hist_3; END IF;
        RAISE NOTICE 'OK  v_historico (security_invoker) respeita o RLS: só as % linhas do aluno 3', v_n;

        SELECT COUNT(*) INTO v_n FROM tb_aluno;
        IF v_n <> 1 THEN RAISE EXCEPTION 'FALHA RLS: aluno_3 vê % cadastros de alunos (CPF/e-mail de outros)', v_n; END IF;
        RAISE NOTICE 'OK  aluno_3 vê apenas o próprio cadastro (CPF e e-mail dos outros protegidos)';

        SELECT COUNT(*) INTO v_n FROM v_oferta;
        IF v_n = 0 THEN RAISE EXCEPTION 'FALHA: aluno não consegue ler v_oferta'; END IF;
        SELECT COUNT(*) INTO v_n FROM v_vagas;
        IF v_n = 0 THEN RAISE EXCEPTION 'FALHA: aluno não consegue ler v_vagas'; END IF;
        RAISE NOTICE 'OK  aluno_3 lê a oferta e as vagas de todas as turmas';
    END;

    BEGIN
        SET LOCAL ROLE aluno_3;
        UPDATE tb_historico SET nota_a1 = 10;
        RAISE EXCEPTION 'FALHA: aluno conseguiu alterar notas';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK  aluno_3 NÃO pode alterar notas (permission denied)';
    END;

    BEGIN
        SET LOCAL ROLE aluno_3;
        PERFORM 1 FROM tb_log_matricula;
        RAISE EXCEPTION 'FALHA: aluno leu o log de matrículas';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK  aluno_3 NÃO lê tb_log_matricula (permission denied)';
    END;

    BEGIN
        SET LOCAL ROLE aluno_3;
        PERFORM 1 FROM tb_professor;
        RAISE EXCEPTION 'FALHA: aluno leu tb_professor';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK  aluno_3 NÃO lê tb_professor (e-mails) (permission denied)';
    END;

    BEGIN
        SET LOCAL ROLE aluno_3;
        PERFORM 1 FROM mv_indicadores_disciplina;
        RAISE EXCEPTION 'FALHA: aluno leu os indicadores';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK  aluno_3 NÃO lê os indicadores (permission denied)';
    END;

    ---------------- SECRETARIA ----------------
    BEGIN
        SET LOCAL ROLE secretaria;
        SELECT COUNT(*) INTO v_n FROM tb_historico;
        IF v_n <> v_total_hist THEN RAISE EXCEPTION 'FALHA: secretaria vê % de % linhas', v_n, v_total_hist; END IF;
        UPDATE tb_historico SET nota_a1 = nota_a1 WHERE id_historico = 1;    -- escrita permitida (sem alterar o valor)
        RAISE NOTICE 'OK  secretaria lê todo o histórico (% linhas) e pode lançar notas', v_n;
    END;

    BEGIN
        SET LOCAL ROLE secretaria;
        DELETE FROM tb_historico WHERE id_historico = 1;
        RAISE EXCEPTION 'FALHA: secretaria apagou histórico';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK  secretaria NÃO apaga histórico (REVOKE DELETE)';
    END;

    BEGIN
        SET LOCAL ROLE secretaria;
        DELETE FROM tb_matricula WHERE id_matricula = 1;
        RAISE EXCEPTION 'FALHA: secretaria apagou matrícula';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK  secretaria NÃO apaga matrículas (cancela por status)';
    END;

    ---------------- COORDENAÇÃO ----------------
    BEGIN
        SET LOCAL ROLE coordenacao;
        SELECT COUNT(*) INTO v_n FROM tb_historico;
        IF v_n <> v_total_hist THEN RAISE EXCEPTION 'FALHA: coordenação vê % de % linhas', v_n, v_total_hist; END IF;
        PERFORM 1 FROM mv_indicadores_disciplina;
        RAISE NOTICE 'OK  coordenacao lê todo o histórico (% linhas) e os indicadores', v_n;
    END;

    BEGIN
        SET LOCAL ROLE coordenacao;
        UPDATE tb_historico SET nota_a1 = 10 WHERE id_historico = 1;
        RAISE EXCEPTION 'FALHA: coordenação alterou notas';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK  coordenacao NÃO altera notas (somente leitura)';
    END;

    BEGIN
        SET LOCAL ROLE coordenacao;
        INSERT INTO tb_campus (nome_campus, cidade) VALUES ('Intruso', 'X');
        RAISE EXCEPTION 'FALHA: coordenação inseriu dados';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK  coordenacao NÃO insere dados (somente leitura)';
    END;

    -- Papel sem relação alguma com os três: não pode nada
    BEGIN
        SET LOCAL ROLE aluno;           -- o papel de grupo, sem id: fn_id_aluno_logado() é NULL
        SELECT COUNT(*) INTO v_n FROM tb_historico;
        IF v_n <> 0 THEN RAISE EXCEPTION 'FALHA: papel "aluno" sem id enxerga % linhas', v_n; END IF;
        RAISE NOTICE 'OK  papel de grupo "aluno" (sem id de aluno) não enxerga nenhuma linha';
    END;

    RESET ROLE;     -- SET LOCAL ROLE dura até o fim da transação; no pgAdmin o arquivo todo é UMA transação
    RAISE NOTICE 'TODOS OS TESTES DE SEGURANÇA PASSARAM';
END $$;

-- A secretaria usa a função segura de matrícula (06b) sem ganhar acesso extra.
DO $$
DECLARE
    v_res text;
BEGIN
    IF to_regprocedure('academico.sp_matricular_bloqueio(integer,integer,numeric)') IS NULL THEN
        RAISE NOTICE 'sp_matricular_bloqueio não existe (rode o 06b); teste ignorado';
        RETURN;
    END IF;

    BEGIN
        SET LOCAL ROLE aluno_91;
        PERFORM sp_matricular_bloqueio(91, 1);
        RAISE EXCEPTION 'FALHA: aluno executou a função de matrícula';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'OK  aluno NÃO executa a função de matrícula (permission denied)';
    END;

    SET LOCAL ROLE secretaria;
    v_res := sp_matricular_bloqueio(91, 1);
    RESET ROLE;
    IF v_res <> 'MATRICULADO' THEN RAISE EXCEPTION 'FALHA: matrícula pela secretaria retornou %', v_res; END IF;
    RAISE NOTICE 'OK  secretaria matricula o aluno 91 na turma 1 pela função segura (%)', v_res;
    PERFORM sp_limpar_disputa();        -- desfaz o teste: devolve a turma ao estado original
END $$;

-- Resumo (última consulta): as policies de RLS criadas
SELECT tablename AS tabela, policyname AS policy, roles, cmd AS comando
FROM pg_policies
WHERE schemaname = 'academico'
ORDER BY tablename, policyname;
