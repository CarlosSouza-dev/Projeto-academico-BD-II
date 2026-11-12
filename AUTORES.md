# Autores e Responsabilidades - Projeto Banco de Dados II (2026/2)

Este repositório contém o Projeto Acadêmico da disciplina de Banco de Dados II, referente ao Sistema de Matrícula Acadêmica do IESB.

O grupo é composto por 3 integrantes, e a divisão de responsabilidades técnicas obrigatórias foi definida da seguinte forma:

## 1. Responsável pela Modelagem Física e Desempenho
**Nome:** Carlos Eduardo Ferreira de Souza.  
**Matrícula:** 2512130043  
**Frente:** Implementação do DDL completo (tabelas, tipos, domínios e restrições), criação dos índices (incluindo índice parcial) e comprovação de ganho de desempenho via `EXPLAIN (ANALYZE, BUFFERS)`.  
**Arquivos:** `01_ddl_inicial.sql`, `02_dml_carga.sql`, `03_dql_consultas.sql`, `05_indices.sql`, `05b_evidencias_explain.sql`, `evidencias_explain.txt` e o bônus `09_bonus_jsonb_gin.sql`.

## 2. Responsável por Transações e Concorrência
**Nome:** Ana Luiza  
**Matrícula:** [Matrícula]  
**Frente:** Reprodução da anomalia de concorrência (disputa pela última vaga) e implementação de correções via bloqueio explícito e nível de isolamento, com comparação de custo, contenção e retentativa.  
**Arquivos:** `06_anomalia_vagas.sql`, `06b_correcao_bloqueio.sql`, `06c_correcao_isolamento.sql` e `docs/comparacao_concorrencia.md`.

## 3. Responsável por Administração e Operação
**Nome:** Lucas Pessoa Ranieri.  
**Matrícula:** 2512130092  
**Frente:** Criação de views e materialized view com política de atualização, configuração de papéis de acesso (roles) com `GRANT`/`REVOKE`, implementação de Row-Level Security (RLS) e procedimentos de backup e restauração.  
**Arquivos:** `04_views.sql`, `07_seguranca.sql`, `08_verificacao_backup.sql` e `docs/backup_restauracao.md`.
