# Sistema de Matrícula Acadêmica - IESB

Projeto desenvolvido para a disciplina de Banco de Dados II (CCO072) - Semestre 2026/2. O objetivo deste projeto é implementar um banco de dados funcional para um sistema de matrícula, garantindo integridade, controle de concorrência, desempenho e segurança.

## Pré-requisitos
* [Docker](https://www.docker.com/) instalado.
* Cliente SQL (ex: DBeaver, pgAdmin ou psql).

## Como executar o projeto do zero

O ambiente oficial deste projeto utiliza a imagem do **PostgreSQL 17** pré-configurada via Docker Compose. Siga os passos abaixo para inicializar o banco de dados e aplicar os scripts.

### Passo 1: Subir o ambiente com Docker Compose
O ambiente já foi previamente configurado pelo professor no arquivo `docker-compose.yml`. Para iniciar o banco de dados:

1. Abra o Prompt de Comando (CMD) ou o terminal da sua máquina.
2. Navegue até a pasta `ambiente_aluno` onde o arquivo `.yml` está localizado[cite: 3], usando o comando `cd` e o caminho entre aspas. Exemplo:
   `cd "C:\caminho\para\a\pasta\ambiente_aluno"`
3. Execute o comando para subir o contêiner em segundo plano:
   `docker compose up -d`

### Passo 2: Ordem de Execução dos Scripts
Conecte-se ao banco utilizando as credenciais definidas no ambiente oficial e execute os scripts SQL localizados na raiz deste repositório, **estritamente na ordem numérica abaixo**:

1. **01_ddl_estruturas.sql**: Criação de tipos, domínios e tabelas independentes (Marco 1).
2. **02_ddl_tabelas_dependentes.sql**: Criação das tabelas com chaves estrangeiras e regras de integridade (Marco 1).
3. **03_carga_dados.sql**: Inserção de dados iniciais, alunos, turmas e matrículas (Marco 1).
4. **04_consultas.sql**: As 10 consultas exigidas no projeto (Marco 1).
5. **05_views_seguranca.sql**: Criação de views, materialized views, roles e RLS (Marco 2).
6. **06_indices.sql**: Criação dos índices de otimização (Marco 2).
7. **07_concorrencia.sql**: Script de simulação e correção da anomalia de transação (Marco 2).

### Passo 3: Backup e Restauração
*As instruções e o comando exato de dump e restore serão documentados aqui pela Frente 3 (Administração e Operação) para a entrega do Marco 2.*

## Avaliação de Desempenho
As comprovações de ganho de desempenho utilizando o EXPLAIN (ANALYZE, BUFFERS) serão salvas no arquivo `evidencias_explain.txt`.
