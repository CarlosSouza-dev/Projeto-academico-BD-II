-----------------------------------------------------------------
-- 1. Criação de tipos (ENUM) e domínios (DOMAIN)
-----------------------------------------------------------------
DROP SCHEMA IF EXISTS academico CASCADE;
CREATE SCHEMA academico;
SET search_path TO academico;

-- Aqui começam os seus comandos CREATE TYPE...
CREATE TYPE turno_t as ENUM ('Matutino', 'Vespertino', 'Noturno');

CREATE TYPE tipo_sala_t as ENUM ('TEORICA', 'LABORATORIO', 'AUDITORIO', 'HIBRIDA');

CREATE TYPE status_mat_t as ENUM ('Ativa', 'Trancada', 'Concluida', 'Cancelada');

CREATE TYPE vinculo_t as ENUM ('OBRIGATORIA', 'OPTATIVA');

CREATE TYPE situacao_t as ENUM ('Cursando', 'Aprovado', 'Reprovado por Nota', 'Reprovado por Falta');

CREATE DOMAIN nota_t as numeric(4,2) check (value >= 0.00 and value <=10.00);

CREATE DOMAIN pct_t as numeric(5,2) check (value >= 0.00 and value <=100.00);

-----------------------------
-- 1.2. Tabelas independentes
-----------------------------

-- Nível 0

CREATE TABLE campus (
    id_campus int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome_campus varchar(120) UNIQUE NOT NULL,
    cidade varchar(120) NOT NULL
);

CREATE TABLE professor (
    id_professor int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    matricula_professor char(20) UNIQUE NOT NULL,
    nome_professor varchar(120) NOT NULL,
    email_professor varchar(120) NOT NULL,
    titulacao varchar(120)
);

CREATE TABLE disciplina (
    id_disciplina int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo varchar(20) UNIQUE NOT NULL,
    nome varchar(120) UNIQUE NOT NULL,
    ch_teorico smallint NOT NULL DEFAULT 0,
    ch_pratica smallint NOT NULL DEFAULT 0,
    -- Coluna gerada
    ch_total_disciplina smallint GENERATED ALWAYS AS (ch_teorico + ch_pratica) STORED,
    ementa text
);

CREATE TABLE periodo_letivo (
    id_periodo_letivo INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ano smallint NOT NULL,
    semestre smallint NOT NULL,
    data_inicio date NOT NULL,
    data_fim date NOT NULL,
    UNIQUE (ano, semestre)
);

-----------------------------------------------------------------
-- 2. Tabelas Dependentes
-----------------------------------------------------------------

-- Nível 1

CREATE TABLE curso (
    id_curso INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo varchar(20) UNIQUE NOT NULL,
    nome_curso varchar(120) NOT NULL,
    grau varchar(50) NOT NULL,
    ch_total_curso int NOT NULL,
    campus_id int NOT NULL REFERENCES campus(id_campus)
);

CREATE TABLE feriado (
    id_feriado INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    data_feriado date NOT NULL,
    descricao varchar(120) NOT NULL,
    campus_id int NOT NULL REFERENCES campus(id_campus)
);

CREATE TABLE sala (
    id_sala INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    campus_id int NOT NULL REFERENCES campus(id_campus),
    codigo varchar(20) NOT NULL,
    capacidade smallint NOT NULL CHECK (capacidade > 0),
    tipo tipo_sala_t NOT NULL,
    UNIQUE (campus_id, codigo)
);

CREATE TABLE turma (
    id_turma INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo varchar(20) NOT NULL,
    disciplina_id int NOT NULL REFERENCES disciplina(id_disciplina),
    periodo_letivo_id int NOT NULL REFERENCES periodo_letivo(id_periodo_letivo),
    professor_id int NOT NULL REFERENCES professor(id_professor),
    turno turno_t NOT NULL,
    vagas smallint NOT NULL CHECK (vagas >= 0),
    UNIQUE (codigo, disciplina_id, periodo_letivo_id)
);

-- Nível 2

CREATE TABLE curriculo (
    id_curriculo INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    curso_id int NOT NULL REFERENCES curso(id_curso),
    ano_vigencia smallint NOT NULL,
    ativo_curriculo boolean NOT NULL DEFAULT true,
    UNIQUE (curso_id, ano_vigencia)
);

CREATE TABLE turma_horario (
    id_turma_horario INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    turma_id int NOT NULL REFERENCES turma(id_turma),
    sala_id int NOT NULL REFERENCES sala(id_sala),
    dia_semana smallint NOT NULL CHECK (dia_semana BETWEEN 1 AND 7),
    faixa varchar(20) NOT NULL
);

-- Nível 3

CREATE TABLE aluno (
    id_aluno INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome_aluno varchar(120) NOT NULL,
    cpf char(11) UNIQUE NOT NULL,
    email_aluno varchar(120) UNIQUE NOT NULL,
    nascimento date NOT NULL,
    curriculo_id int NOT NULL REFERENCES curriculo(id_curriculo),
    ingresso_aluno smallint NOT NULL,
    ativo_aluno boolean NOT NULL DEFAULT true
);

CREATE TABLE curriculo_disciplina (
    curriculo_id int NOT NULL REFERENCES curriculo(id_curriculo),
    disciplina_id int NOT NULL REFERENCES disciplina(id_disciplina),
    periodo smallint NOT NULL,
    tipo vinculo_t NOT NULL,
    PRIMARY KEY (curriculo_id, disciplina_id)
);

CREATE TABLE pre_requisito (
    requisito_id int NOT NULL REFERENCES disciplina(id_disciplina),
    disciplina_id int NOT NULL REFERENCES disciplina(id_disciplina),
    vinculo vinculo_t NOT NULL,
    PRIMARY KEY (requisito_id, disciplina_id)
);

--Nível 4

CREATE TABLE matricula (
    id_matricula INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    aluno_id int NOT NULL REFERENCES aluno(id_aluno),
    turma_id int NOT NULL REFERENCES turma(id_turma),
    data_matricula date NOT NULL DEFAULT current_timestamp,
    status_matricula status_mat_t NOT NULL,
    UNIQUE (turma_id, aluno_id)
);

CREATE TABLE historico (
    id_historico INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    matricula_id int UNIQUE NOT NULL REFERENCES matricula(id_matricula),
    nota_a1 nota_t,
    nota_a2 nota_t,
    nota_p3 nota_t,
    frequencia pct_t,
    situacao situacao_t,
    media_final nota_t GENERATED ALWAYS AS (
        GREATEST(
            COALESCE((nota_a1 * 0.4) + (nota_a2 * 0.6), 0),
            COALESCE((nota_a1 * 0.4) + (nota_p3 * 0.6), 0),
            COALESCE((nota_p3 * 0.4) + (nota_a2 * 0.6), 0)
        )
    ) STORED
);

CREATE TABLE log_matricula (
    id_log_matricula INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    matricula_id int NOT NULL REFERENCES matricula(id_matricula),
    acao varchar(50) NOT NULL,
    ocorrido_em timestamp NOT NULL DEFAULT current_timestamp,
    usuario varchar(120) NOT NULL,
    detalhe text
);