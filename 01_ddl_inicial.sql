-- 1. Criação de tipos (ENUM) e domínios (DOMAIN)
CREATE TYPE turno_t as ENUM ('Matutino', 'Vespertino', 'Noturno');

CREATE TYPE tipo_sala_t as ENUM ('Teorica', 'Laboratorio', 'Auditorio', 'Hibrida');

CREATE TYPE status_mat_t as ENUM ('Ativa', 'Trancada', 'Concluida', 'Cancelada');

CREATE TYPE vinculo_t as ENUM ('Obrigatoria', 'Optativa');

CREATE TYPE situacao_t as ENUM ('Cursando', 'Aprovado', 'Reprovado por Nota', 'Reprovado por Falta');

CREATE DOMAIN nota_t as numeric(4,2) check (value >= 0.00 and value <=10.00);

CREATE DOMAIN pct_t as numeric(5,2) check (value >= 0.00 and value <=100.00);

-- 2. Tabelas independentes

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