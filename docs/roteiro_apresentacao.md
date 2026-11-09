# Roteiro para mostrar o projeto ao professor

Passo a passo para subir o ambiente, rodar os scripts e demonstrar cada requisito do PDF, com as
respostas para as perguntas mais prováveis. Tempo da demonstração completa: **~15 minutos**
(fora a preparação).

---

## 0. Antes de sair de casa (checklist)

- [ ] Docker Desktop instalado e abrindo sem erro.
- [ ] Pasta `ambiente_aluno` (do zip do professor) no notebook.
- [ ] Repositório atualizado: `git pull origin CARLOS`.
- [ ] Imagens já baixadas (sem internet o `docker compose up` falha na 1ª vez): rode `docker compose up -d` uma vez em casa.
- [ ] Ensaiar este roteiro inteiro pelo menos uma vez, cronometrando.
- [ ] Deixar abertos: o VS Code (ou Bloco de Notas) com a pasta do projeto e o navegador no GitHub da branch `CARLOS`.

---

## 1. Subir o ambiente (~2 min)

No Prompt de Comando (CMD), dentro da pasta `ambiente_aluno`:

```
docker compose up -d
docker compose ps
```

Os dois serviços (`postgres` e `pgadmin`) têm de aparecer como `running` / `healthy`.

**Começar do zero** (apaga o banco, útil se algo ficou estranho de um ensaio):

```
docker compose down -v
docker compose up -d
```

### Conectar o pgAdmin

1. Abra http://localhost:8080 e entre com `admin@iesb.br` / `admin`. (O pgAdmin demora ~30 s a mais que o banco para subir.)
2. Botão direito em **Servers > Register > Server...**
   - aba *General*: Name = `BD2`
   - aba *Connection*: Host = **`postgres`** (o nome do serviço, não `localhost`), Port = `5432`, Maintenance database = `matricula`, Username = `bd2`, Password = `bd2`, marque *Save password*.
3. Abra **Servers > BD2 > Databases > matricula** e clique em **Tools > Query Tool**.

### Como colocar o script no Query Tool

O pgAdmin roda **dentro do Docker**, então o botão *Open File* não enxerga as pastas do seu computador.
O jeito mais simples: abra o arquivo `.sql` no VS Code, **Ctrl+A, Ctrl+C**, e cole no Query Tool.
(Outra opção: no *Open File*, use o botão de **upload** para enviar o arquivo ao pgAdmin e depois abri-lo.)

**Regra do pgAdmin:** **F5** executa tudo o que está no editor ou **só o trecho selecionado**. Em
*Data Output* aparece o resultado da **última** consulta executada; os avisos (`NOTICE`) e erros ficam
em *Messages*.

---

## 2. Criar o banco (~3 min)

Cole e execute, um por vez, cada arquivo inteiro (F5), **nesta ordem**:

| # | Arquivo | O que conferir no fim |
|---|---|---|
| 1 | `01_ddl_inicial.sql` | "Query returned successfully" (o aviso *schema does not exist* na 1ª vez é normal) |
| 2 | `02_dml_carga.sql` | **100 alunos, 6 turmas, 300 matrículas, 300 históricos** |
| 3 | `03_dql_consultas.sql` | resultado da consulta 10 (LAG) |
| 4 | `04_views.sql` | `v_vagas`: 6 turmas com **50/51, COM VAGAS** |
| 5 | `05_indices.sql` | os 4 índices criados |
| 6 | `06_anomalia_vagas.sql` | turma 1: 50/51 |
| 7 | `06b_correcao_bloqueio.sql` | turma 1: 50/51 |
| 8 | `06c_correcao_isolamento.sql` | `read committed` |
| 9 | `07_seguranca.sql` | as 6 policies |
| 10 | `09_bonus_jsonb_gin.sql` | `detalhe` = `jsonb`, 1 trigger |

Fale enquanto roda: *"cada arquivo tem uma parte de criação, que roda com F5, e uma parte de
demonstração no fim, dentro de um comentário `/* ... */`, que eu executo selecionando o trecho."*

---

## 3. Demonstrações (o que o PDF exige na seção 6)

### 3.1 Restrições de integridade (~2 min) - `01_ddl_inicial.sql`

Mostre no arquivo: os **ENUM** (`turno_t`, `status_mat_t`), os **DOMAIN** (`nota_t` 0 a 10), as
**colunas geradas** (`ch_total_disciplina`, `media_geral`), os **CHECK**, **UNIQUE** e **FK**.
Depois prove ao vivo, num Query Tool, um de cada vez (todos dão **erro de propósito**):

```sql
SET search_path TO academico;

-- CHECK: semestre só pode ser 1 ou 2
INSERT INTO tb_periodo_letivo (ano, semestre, data_inicio, data_fim) VALUES (2027, 3, '2027-02-01', '2027-06-30');

-- DOMAIN: nota de 0 a 10
UPDATE tb_historico SET nota_a1 = 11 WHERE id_historico = 1;

-- UNIQUE: o aluno 1 já está na turma 1? (UNIQUE id_turma + id_aluno)
INSERT INTO tb_matricula (id_aluno, id_turma, status_matricula)
SELECT id_aluno, id_turma, 'Ativa' FROM tb_matricula WHERE id_matricula = 1;

-- FK: turma que não existe
INSERT INTO tb_matricula (id_aluno, id_turma, status_matricula) VALUES (91, 999, 'Ativa');

-- Coluna gerada: não aceita valor digitado
UPDATE tb_disciplina SET ch_total_disciplina = 100 WHERE id_disciplina = 1;

-- CHECK: disciplina não pode ser pré-requisito de si mesma
INSERT INTO tb_pre_requisito (id_disciplina, id_requisito, vinculo) VALUES (1, 1, 'OBRIGATORIA');
```

### 3.2 Consultas do Marco 1 (~1 min) - `03_dql_consultas.sql`

Selecione e rode a **consulta 7** (árvore de pré-requisitos, CTE recursiva: BD II exige BD I, que
exige APC I, nível 2) e a **consulta 9** (RANK e PERCENT_RANK por turma).

### 3.3 Views e materialized view (~1 min) - `04_views.sql`

```sql
SELECT * FROM academico.v_vagas;
SELECT * FROM academico.mv_indicadores_disciplina;
```

Explique a **política de atualização** (cabeçalho do item 4 do arquivo): REFRESH CONCURRENTLY diário
e após lançamento de notas; exige índice único.

### 3.4 Plano de execução com EXPLAIN ANALYZE (~2 min) - `05b_evidencias_explain.sql`

1. Cole o `05b` inteiro. Selecione da linha `SELECT version();` até os três `ANALYZE` (cria a massa
   de 500 mil linhas) e aperte F5.
2. Selecione o bloco do **ÍNDICE 2 (PARCIAL)**: o `EXPLAIN` do ANTES → F5 (mostra `Seq Scan`, ~7 ms);
   o `CREATE INDEX` + `ANALYZE` → F5; o `EXPLAIN` do DEPOIS → F5 (mostra `Bitmap Index Scan`, ~0,05 ms).
3. Rode a consulta de tamanho: índice parcial **392 kB** contra **5.720 kB** de um índice na tabela toda.
4. No fim, selecione as duas últimas linhas (`RESET search_path; DROP SCHEMA teste_desempenho CASCADE;`).

Se o professor quiser ver todos: o arquivo `evidencias_explain.txt` tem os 5 planos antes/depois.

### 3.5 Anomalia da última vaga e as duas correções (~4 min) - `06`, `06b`, `06c`

Abra **duas abas** do Query Tool (cada aba é uma sessão, como dois alunos). Nas duas, rode:

```sql
SET search_path TO academico;
```

**(a) A anomalia:**
- Aba A: `CALL sp_matricular_ingenuo(91, 1);`
- Aba B, em menos de 5 s: `CALL sp_matricular_ingenuo(92, 1);`
- Qualquer aba: `SELECT * FROM v_vagas WHERE id_turma = 1;` → **52/51, SUPERLOTADA**.
- Limpeza (rode sempre entre um teste e outro):
  ```sql
  DELETE FROM tb_log_matricula WHERE id_matricula IN
      (SELECT id_matricula FROM tb_matricula WHERE id_turma = 1 AND id_aluno BETWEEN 91 AND 100);
  DELETE FROM tb_matricula WHERE id_turma = 1 AND id_aluno BETWEEN 91 AND 100;
  ```

**(b) Correção 1, bloqueio:**
- Aba A: `CALL sp_matricular_bloqueio(91, 1);`
- Aba B, logo em seguida: `CALL sp_matricular_bloqueio(92, 1);` → a aba B fica **esperando** e depois
  recebe `Turma 1 sem vaga: 51 ocupadas de 51 vagas`. `v_vagas`: **51/51, LOTADA**. Limpeza.

**(c) Correção 2, SERIALIZABLE:**
- Nas duas abas, num F5 **separado**: `SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL SERIALIZABLE;`
- Confira em outro F5: `SHOW transaction_isolation;` → `serializable`.
- Aba A: `CALL sp_matricular_ingenuo(91, 1);` | Aba B: `CALL sp_matricular_ingenuo(92, 1);`
- A aba B **não espera**, mas recebe `could not serialize access` (erro 40001).
- Aba B repete o mesmo `CALL` → `sem vaga`. `v_vagas`: **51/51**. Limpeza e, nas duas abas:
  `SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL READ COMMITTED;`

### 3.6 Row-level security (~2 min) - `07_seguranca.sql`

```sql
SET search_path TO academico;
SELECT COUNT(*) FROM tb_historico;                 -- como bd2 (dono): 300

SET ROLE aluno_3;
SELECT * FROM v_historico;                         -- só as 4 linhas do aluno 3
SELECT COUNT(*) FROM tb_historico;                 -- 4
SELECT * FROM v_historico WHERE id_aluno = 4;      -- 0: não vê o colega
UPDATE tb_historico SET nota_a1 = 10;              -- ERRO de propósito: permission denied
RESET ROLE;
```

Depois de qualquer erro com `SET ROLE` ativo, rode `RESET ROLE;`.

### 3.7 Restauração de backup ao vivo (~3 min)

1. No pgAdmin, rode o `08_verificacao_backup.sql` e mostre: **300 matrículas, 36 índices, 6 policies**.
2. No CMD:
   ```
   docker exec bd2_aluno_postgres pg_dump -U bd2 -d matricula -n academico -Fc -f /tmp/academico.dump
   docker exec bd2_aluno_postgres psql -U bd2 -d matricula -c "DROP SCHEMA academico CASCADE"
   ```
3. No pgAdmin: `SELECT COUNT(*) FROM academico.tb_matricula;` → **erro: a tabela não existe** (o desastre).
4. No CMD:
   ```
   docker exec bd2_aluno_postgres pg_restore -U bd2 -d matricula /tmp/academico.dump
   ```
5. No pgAdmin: rode o `08` de novo → **os mesmos números**. E o RLS voltou junto:
   `SET ROLE aluno_3; SELECT COUNT(*) FROM academico.tb_historico; RESET ROLE;` → **4**.

### 3.8 Bônus JSONB + GIN (~1 min) - `09_bonus_jsonb_gin.sql`

```sql
SET search_path TO academico;
BEGIN;
INSERT INTO tb_matricula (id_aluno, id_turma, status_matricula) VALUES (91, 5, 'Ativa');
SELECT * FROM tb_log_matricula;                                  -- a trigger gravou o log
SELECT * FROM tb_log_matricula WHERE detalhe @> '{"id_turma": 5}';  -- busca dentro do JSON
ROLLBACK;
```

O ganho do GIN está no `evidencias_explain.txt` (26,2 ms → 0,55 ms).

---

## 4. Perguntas prováveis do professor (respostas curtas)

**Modelagem e integridade**
- *ENUM x DOMAIN?* ENUM é uma lista fechada de valores; DOMAIN é um tipo existente (numeric) com uma regra CHECK reaproveitada em várias colunas.
- *Como a `media_geral` é calculada?* Coluna gerada: 40% da A1 + 60% da A2; a P3 substitui a menor das duas (vale o maior resultado).
- *Por que IDENTITY e não SERIAL?* IDENTITY é o padrão SQL; com `GENERATED ALWAYS` ninguém insere id na mão por engano.
- *Por que a carga não informa os ids?* O IDENTITY gera 1, 2, 3... na ordem dos INSERTs, e o 01 recria o schema do zero, então os ids são sempre os mesmos.

**Consultas**
- *GROUP BY x função de janela?* GROUP BY junta as linhas em uma; `OVER` mantém todas e acrescenta o cálculo como coluna.
- *Como a CTE recursiva termina?* Quando o termo recursivo não acha mais linhas; na 7 há a trava `nivel < 10`, na 8 o `UNION` (sem ALL) descarta repetidos e evita laço.
- *Por que NOT EXISTS na consulta 4?* `NOT IN` com um NULL na lista devolve vazio; `NOT EXISTS` não tem esse problema.

**Views e índices**
- *View x materialized view?* A view roda a consulta toda vez; a MV grava o resultado e só muda com REFRESH.
- *Por que CONCURRENTLY?* Não bloqueia a leitura da MV durante a atualização; exige índice único.
- *Para que o `security_invoker` na `v_historico`?* Sem ele a view roda como o dono e ignora o RLS: o aluno veria o histórico de todos.
- *Por que o 05b usa outra massa de dados?* Com 300 linhas o PostgreSQL nem usa índice (ler tudo é mais barato); com 500 mil o ganho aparece.
- *Por que não indexar tudo?* Índice ocupa espaço e deixa INSERT/UPDATE mais lentos.
- *O que é índice parcial?* Só entra no índice o que a consulta procura (matrículas `Ativa`): menor e mais barato de manter.

**Concorrência**
- *Por que a anomalia acontece?* Em READ COMMITTED uma sessão não enxerga o que a outra não confirmou; as duas contam 50 antes de qualquer uma inserir.
- *Nenhuma constraint resolve?* Não: UNIQUE barra o mesmo aluno duas vezes e CHECK olha uma linha; "no máximo N matrículas" é uma regra entre linhas.
- *Bloqueio x SERIALIZABLE?* Bloqueio é pessimista: faz fila e não precisa repetir. SERIALIZABLE é otimista: ninguém espera, mas quem perde recebe erro 40001 e precisa repetir a transação.
- *Qual vocês escolheram?* O bloqueio: o recurso disputado é conhecido (a linha da turma) e a aplicação não precisa de laço de repetição. Por isso só a `sp_matricular_bloqueio` é liberada para a secretaria.
- *Para que o `pg_sleep(5)`?* Simula o tempo entre verificar e gravar e abre a janela para a demonstração à mão; sem ele o problema existe, mas a janela é de milissegundos.

**Segurança**
- *GRANT x RLS?* GRANT diz o que o papel pode fazer na tabela; RLS diz quais linhas ele vê.
- *Como o banco sabe quem é o aluno?* O papel `aluno_3` é o aluno de id 3; a policy compara `current_user = 'aluno_' || id_aluno`. O diagrama não foi alterado.
- *Por que o bd2 vê tudo?* RLS não se aplica ao dono da tabela nem a superusuário; por isso a demonstração usa `SET ROLE`.

**Backup**
- *Por que lógico (`pg_dump`)?* Restaura só o schema, em outro servidor e em versão igual ou mais nova; não bloqueia o sistema.
- *O `pg_dump` leva os papéis?* Não: papel é do servidor. No desastre eles continuam; num servidor novo, rode o `07` ou use `pg_dumpall --roles-only`.
- *Como você prova que restaurou certo?* O `08` dá a mesma saída antes e depois, e o RLS continua funcionando.

**Projeto e grupo**
- *O que é bônus?* JSONB com índice GIN e trigger de auditoria (`09`).
- *Quem fez o quê?* Ver `AUTORES.md`: Carlos frente 1 (DDL, carga, consultas, índices, bônus), Ana Luiza frente 2 (concorrência), Lucas frente 3 (views, segurança, backup).

---

## 5. Se algo der errado (plano B)

| Problema | Solução |
|---|---|
| `port is already allocated` | Outro PostgreSQL está usando a 5432: feche-o, ou `docker ps` e `docker stop <nome>` |
| pgAdmin não abre | Espere ~30 s depois do `up`; confira com `docker compose ps` |
| `relation ... does not exist` | Faltou `SET search_path TO academico;` no Query Tool, ou um script anterior não rodou |
| Um script parou no meio | No pgAdmin o arquivo inteiro é uma transação: nada foi gravado. Corrija e rode o arquivo de novo |
| Demonstração da vaga bagunçou a turma 1 | Rode a limpeza (os dois `DELETE` da seção 3.5) |
| A aba ficou presa num `SET ROLE` | `RESET ROLE;` |
| O 06c não deu erro 40001 | O `SET SESSION CHARACTERISTICS` foi rodado no mesmo F5 do `CALL`; rode separado e confira com `SHOW transaction_isolation;` |
| Banco em estado estranho | Rode de novo do `01` ao `09` (o `01` recria tudo) |
