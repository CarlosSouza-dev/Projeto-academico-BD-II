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
2. Navegue até a pasta `ambiente_aluno` onde o arquivo `.yml` está localizado, usando o comando `cd` e o caminho entre aspas. Exemplo:
   `cd "C:\caminho\para\a\pasta\ambiente_aluno"`
3. Execute o comando para subir o contêiner em segundo plano:
   `docker compose up -d`

### Passo 2: Ordem de Execução dos Scripts
Conecte-se ao banco utilizando as credenciais definidas no ambiente oficial e execute os scripts SQL localizados na raiz deste repositório, **estritamente na ordem numérica abaixo** (todos os arquivos estão em UTF-8):

1. **01_ddl_inicial.sql**: recria o schema `academico` do zero e cria tipos (ENUM), domínios e todas as tabelas (`tb_*`) com chaves e restrições de integridade (Marco 1).
2. **02_dml_carga.sql**: carga de dados — 100 alunos, 6 turmas e 300 matrículas, além de campus, cursos, currículos, disciplinas, pré-requisitos, salas e horários (Marco 1).
3. **03_dql_consultas.sql**: 10 consultas de complexidade crescente, incluindo junção externa, consultas recursivas e funções de janela (Marco 1).

> Atenção: o `01_ddl_inicial.sql` executa `DROP SCHEMA academico CASCADE`; rodá-lo apaga todos os dados existentes no schema.

### Passo 3: Backup e Restauração
*As instruções e o comando exato de dump e restore serão documentados aqui pela Frente 3 (Administração e Operação) para a entrega do Marco 2.*

## Avaliação de Desempenho
As comprovações de ganho de desempenho utilizando o EXPLAIN (ANALYZE, BUFFERS) serão salvas no arquivo `evidencias_explain.txt`.