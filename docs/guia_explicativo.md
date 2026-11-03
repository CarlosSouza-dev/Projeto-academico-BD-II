# Guia explicativo do projeto

O que cada arquivo faz, **por que** foi feito assim e o que responder na arguição. Na arguição cada um
responde sobre a frente de **outro** colega, então todos precisam saber o guia inteiro.

## 0. Como os arquivos se encaixam

```
01 cria as tabelas ──► 02 carrega os dados ──► 03 consultas (só leitura)
                              │
                              ▼
                04 VIEWS (v_oferta, v_vagas, v_historico) e a MATERIALIZED VIEW
                              │
     ┌────────────────────────┼──────────────────────────┐
     ▼                        ▼                          ▼
05 ÍNDICES             06 a ÚLTIMA VAGA            07 SEGURANÇA (quem vê o quê)
05b prova o ganho      06b e 06c corrigem          usa a v_historico do 04 e
                                                   libera a procedure do 06b à secretaria
                              │
                              ▼
09 BÔNUS (JSONB + GIN + trigger)        08 conferência do backup e da restauração
```

**Ideia central do Marco 2:** o Marco 1 entregou um banco que funciona. O Marco 2 mostra que ele é
**rápido** (índices), **correto com vários usuários ao mesmo tempo** (a última vaga), **seguro**
(papéis e RLS) e **recuperável** (backup). Cada item tem uma prova que roda ao vivo.

---

## 1. `01_ddl_inicial.sql`: tabelas e restrições (Carlos)

| Recurso | Onde | Para quê |
|---|---|---|
| `CREATE TYPE ... AS ENUM` | `turno_t`, `status_mat_t`, `situacao_t`... | A coluna só aceita os valores da lista |
| `CREATE DOMAIN` | `nota_t` (0 a 10), `pct_t` (0 a 100) | Um tipo com regra embutida, reaproveitado em várias colunas |
| `GENERATED ALWAYS AS IDENTITY` | todas as PKs | O banco gera o id |
| Coluna gerada (`... STORED`) | `ch_total_disciplina`, `media_geral` | O valor é calculado a partir de outras colunas e não pode ser digitado |
| `CHECK` | semestre 1 ou 2, `data_fim > data_inicio`, CPF com 11 dígitos, pré-requisito diferente da própria disciplina | Regras de negócio |
| `UNIQUE` | CPF, e-mail, `(id_turma, id_aluno)` | Sem repetição; o aluno não entra duas vezes na mesma turma |
| `REFERENCES` | todas as FKs | Não existe matrícula de aluno inexistente |

**Perguntas prováveis**
- *Diferença entre ENUM e DOMAIN?* ENUM é uma lista fechada de valores; DOMAIN é um tipo existente
  (numeric) com uma regra (CHECK) que vale em todo lugar onde ele é usado.
- *Como a `media_geral` é calculada?* É coluna gerada: 40% da A1 + 60% da A2, e a P3 substitui a menor
  das duas (vale o maior dos três resultados).

## 2. `02_dml_carga.sql`: carga (Marco 1)

- Os ids não são informados: o IDENTITY gera 1, 2, 3... na ordem dos INSERTs. Como o 01 recria tudo,
  os ids são sempre os mesmos.
- Os 100 alunos vêm de `generate_series(1, 100)`. O nome é montado com três listas (ARRAY) usando o
  resto da divisão (`i % 20`, `i % 11`, `i % 13`).
- 6 turmas com 51 vagas e exatamente 50 matrículas: sobra 1 vaga, que é o cenário do 06.
- Alunos 91 a 100 ficam sem matrícula de propósito (consulta 4 e disputa do 06).
- `setseed(0.42)` faz o `random()` das notas dar sempre o mesmo resultado.

## 3. `03_dql_consultas.sql`: 10 consultas (Marco 1)

| # | O que responde | Técnica |
|---|---|---|
| 1 | Aluno e seu curso | JOIN em cadeia (aluno → currículo → curso) |
| 2 | Média da A1 por turma | JOIN + GROUP BY |
| 3 | Disciplina e seu pré-requisito | Auto-junção (a mesma tabela duas vezes) |
| 4 | Alunos sem matrícula | `NOT EXISTS` (seguro contra NULL, ao contrário do `NOT IN`) |
| 5 | Turmas com mais de 30 alunos | `HAVING` (filtro depois do agrupamento) |
| 6 | Turmas por professor, inclusive quem não tem turma | **Junção externa** (`LEFT JOIN`) com agregação |
| 7 | Árvore de pré-requisitos | **CTE recursiva** (âncora + `UNION ALL` + termo recursivo), com trava de profundidade |
| 8 | Disciplinas que o aluno 3 já pode cursar | **CTE recursiva** com todos os pré-requisitos + CTEs `aprovadas` e `bloqueadas` |
| 9 | Ranking e percentil por turma | **Função de janela**: `RANK()` e `PERCENT_RANK()` com `PARTITION BY` |
| 10 | Evolução da nota de cada aluno | **Função de janela**: `LAG()` (a linha anterior) |

**Perguntas prováveis**
- *GROUP BY x função de janela?* O GROUP BY junta as linhas em uma; a janela (`OVER`) mantém todas e
  acrescenta o cálculo como uma coluna.
- *Por que a consulta 8 só mostra disciplinas sem pré-requisito?* Porque a carga só tem matrículas
  "Cursando": ninguém foi aprovado ainda, então nada foi desbloqueado.
- *Como a recursão termina?* Quando o termo recursivo não acha mais linhas. Na 7 há também `nivel < 10`,
  e na 8 o `UNION` (sem ALL) descarta repetidos, o que impede o laço se houver ciclo nos dados.

## 4. `04_views.sql`: views e materialized view (Lucas)

| Objeto | O que mostra | Detalhe importante |
|---|---|---|
| `v_oferta` | Turmas com disciplina, professor, dia, horário e sala | Esconde 6 JOINs; `LEFT JOIN` para turma sem horário |
| `v_vagas` | Vagas, ocupadas, livres e situação | Ocupada = matrícula `Ativa` (`COUNT ... FILTER`). `SUPERLOTADA` denuncia a anomalia do 06 |
| `v_historico` | Notas e situação por aluno e disciplina | `security_invoker = true`: o RLS do 07 vale também pela view |
| `mv_indicadores_disciplina` | Aprovados, reprovados e médias por disciplina | **Materialized**: o resultado fica gravado; atualiza só com `REFRESH` |

**Política de atualização da MV:** um `REFRESH MATERIALIZED VIEW CONCURRENTLY` por dia (madrugada) e
outro depois do lançamento de notas. Indicador de gestão não precisa ser em tempo real, e recalcular
a cada consulta (view comum) ou a cada matrícula (trigger) seria desperdício. O `CONCURRENTLY` deixa a
MV legível durante a atualização e **exige um índice único** (`ux_mv_indicadores_disciplina`).

**Perguntas prováveis**
- *View x materialized view?* A view roda a consulta toda vez (dado sempre atual). A MV grava o
  resultado (leitura rápida, mas o dado fica parado até o REFRESH).
- *Para que o `security_invoker`?* Por padrão a view roda com as permissões do **dono**, que não é
  filtrado pelo RLS. Com `security_invoker` ela roda com as permissões de **quem consulta**; assim o
  aluno vê pela view só as linhas dele.

## 5. `05_indices.sql` e `05b_evidencias_explain.sql`: índices (Carlos)

| Índice | Tipo | Consulta que atende |
|---|---|---|
| `idx_matricula_aluno` | comum, em FK | Matrículas de um aluno (o PostgreSQL não indexa FK sozinho) |
| `idx_matricula_turma_ativa` | **parcial** (`WHERE status_matricula = 'Ativa'`) | Vagas ocupadas de uma turma (a contagem da matrícula do 06) |
| `idx_aluno_nome_lower` | de **expressão** (`lower(nome_aluno)`) | Busca por nome sem diferenciar maiúsculas |
| `idx_historico_situacao_freq` | **composto** (2 colunas) | Reprovados por falta em ordem de frequência (filtra pela 1ª coluna e já sai ordenado pela 2ª) |

**Por que o 05b existe:** com 300 matrículas o PostgreSQL nem usa índice (ler 300 linhas direto é
mais barato). O 05b cria uma massa de teste de 500 mil linhas, roda o `EXPLAIN (ANALYZE, BUFFERS)`
antes e depois de cada índice e depois apaga a massa.

**Ganho medido (PostgreSQL 17, arquivo `evidencias_explain.txt`):**

| Índice | Antes | Depois | Páginas lidas (antes → depois) |
|---|---|---|---|
| comum (id_aluno) | Seq Scan, 7,7 ms | Index Scan, 0,03 ms | 3.200 → 8 |
| parcial (turma ativa) | Seq Scan, 7,4 ms | Bitmap Index Scan, 0,05 ms | 3.200 → 27 |
| expressão (lower) | Seq Scan, 15,6 ms | Index Scan, 0,02 ms | 640 → 4 |
| composto (situação, frequência) | Seq Scan + ordenação, 9,2 ms | Index Scan já ordenado, 0,04 ms | 3.376 → 23 |
| GIN (bônus, JSONB) | Seq Scan, 26,2 ms | Bitmap Index Scan, 0,55 ms | 2.880 → 161 |

O índice parcial ocupa **392 kB**, contra **5.720 kB** de um índice na tabela toda.

**Perguntas prováveis**
- *Como ler o EXPLAIN?* `Seq Scan` = leu a tabela inteira; `Index Scan` = foi direto às linhas;
  `Execution Time` = tempo real; `Buffers` = páginas de 8 kB lidas.
- *Por que não indexar tudo?* Cada índice ocupa espaço e deixa INSERT/UPDATE mais lentos, porque o
  índice também precisa ser atualizado.
- *Para que o `ANALYZE`?* Atualiza as estatísticas que o planejador usa para escolher o plano.

## 6. `06`, `06b`, `06c`: a disputa pela última vaga (Ana Luiza)

Detalhes e comparação em [`comparacao_concorrencia.md`](comparacao_concorrencia.md).

| Arquivo | O que faz | Resultado (2 abas, alunos 91 e 92) |
|---|---|---|
| `06` | `sp_matricular_ingenuo`: conta, espera 5 s e insere | As duas entram: **52/51, SUPERLOTADA** |
| `06b` | `sp_matricular_bloqueio`: igual, com `FOR UPDATE` na turma | B espera A terminar e recebe "sem vaga": **51/51** |
| `06c` | a mesma procedure do 06, em `SERIALIZABLE` | B recebe o erro 40001, repete e recebe "sem vaga": **51/51** |

**Perguntas prováveis**
- *Por que a anomalia acontece?* Em READ COMMITTED uma sessão não enxerga o que a outra ainda não
  confirmou. As duas contam 50 antes de qualquer uma inserir.
- *Bloqueio x SERIALIZABLE?* O bloqueio é pessimista (faz fila, não precisa repetir). O SERIALIZABLE
  é otimista (ninguém espera, mas quem perde recebe erro e precisa **repetir** a transação).
- *Qual foi escolhida e por quê?* O bloqueio: o recurso disputado é conhecido (a linha da turma) e a
  aplicação não precisa de laço de repetição.

## 7. `07_seguranca.sql`: papéis, GRANT e RLS (Lucas)

- **Papéis de grupo** `aluno`, `secretaria`, `coordenacao` (NOLOGIN: só agrupam permissões).
- **Papéis de aluno** `aluno_3`, `aluno_4`, `aluno_91`, membros de `aluno`. O diagrama não tem coluna
  de usuário, então a regra é: o papel `aluno_3` é o aluno de id 3.
- **GRANT/REVOKE:** o aluno lê as views e as próprias informações; a secretaria lê tudo, matricula e
  lança notas, mas **não apaga** histórico; a coordenação só lê. A procedure de matrícula segura só a
  secretaria executa (`REVOKE ... FROM PUBLIC`).
- **RLS:** em `tb_aluno`, `tb_matricula` e `tb_historico`. A policy do aluno é
  `current_user = 'aluno_' || id_aluno`. Secretaria e coordenação têm `USING (true)`.

**Demonstração:** `SET ROLE aluno_3;` → `SELECT COUNT(*) FROM tb_historico;` dá **4** (o dono vê 300).
Tentar `UPDATE` nas notas ou ler `tb_professor` dá **permission denied**.

**Perguntas prováveis**
- *GRANT x RLS?* O GRANT diz **o que** o papel pode fazer na tabela (SELECT, UPDATE...). O RLS diz
  **quais linhas** ele enxerga.
- *Por que o dono vê tudo?* O RLS não se aplica ao dono da tabela nem a superusuário. Por isso a
  demonstração usa `SET ROLE`.
- *E se o aluno consultar pela view?* A `v_historico` tem `security_invoker`, então o RLS vale também.

## 8. `08_verificacao_backup.sql` e o backup (Lucas)

Passo a passo e justificativa em [`backup_restauracao.md`](backup_restauracao.md). Resumo: `pg_dump`
do schema → `DROP SCHEMA academico CASCADE` → `pg_restore` → o `08` dá a mesma saída de antes.

## 9. `09_bonus_jsonb_gin.sql`: JSONB + GIN (bônus)

- A coluna `detalhe` do log vira `jsonb` (`ALTER COLUMN ... TYPE jsonb`).
- Índice **GIN** na coluna: acelera `detalhe @> '{"id_turma": 5}'` ("contém").
- **Trigger** `trg_matricula_log` (AFTER INSERT em `tb_matricula`): a função `fn_log_matricula()`
  grava o log com `jsonb_build_object(...)`. Como nas aulas: a função (`RETURNS TRIGGER`) e a trigger
  são dois objetos.

**Pergunta provável:** *Por que GIN e não B-tree?* O B-tree ordena o valor inteiro da coluna. O GIN
guarda cada chave e valor de **dentro** do JSON e responde "quais linhas contêm isto?".

## 10. Frases-chave

- "Restrição garante a regra **dentro de uma linha**; a última vaga é uma regra **entre linhas**, por isso precisa de controle de concorrência."
- "Índice parcial: só entra no índice o que a consulta procura."
- "GRANT diz o que pode fazer; RLS diz quais linhas pode ver."
- "Backup só vale se a restauração for testada e conferida."
