-----------------------------------------------------------------
-- 1. Criação de tipos (ENUM) e domínios (DOMAIN)
-----------------------------------------------------------------

CREATE TYPE turno_t as ENUM ('Matutino', 'Vespertino', 'Noturno');

CREATE TYPE tipo_sala_t as ENUM ('Teorica', 'Laboratorio', 'Auditorio', 'Hibrida');

CREATE TYPE status_mat_t as ENUM ('Ativa', 'Trancada', 'Concluida', 'Cancelada');

CREATE TYPE vinculo_t as ENUM ('Obrigatoria', 'Optativa');

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
    dat_a date NOT NULL,
    descricao varchar(120) NOT NULL,
    campus_id int NOT NULL REFERENCES campus(id_campus)
);

CREATE TABLE sala (
    id_sala INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    campus_id int NOT NULL REFERENCES campus(id_campus)
    codigo varchar(20) NOT NULL,
    capacidade smallint NOT NULL CHECK (capacidade > 0),
    tipo tipo_sala_t NOT NULL,
    UNIQUE (campus_id, codigo)
);

CREATE TABLE turma (
    id_turma INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo varchar(20) NOT NULL,
    disciplina_id int NOT NULL REFERENCES disciplina(id_disciplina), --
    periodo_letivo_id int NOT NULL REFERENCES periodo_letivo(id_periodo_letivo),
    professor_id int NOT NULL REFERENCES professor(id_professor),
    turno turno_t NOT NULL,
    vagas smallint NOT NULL (vagas >= 0),
    UNIQUE (codigo, disciplina_id, periodo_letivo_id)
);

-- Nível 2

CREATE TABLE curriculo (
    id_curriculo INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    curso_id int NOT NULL REFERENCES curso(id_curso)
    ano_vigencia smallint NOT NULL,
    ativo_curriculo boolean NOT NULL DEFAUT true,
    UNIQUE (curso_id, ano_vigencia)
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

CREATE TABLE 

