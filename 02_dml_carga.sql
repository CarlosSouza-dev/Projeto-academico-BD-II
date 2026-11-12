-----------------------------------------------------------------
-- 02_dml_carga.sql
-- Carga de dados (>= 100 alunos, >= 6 turmas, >= 300 matrículas)
-- Rode APÓS o 01_ddl_inicial.sql.
--
-- Os ids não são informados: o IDENTITY gera 1, 2, 3... na ordem dos
-- INSERTs. Como o 01 recria o schema do zero, os ids são sempre os mesmos,
-- e é neles que as chaves estrangeiras abaixo se apoiam.
-----------------------------------------------------------------
SET search_path TO academico;

-- Semente fixa: as notas sorteadas com random() saem iguais em toda carga
SELECT setseed(0.42);

-----------------------------------------------------------------
-- Campus (ids 1 e 2)
-----------------------------------------------------------------
INSERT INTO tb_campus (nome_campus, cidade) VALUES
    ('Asa Sul',   'Brasília'),
    ('Ceilândia', 'Brasília');

-----------------------------------------------------------------
-- Curso (ids 1 a 3)
-----------------------------------------------------------------
INSERT INTO tb_curso (codigo, nome_curso, grau, ch_total_curso, id_campus) VALUES
    ('CCO',  'Ciência da Computação',                 'BACHARELADO', 3200, 1),
    ('ENGC', 'Engenharia de Computação',              'BACHARELADO', 3600, 1),
    ('ADS',  'Análise e Desenvolvimento de Sistemas', 'TECNOLOGO',   2000, 1);

-----------------------------------------------------------------
-- Currículo (ids 1 a 4; o 2 é o currículo antigo/inativo de CCO)
-----------------------------------------------------------------
INSERT INTO tb_curriculo (id_curso, ano_vigente, ativo_curriculo) VALUES
    (1, 2026, true),
    (1, 2023, false),
    (2, 2026, true),
    (3, 2026, true);

-----------------------------------------------------------------
-- Aluno: 100 alunos gerados com generate_series.
-- O nome é montado com prenome + 2 sobrenomes, escolhidos de três listas
-- (ARRAY) pelo resto da divisão do número do aluno. As listas têm 20, 11 e
-- 13 nomes, então nenhum nome completo se repete entre os 100 alunos.
-- O e-mail vem do nome (sem acento) e o CPF é fictício: 11 dígitos únicos.
-- Os alunos vão só para os currículos ATIVOS (1, 3 e 4).
-----------------------------------------------------------------
INSERT INTO tb_aluno (nome_aluno, cpf, email_aluno, nascimento, id_curriculo, ingresso_aluno, ativo_aluno)
WITH nomes AS (
    SELECT
        ARRAY['Ana', 'Beatriz', 'Bruno', 'Camila', 'Carlos', 'Daniel', 'Eduardo', 'Fernanda',
              'Gabriel', 'Helena', 'Igor', 'Juliana', 'Larissa', 'Lucas', 'Mariana', 'Mateus',
              'Nicolas', 'Rafaela', 'Thiago', 'Vitória'] AS prenomes,                    -- 20
        ARRAY['Silva', 'Santos', 'Oliveira', 'Souza', 'Lima', 'Pereira', 'Costa',
              'Rodrigues', 'Almeida', 'Nascimento', 'Carvalho'] AS sobrenomes_a,         -- 11
        ARRAY['Ferreira', 'Ribeiro', 'Martins', 'Araújo', 'Barbosa', 'Gomes', 'Cavalcanti',
              'Moreira', 'Rocha', 'Dias', 'Teixeira', 'Machado', 'Monteiro'] AS sobrenomes_b  -- 13
)
SELECT
    n.prenomes[(g.i % 20) + 1] || ' ' ||
        n.sobrenomes_a[(g.i % 11) + 1] || ' ' ||
        n.sobrenomes_b[(g.i % 13) + 1],                                  -- nome completo
    (52000000000 + g.i * 7919)::text,                                    -- CPF fictício (11 dígitos)
    lower(replace(n.prenomes[(g.i % 20) + 1], 'ó', 'o') || '.' || n.sobrenomes_a[(g.i % 11) + 1])
        || '@iesb.edu.br',                                               -- e-mail sem acento
    DATE '1998-01-01' + ((g.i * 83) % 3300),                             -- nascimentos entre 1998 e 2007
    (ARRAY[1, 3, 4])[(g.i % 3) + 1],                                     -- currículos ativos
    2026,                                                                -- ano de ingresso
    true                                                                 -- aluno ativo
FROM generate_series(1, 100) AS g(i)
CROSS JOIN nomes n
ORDER BY g.i;                                                            -- id_aluno 1..100 na ordem de geração

-----------------------------------------------------------------
-- Disciplina (ids 1 a 7)
-----------------------------------------------------------------
INSERT INTO tb_disciplina (codigo, nome, ch_teorico, ch_pratica, ementa) VALUES
    ('HMDC253', 'Banco de Dados I',                           30, 30, 'Modelagem conceitual, modelo relacional, álgebra relacional, normalização e SQL.'),
    ('CCO072',  'Banco de Dados II',                          30, 30, 'Arquitetura de SGBD, transações, controle de concorrência, recuperação, segurança, otimização de consultas e bancos distribuídos.'),
    ('CCO085',  'Programação Paralela',                       45, 15, 'Concorrência, paralelismo, memória compartilhada e distribuída.'),
    ('MDC050',  'Inteligência Artificial',                    45, 15, 'Busca, representação do conhecimento e aprendizado de máquina.'),
    ('ADS033',  'Aprendizagem de Máquina',                    30, 30, 'Aprendizado supervisionado e não supervisionado, avaliação de modelos.'),
    ('MDC118',  'Algoritmos e Programação de Computadores I', 30, 30, 'Lógica de programação e estruturas básicas.'),
    ('MDC122',  'Sistemas Operacionais',                      45, 15, 'Processos, escalonamento, memória e sistemas de arquivos.');

-----------------------------------------------------------------
-- Currículo x Disciplina
-----------------------------------------------------------------
INSERT INTO tb_curriculo_disciplina (id_curriculo, id_disciplina, periodo, tipo) VALUES
    (1, 1, 2, 'OBRIGATORIA'),
    (1, 2, 4, 'OBRIGATORIA'),
    (1, 3, 6, 'OBRIGATORIA'),
    (1, 4, 4, 'OBRIGATORIA'),
    (1, 6, 1, 'OBRIGATORIA'),
    (1, 7, 4, 'OBRIGATORIA'),
    (4, 5, 5, 'OBRIGATORIA');

-----------------------------------------------------------------
-- Feriado
-----------------------------------------------------------------
INSERT INTO tb_feriado (data, descricao, id_campus) VALUES
    ('2026-09-07', 'Independência do Brasil', 1),
    ('2026-10-12', 'Nossa Senhora Aparecida', 1),
    ('2026-10-13', 'Recesso Antecipado do Dia do Professor', 1),
    ('2026-11-02', 'Finados', 1),
    ('2026-11-15', 'Proclamação da República', 1),
    ('2026-11-20', 'Dia da Consciência Negra', 1),
    ('2026-11-30', 'Dia do Evangélico', 1),
    ('2026-12-25', 'Natal', 1);

-----------------------------------------------------------------
-- Período letivo (id 1 = 2026/2, o vigente; id 2 = 2026/1)
-----------------------------------------------------------------
INSERT INTO tb_periodo_letivo (ano, semestre, data_inicio, data_fim) VALUES
    (2026, 2, '2026-08-03', '2026-12-12'),
    (2026, 1, '2026-02-02', '2026-06-20');

-----------------------------------------------------------------
-- Professor (ids 1 a 3)
-----------------------------------------------------------------
INSERT INTO tb_professor (matricula_professor, nome_professor, email_professor, titulacao) VALUES
    ('201680', 'Rodrigo Gonçalves Pinto', 'rodrigo.pinto@iesb.edu.br', 'MESTRE'),
    ('201455', 'Marcelo Paiva',           'marcelo.paiva@iesb.edu.br', 'DOUTOR'),
    ('201322', 'Roger Santos',            'roger.santos@iesb.edu.br',  'MESTRE');

-----------------------------------------------------------------
-- Turma: 6 turmas em 2026/2 (ids 1 a 6)
-- O código identifica a turma do curso (CCODM2B = matutino, CCONM2B = noturno);
-- o mesmo código se repete entre disciplinas, o que o
-- UNIQUE (codigo, id_disciplina, id_periodo_letivo) permite.
-- Turmas 2 e 4 têm aula às 19h15 (ver tb_turma_horario), logo são Noturno.
-- vagas = 51: com 50 matrículas por turma sobra exatamente 1 vaga livre,
-- o cenário da disputa pela "última vaga" (06_anomalia_vagas.sql).
-----------------------------------------------------------------
INSERT INTO tb_turma (codigo, id_disciplina, id_periodo_letivo, id_professor, turno, vagas)
SELECT
    CASE WHEN i IN (2, 4) THEN 'CCONM2B' ELSE 'CCODM2B' END, -- código da turma
    (i % 7) + 1,                                             -- disciplinas 2..7 (a 1 fica sem turma neste período)
    1,                                                       -- todas no período letivo 1 (2026/2)
    (i % 3) + 1,                                             -- distribui entre os 3 professores
    (CASE WHEN i IN (2, 4) THEN 'Noturno' ELSE 'Matutino' END)::turno_t,
    51
FROM generate_series(1, 6) AS i;

-----------------------------------------------------------------
-- Matrícula + Histórico: 300 matrículas
-- Alunos 1..90 cursam 3 turmas; alunos 1..30 cursam uma 4ª (90*3 + 30 = 300).
-- Cada turma recebe exatamente 50 matrículas (não estoura as 51 vagas).
-- Alunos 91..100 ficam sem matrícula (alimentam a consulta 4 e a disputa do 06).
-----------------------------------------------------------------
INSERT INTO tb_matricula (id_aluno, id_turma, status_matricula)
SELECT a.id_aluno,
       ((a.id_aluno + k) % 6) + 1,                    -- turma 1..6
       'Ativa'
FROM tb_aluno a
CROSS JOIN generate_series(0, 3) AS k                 -- até 4 turmas por aluno
WHERE a.id_aluno <= 90
  AND (k < 3 OR a.id_aluno <= 30)                     -- a 4ª turma só para os alunos 1..30
ORDER BY a.id_aluno, k;

-- Um histórico por matrícula (notas sorteadas; todos ainda "Cursando")
INSERT INTO tb_historico (id_matricula, nota_a1, nota_a2, frequencia, situacao)
SELECT id_matricula,
       ROUND((random() * 10)::numeric, 2),
       ROUND((random() * 10)::numeric, 2),
       ROUND((75 + random() * 25)::numeric, 2),
       'Cursando'
FROM tb_matricula
ORDER BY id_matricula;

-- tb_log_matricula começa vazia (é preenchida pela trigger do 09)

-----------------------------------------------------------------
-- Pré-requisito: (id_disciplina) exige (id_requisito)
-----------------------------------------------------------------
INSERT INTO tb_pre_requisito (id_disciplina, id_requisito, vinculo) VALUES
    (1, 6, 'OBRIGATORIA'),    -- BD I exige APC I
    (2, 1, 'OBRIGATORIA'),    -- BD II exige BD I
    (3, 6, 'OBRIGATORIA'),    -- Prog. Paralela exige APC I
    (3, 7, 'OBRIGATORIA'),    -- Prog. Paralela exige Sistemas Operacionais
    (4, 6, 'OBRIGATORIA');    -- IA exige APC I

-----------------------------------------------------------------
-- Sala (ids 1 a 6)
-----------------------------------------------------------------
INSERT INTO tb_sala (id_campus, codigo, capacidade, tipo) VALUES
    (1, 'JB1',   55, 'LABORATORIO'),
    (1, 'JB2/4', 36, 'LABORATORIO'),
    (1, 'JB5',   44, 'LABORATORIO'),
    (1, 'IA2',   24, 'LABORATORIO'),
    (1, 'IA3',   30, 'LABORATORIO'),
    (1, 'JA2',   32, 'TEORICA');

-----------------------------------------------------------------
-- Horário das turmas (dia_semana: 1 = domingo ... 7 = sábado)
-----------------------------------------------------------------
INSERT INTO tb_turma_horario (id_turma, id_sala, dia_semana, faixa) VALUES
    (1, 1, 2, '08:15-11:00'),
    (2, 4, 2, '19:15-22:00'),
    (3, 5, 5, '08:15-11:00'),
    (4, 5, 5, '19:15-22:00'),
    (5, 2, 4, '08:15-11:00'),
    (6, 2, 6, '08:15-11:00');

-----------------------------------------------------------------
-- Conferência dos mínimos exigidos (100 alunos, 6 turmas, 300 matrículas)
-----------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM tb_aluno)     AS alunos,
    (SELECT COUNT(*) FROM tb_turma)     AS turmas,
    (SELECT COUNT(*) FROM tb_matricula) AS matriculas,
    (SELECT COUNT(*) FROM tb_historico) AS historicos;
