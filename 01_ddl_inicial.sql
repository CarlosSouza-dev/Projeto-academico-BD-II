-----------------------------------------------------------------
-- 01_ddl_inicial.sql
-- Sistema de Matrícula Acadêmica (IESB) - Banco de Dados II 2026/2
-- Cria o schema, os tipos (ENUM), os domínios e TODAS as tabelas.
-- Nomes das tabelas e colunas seguem o diagrama oficial (prefixo tb_).
-----------------------------------------------------------------
DROP SCHEMA IF EXISTS academico CASCADE;
CREATE SCHEMA academico;
SET search_path TO academico;

-----------------------------------------------------------------
-- 1. Tipos (ENUM) e domínios (DOMAIN)
-----------------------------------------------------------------
CREATE TYPE turno_t AS ENUM ('Matutino', 'Vespertino', 'Noturno');

CREATE TYPE tipo_sala_t AS ENUM ('TEORICA', 'LABORATORIO', 'AUDITORIO', 'HIBRIDA');

CREATE TYPE status_mat_t AS ENUM ('Ativa', 'Trancada', 'Concluida', 'Cancelada');

CREATE TYPE vinculo_t AS ENUM ('OBRIGATORIA', 'OPTATIVA');

CREATE TYPE situacao_t AS ENUM ('Cursando', 'Aprovado', 'Reprovado por Nota', 'Reprovado por Falta');

CREATE DOMAIN nota_t AS numeric(4,2) CHECK (VALUE >= 0.00 AND VALUE <= 10.00);

CREATE DOMAIN pct_t AS numeric(5,2) CHECK (VALUE >= 0.00 AND VALUE <= 100.00);

-----------------------------------------------------------------
-- 2. Tabelas independentes (Nível 0)
-----------------------------------------------------------------

CREATE TABLE tb_campus (
    id_campus int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome_campus varchar(120) UNIQUE NOT NULL,
    cidade varchar(120) NOT NULL
);

CREATE TABLE tb_professor (
    id_professor int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    matricula_professor varchar(20) UNIQUE NOT NULL,
    nome_professor varchar(120) NOT NULL,
    email_professor varchar(120) UNIQUE NOT NULL,
    titulacao varchar(120)
);

CREATE TABLE tb_disciplina (
    id_disciplina int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo varchar(20) UNIQUE NOT NULL,
    nome varchar(120) UNIQUE NOT NULL,
    ch_teorico smallint NOT NULL DEFAULT 0 CHECK (ch_teorico >= 0),
    ch_pratica smallint NOT NULL DEFAULT 0 CHECK (ch_pratica >= 0),
    -- Coluna gerada
    ch_total_disciplina smallint GENERATED ALWAYS AS (ch_teorico + ch_pratica) STORED,
    ementa text
);

CREATE TABLE tb_periodo_letivo (
    id_periodo_letivo int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ano smallint NOT NULL,
    semestre smallint NOT NULL CHECK (semestre IN (1, 2)),
    data_inicio date NOT NULL,
    data_fim date NOT NULL,
    UNIQUE (ano, semestre),
    CHECK (data_fim > data_inicio)
);

-----------------------------------------------------------------
-- 3. Tabelas dependentes
-----------------------------------------------------------------

-- Nível 1

CREATE TABLE tb_curso (
    id_curso int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_campus int NOT NULL REFERENCES tb_campus(id_campus),
    ch_total_curso int NOT NULL CHECK (ch_total_curso > 0),
    codigo varchar(120) UNIQUE NOT NULL,
    nome_curso varchar(120) NOT NULL,
    grau varchar(50) NOT NULL
);

CREATE TABLE tb_feriado (
    id_feriado int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_campus int NOT NULL REFERENCES tb_campus(id_campus),
    descricao varchar(120) NOT NULL,
    data date NOT NULL
);

CREATE TABLE tb_sala (
    id_sala int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_campus int NOT NULL REFERENCES tb_campus(id_campus),
    codigo varchar(20) NOT NULL,
    capacidade smallint NOT NULL CHECK (capacidade > 0),
    tipo tipo_sala_t NOT NULL,
    UNIQUE (id_campus, codigo)
);

CREATE TABLE tb_turma (
    id_turma int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_disciplina int NOT NULL REFERENCES tb_disciplina(id_disciplina),
    id_periodo_letivo int NOT NULL REFERENCES tb_periodo_letivo(id_periodo_letivo),
    id_professor int NOT NULL REFERENCES tb_professor(id_professor),
    codigo varchar(20) NOT NULL,
    turno turno_t NOT NULL,
    vagas smallint NOT NULL CHECK (vagas >= 0),
    UNIQUE (codigo, id_disciplina, id_periodo_letivo)
);

-- Nível 2

CREATE TABLE tb_curriculo (
    id_curriculo int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_curso int NOT NULL REFERENCES tb_curso(id_curso),
    ano_vigente smallint NOT NULL,
    ativo_curriculo boolean NOT NULL DEFAULT true,
    UNIQUE (id_curso, ano_vigente)
);

CREATE TABLE tb_turma_horario (
    id_turma_horario int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_turma int NOT NULL REFERENCES tb_turma(id_turma),
    id_sala int NOT NULL REFERENCES tb_sala(id_sala),
    faixa varchar(20) NOT NULL,
    dia_semana smallint NOT NULL CHECK (dia_semana BETWEEN 1 AND 7)
);

-- Nível 3

CREATE TABLE tb_aluno (
    id_aluno int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_curriculo int NOT NULL REFERENCES tb_curriculo(id_curriculo),
    cpf char(11) UNIQUE NOT NULL CHECK (cpf ~ '^[0-9]{11}$'),
    nome_aluno varchar(120) NOT NULL,
    email_aluno varchar(120) UNIQUE NOT NULL,
    nascimento date NOT NULL,
    ingresso_aluno smallint NOT NULL,
    ativo_aluno boolean NOT NULL DEFAULT true
);

CREATE TABLE tb_curriculo_disciplina (
    id_curriculo int NOT NULL REFERENCES tb_curriculo(id_curriculo),
    id_disciplina int NOT NULL REFERENCES tb_disciplina(id_disciplina),
    periodo smallint NOT NULL CHECK (periodo > 0),
    tipo vinculo_t NOT NULL,
    PRIMARY KEY (id_curriculo, id_disciplina)
);

CREATE TABLE tb_pre_requisito (
    id_requisito int NOT NULL REFERENCES tb_disciplina(id_disciplina),
    id_disciplina int NOT NULL REFERENCES tb_disciplina(id_disciplina),
    vinculo vinculo_t NOT NULL,
    PRIMARY KEY (id_requisito, id_disciplina),
    CHECK (id_requisito <> id_disciplina)   -- disciplina não pode ser pré-requisito de si mesma
);

-- Nível 4

CREATE TABLE tb_matricula (
    id_matricula int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_aluno int NOT NULL REFERENCES tb_aluno(id_aluno),
    id_turma int NOT NULL REFERENCES tb_turma(id_turma),
    data_matricula date NOT NULL DEFAULT CURRENT_DATE,
    status_matricula status_mat_t NOT NULL,
    UNIQUE (id_turma, id_aluno)
);

-- Nível 5

CREATE TABLE tb_historico (
    id_historico int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_matricula int UNIQUE NOT NULL REFERENCES tb_matricula(id_matricula),
    nota_a1 nota_t,
    nota_a2 nota_t,
    nota_p3 nota_t,
    frequencia pct_t,
    situacao situacao_t,
    -- Coluna gerada: a P3 substitui a menor entre A1 e A2 (vale o melhor resultado)
    media_geral nota_t GENERATED ALWAYS AS (
        GREATEST(
            COALESCE((nota_a1 * 0.4) + (nota_a2 * 0.6), 0),
            COALESCE((nota_a1 * 0.4) + (nota_p3 * 0.6), 0),
            COALESCE((nota_p3 * 0.4) + (nota_a2 * 0.6), 0)
        )
    ) STORED
);

CREATE TABLE tb_log_matricula (
    id_log_matricula int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_matricula int NOT NULL REFERENCES tb_matricula(id_matricula),
    acao varchar(50) NOT NULL,
    usuario varchar(120) NOT NULL,
    ocorrido_em timestamp NOT NULL DEFAULT current_timestamp,
    detalhe text
);