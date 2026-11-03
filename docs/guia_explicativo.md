# Guia explicativo do projeto (do 03 ao 09)

Para entender o que cada arquivo faz, **por que** foi feito assim e o que responder na arguição.
Cada arquivo tem: o que faz, como funciona por partes, os conceitos e as perguntas prováveis.

## 0. Visão geral: como os arquivos se encaixam

```
01 cria as tabelas ──► 02 carrega os dados ──► 03 consultas (só leitura)
                                │
                                ▼
                  04 VIEWS (v_oferta, v_vagas, v_historico, MV)
                                │
        ┌───────────────────────┼─────────────────────────┐
        ▼                       ▼                         ▼
 05 ÍNDICES (rapidez)   06 CONCORRÊNCIA (a última vaga)   07 SEGURANÇA (quem vê o quê)
 05b prova o ganho      06b/06c corrigem, 06d compara      usa v_historico e o índice do 05;
                        07 libera a função do 06b          dá a função do 06b à secretaria
                                │
                                ▼
 09 BÔNUS (JSONB + GIN + triggers)     08 + scripts/backup_restauracao.sh (salvar e restaurar tudo)
```

**Ideia central do Marco 2:** o Marco 1 entregou um banco que *funciona*. O Marco 2 mostra que ele é
**rápido** (índices, views), **correto sob concorrência** (a última vaga), **seguro** (papéis e RLS) e
**recuperável** (backup). Cada item precisa de **prova**: números, saídas e testes.

**Sobre o resultado que você me enviou (05):** está **correto**. O 05 cria exatamente 4 índices e a
consulta final mostra só eles (filtro `indexname LIKE 'idx\_%'`). A linha 2 aparece cortada no
pgAdmin por causa da largura da coluna (termina em `WHERE situacao = 'Reprovado por Falta'`). O
`::status_mat_t` que aparece na linha 4 é só o PostgreSQL mostrando o tipo do valor `'Ativa'`. O quinto
índice (`idx_log_detalhe_gin`, o GIN do bônus) só nasce no `09`.

---

## 1. `03_dql_consultas.sql`: 10 consultas (Marco 1)

Só `SELECT`: não altera nada. Cada consulta ilustra uma técnica.

| # | O que responde | Técnica | Como funciona |
|---|---|---|---|
| 1 | Aluno e seu curso | `JOIN` encadeado | aluno → currículo → curso: cada `JOIN` segue uma chave estrangeira |
| 2 | Média da nota A1 por turma | `GROUP BY` + `AVG` | junta turma, disciplina, matrícula e histórico; agrupa por turma |
| 3 | Disciplina e seus pré-requisitos | **self-join** | `tb_disciplina` entra 2 vezes (`d1` = a disciplina, `d2` = o pré-requisito) ligadas por `tb_pre_requisito` |
| 4 | Alunos sem matrícula | `NOT EXISTS` | "não existe nenhuma matrícula deste aluno". É melhor que `NOT IN`, que dá resultado errado se a subconsulta devolver `NULL` |
| 5 | Turmas com mais de 30 matrículas | `HAVING` | `WHERE` filtra linhas *antes* de agrupar; `HAVING` filtra os grupos *depois* de contar |
| 6 | Turmas por professor | `LEFT JOIN` | mantém o professor **sem** turma (conta 0). Com `JOIN` comum ele sumiria |
| 7 | Árvore de pré-requisitos | **CTE recursiva** | veja abaixo |
| 8 | O que o aluno 3 já pode cursar | CTE recursiva + `NOT EXISTS` duplo | veja abaixo |
| 9 | Ranking por turma | `RANK()` e `PERCENT_RANK()` | funções de janela: calculam sem juntar as linhas |
| 10 | Evolução de notas do aluno | `LAG()` | traz a nota da linha anterior para calcular a variação |

**CTE recursiva (consulta 7).** Tem duas partes ligadas por `UNION ALL`:
1. *base:* os pré-requisitos diretos (nível 1);
2. *recursiva:* pega o que já foi achado e procura o pré-requisito **do** pré-requisito (nível + 1).

Repete até não aparecer linha nova. A trava `nivel_profundidade < 10` evita laço infinito se, por
erro, houver um ciclo nos dados (A exige B, que exige A).

**Consulta 8 (a mais difícil).** Regra: "o aluno pode cursar a disciplina se **ainda não foi aprovado**
nela **e** foi aprovado em **todos** os pré-requisitos".
- `cadeia_prerequisitos` calcula todos os pré-requisitos obrigatórios, diretos e indiretos. Usa `UNION` (e
  não `UNION ALL`) porque `UNION` elimina duplicatas e isso também impede ciclos de crescerem sem fim.
- `aprovadas` lista quem foi aprovado em quê.
- O `NOT EXISTS (... NOT EXISTS ...)` dentro de outro é a forma SQL de dizer **"para todo"**: "não existe
  nenhum pré-requisito que o aluno não tenha cumprido". SQL não tem "para todo", então se nega o "existe".

**Funções de janela (9 e 10).** Diferente do `GROUP BY`, elas **não colapsam** as linhas: cada aluno
continua aparecendo, com uma coluna extra calculada sobre o grupo (`PARTITION BY` = o grupo; `ORDER BY` =
a ordem dentro dele). `RANK` dá 1 ao maior; `PERCENT_RANK` em ordem crescente dá 1,00 ao melhor e 0,00 ao pior.

---

## 2. `04_views.sql`: views e materialized view

**Para que serve uma view:** é uma consulta com nome. Esconde a complexidade (6 `JOIN`s) e controla o
que cada usuário enxerga (o aluno lê a view sem ter acesso às tabelas).

### `v_oferta` (o que o aluno vê ao escolher turma)
Junta turma, período, disciplina e professor. A parte difícil é o horário:
- `LEFT JOIN LATERAL (...)`: uma subconsulta que **roda uma vez para cada turma** e pode usar `t.id_turma`.
  É `LEFT` para a turma sem horário aparecer como `'A definir'` (`COALESCE`).
- `string_agg(..., '; ')` junta vários horários da turma numa linha só: `Seg 08:15-11:00 (JB1); Qua ...`.
- `(ARRAY['Dom','Seg',...])[th.dia_semana]` converte o número do dia em texto (1=Dom ... 7=Sáb).
- `substring(th.faixa FROM 2 FOR 5)`: a `faixa` é um intervalo de tempo, que em texto fica
  `[08:15:00,11:00:00)`. Pegar 5 caracteres a partir da posição 2 dá `08:15`; a partir da 11 dá `11:00`.
- `periodo_vigente`: `true` se hoje está entre início e fim do período.

### `v_vagas` (ocupação)
- **Ocupada = matrícula com status `Ativa`.** Trancada/cancelada libera a vaga.
- Subconsulta `o` conta as ativas por turma; `LEFT JOIN` para turma vazia dar 0 (`COALESCE`).
- `NULLIF(t.vagas, 0)` evita divisão por zero.
- `situacao_vagas`: `COM VAGAS`, `LOTADA` (ocupadas = vagas) ou `SUPERLOTADA` (ocupadas > vagas).
  **A `SUPERLOTADA` só aparece com overbooking:** é como o 06 mostra a anomalia.

### `v_historico` (histórico detalhado) e `security_invoker`
Uma view comum roda com os direitos **do dono** da view; por isso ela **furaria o RLS** do 07 (o dono vê
tudo). Com `WITH (security_invoker = true)` ela roda com os direitos **de quem consulta**, então o aluno
só vê as próprias linhas, mesmo pela view. Essa é a ligação entre o 04 e o 07.

### `mv_indicadores_disciplina` (materialized view)
- **View comum:** guarda só a consulta; recalcula toda vez. **Materialized view:** guarda o **resultado**
  (como uma tabela) e só recalcula quando mandamos (`REFRESH`). Boa para painel pesado que não precisa ser
  em tempo real.
- `COUNT(*) FILTER (WHERE ...)`: conta só as linhas que atendem à condição, vários contadores numa consulta.
- Taxa de aprovação = aprovados ÷ (todos menos os "Cursando"), pois quem ainda cursa não foi julgado.
- `atualizado_em = now()` mostra quando o dado foi calculado.
- **Índice único (`ux_mv_...`):** obrigatório para `REFRESH ... CONCURRENTLY`.
- **`CONCURRENTLY`:** a MV continua legível durante a atualização (o refresh normal trava a leitura).
- **Política de atualização (o PDF pede justificativa):** diária às 02:00 + sob demanda após fechar notas.
  Sem trigger, porque as notas entram em rajada e recalcular tudo a cada linha seria caro.
- `sp_atualizar_indicadores()` é `SECURITY DEFINER`: roda com os direitos do **dono**, para a secretaria
  poder atualizar sem ter acesso às tabelas. O `SET search_path` fixo impede que alguém crie um objeto
  com o mesmo nome em outro schema para enganar a função.

**Perguntas prováveis:** *Por que a MV não atualiza sozinha?* (o PostgreSQL não faz isso; é preciso o
`REFRESH`, e escolhemos quando.) *Diferença entre view e MV?* *Por que `security_invoker`?*

---

## 3. `05_indices.sql`: os 4 índices

**Índice** é uma estrutura auxiliar (como o índice remissivo de um livro) que evita ler a tabela inteira.
O PostgreSQL já cria índice sozinho para chave primária e `UNIQUE`, mas **não para chave estrangeira**.

| Índice | Tipo | Para quê |
|---|---|---|
| `idx_matricula_aluno (id_aluno)` | comum | "matrículas do aluno X". O `UNIQUE (id_turma, id_aluno)` existente **não serve**: o `id_aluno` é a 2ª coluna, e índice composto só ajuda a partir da 1ª |
| `idx_matricula_turma_ativa (id_turma) WHERE status_matricula = 'Ativa'` | **parcial** | contar vagas ocupadas. Indexa **só** as ativas: menor, mais barato de manter, e permite *index-only scan* |
| `idx_aluno_nome_lower (lower(nome_aluno) text_pattern_ops)` | **de expressão** | busca por prefixo sem diferenciar maiúsculas (`lower(nome) LIKE 'ana%'`). O índice precisa ter a **mesma expressão** da consulta. `text_pattern_ops` permite o `LIKE 'prefixo%'` mesmo em collations que não são "C" |
| `idx_historico_reprovado_falta (frequencia) INCLUDE (id_matricula) WHERE situacao = 'Reprovado por Falta'` | **parcial + cobertura** | "os 20 piores em frequência entre os reprovados por falta". `INCLUDE` leva `id_matricula` dentro do índice, então a consulta é respondida **só pelo índice** (sem tocar a tabela) e já em ordem |

- `IF NOT EXISTS`: permite rodar de novo sem erro.
- `ANALYZE`: atualiza as estatísticas para o planejador (o "otimizador") saber que os índices existem e quanto ajudam.

**Pergunta provável:** *Por que não indexar tudo?* Cada índice ocupa espaço e **deixa `INSERT`/`UPDATE` mais lentos**
(precisam atualizar o índice). Só se cria o que uma consulta real usa.

---

## 4. `05b_evidencias_explain.sql`: a prova do ganho

**Problema:** com 300 matrículas, varrer a tabela é mais barato que usar índice, então o planejador
**nem usa o índice** e não haveria como provar nada. **Solução:** montar uma cópia com volume realista e medir.

Passo a passo:
1. Confere se o 05 foi executado: um bloco `DO` consulta o catálogo (`to_regclass`) e para com erro se faltar.
2. Cria o schema `academico_perf` copiando só a **estrutura** das tabelas (`LIKE ... INCLUDING ALL`). Isso
   copiou também os índices do 05, então o script **apaga os não-únicos**, para o "antes" ser honesto.
3. Carrega dados com `generate_series`: 30 mil alunos, 9.600 turmas, 240 mil matrículas, 240 mil
   históricos e 200 mil logs. `OVERRIDING SYSTEM VALUE` deixa gravar o `id` em colunas `IDENTITY`;
   `setseed(0.42)` deixa os "aleatórios" reproduzíveis. Cerca de 3% dos históricos viram "Reprovado por Falta".
4. `VACUUM (ANALYZE)`: atualiza estatísticas **e** o mapa de visibilidade, necessário ao index-only scan. O VACUUM não pode rodar dentro de uma transação, e o pgAdmin manda o arquivo todo como uma só; por isso o script dá `COMMIT` na carga e roda o VACUUM em **outra sessão**, via `dblink`.
5. Define 5 consultas e a função `medir`: roda `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` 6 vezes (a 1ª só
   aquece o cache), guarda o **menor** tempo e os **buffers** lidos.
6. Para cada índice: mostra o `EXPLAIN` **antes** → cria o índice → mostra o `EXPLAIN` **depois**.
   Uma função temporária (`pg_temp.explicar`) executa o `EXPLAIN` e escreve cada linha do plano em `RAISE NOTICE` (aba *Messages* do pgAdmin) e na tabela temporária `planos`. Os índices são lidos do banco com
   `pg_get_indexdef`, trocando `academico.` por `academico_perf.`.
7. Imprime o quadro-resumo (ganho em vezes) e **apaga** `academico_perf`.

**Como ler um `EXPLAIN`:**
- `Seq Scan` = leu a tabela inteira; `Index Scan`/`Bitmap Index Scan`/`Index Only Scan` = usou índice.
- `Execution Time` = tempo real. `Buffers: shared hit/read` = blocos de 8 kB lidos (cache/disco). **Menos
  buffers = menos trabalho**, e é mais estável que o tempo.
- Resultados medidos: índice por aluno ~100×, parcial de turma ~4×, expressão ~90×, cobertura ~1000×,
  GIN ~300×.

**Pergunta provável:** *Por que o ganho do parcial (4×) é menor?* A consulta agrupa **todas** as turmas
ativas; o ganho vem de ler um índice pequeno em vez da tabela, mas ainda precisa contar tudo.

---

## 5. `06_anomalia_vagas.sql`: o problema da última vaga

### A anomalia em palavras simples
A turma 1 tem 51 vagas e 50 ocupadas: **sobra 1**. Dois alunos tentam ao mesmo tempo:

```
Aluno A                          Aluno B
conta ocupadas -> 50 (< 51)      conta ocupadas -> 50 (< 51)     <- os dois leem ANTES de qualquer gravação
"tem vaga!"                      "tem vaga!"
INSERT matrícula                 INSERT matrícula
COMMIT                           COMMIT                          -> 52 matrículas em 51 vagas
```

Isso acontece porque, no nível padrão **READ COMMITTED**, cada comando só vê o que já foi **confirmado**
(`COMMIT`), e uma leitura simples **não trava nada**. É o padrão "**checar e depois agir**" (*write skew*).
Nenhuma regra do banco impede: o `UNIQUE` só barra o *mesmo* aluno duas vezes e o `CHECK (vagas >= 0)`
olha uma linha, não uma contagem de outra tabela.

### O que o arquivo contém
- **`CREATE EXTENSION dblink`**: extensão que permite a uma sessão **abrir conexões para o próprio banco**.
  É a forma de simular 10 usuários simultâneos usando só SQL.
- **`sp_matricular_ingenuo(aluno, turma, pausa)`**: conta as ativas; se `< vagas`, espera `pausa` segundos
  (`pg_sleep`, simulando validações demoradas, o que **alarga a janela** da corrida) e insere.
  Retorna `'MATRICULADO'`, `'SEM_VAGA'` ou `'TURMA_INEXISTENTE'`.
- **`sp_limpar_disputa()`**: apaga as matrículas do experimento (e seus logs). **Só apaga matrículas sem
  histórico**, então jamais apaga matrícula real da carga.
- **`sp_simular_disputa(modo, ...)`**, o "laboratório":
  1. valida o modo e monta o texto de conexão (mesmo servidor, banco e usuário);
  2. recusa se algum concorrente já tem matrícula real;
  3. abre a conexão **`ctl`** (controle), limpa o estado e **ajusta as vagas** para que sobrem exatamente
     `p_vagas_livres` (depois restaura). Ela é separada porque as outras sessões só enxergam o que foi
     **confirmado**, e cada comando da `ctl` é confirmado na hora;
  4. abre uma conexão **`disp_1 ... disp_N`** por aluno (se for `serializable`, configura o isolamento);
  5. **dispara todas ao mesmo tempo** com `dblink_send_query` (**assíncrono**: não espera a resposta) e
     depois colhe os resultados com `dblink_get_result`;
  6. se uma falhar com `serialization_failure` (40001) ou `deadlock_detected` (40P01), conta como
     **retentativa** e roda de novo na rodada seguinte (como uma aplicação correta faria);
  7. lê a ocupação final, restaura as vagas, fecha as conexões (também se der erro, no `EXCEPTION`) e
     devolve uma linha com: matriculados, sem vaga, retentativas, ocupadas, **overbooking** e duração.
- **Final do script:** mostra a turma antes, roda a disputa (resultado esperado: **60 ocupadas em 51
  vagas, overbooking 9, `SUPERLOTADA`**) e limpa.

**Pergunta provável:** *Isso não é um bug da pausa?* Não: o cenário D do 06d roda **sem pausa** e a anomalia
aparece em 10 de 10 execuções. A pausa só deixa o resultado determinístico para a demonstração.

---

## 6. `06b_correcao_bloqueio.sql`: correção 1 (esperar na fila)

Mudança no código: **uma linha**.
```sql
SELECT vagas INTO v_vagas FROM tb_turma WHERE id_turma = p_id_turma FOR UPDATE;
```
`FOR UPDATE` **trava a linha da turma** até o fim da transação. Quem chega depois **espera** nessa linha.
Quando o primeiro faz `COMMIT`, o próximo segue, conta de novo **já vendo a matrícula do colega** e
responde `SEM_VAGA`. Checar e agir viram uma operação indivisível, **por turma**.

- É **pessimista**: assume que vai haver conflito e o impede.
- Trava só a **linha da turma**: turmas diferentes não esperam umas pelas outras (`LOCK TABLE` pararia tudo).
- Não há risco de esquecer de soltar: o bloqueio termina no `COMMIT`/`ROLLBACK`.
- Deadlock não ocorre porque cada transação trava um único recurso.
- Resultado: 1 matriculado, 9 `SEM_VAGA`, **0 retentativas**, 51/51.

---

## 7. `06c_correcao_isolamento.sql`: correção 2 (tentar e repetir)

O corpo da função é **idêntico** ao da ingênua. A diferença é rodar em **`SERIALIZABLE`**. O PostgreSQL
(*Serializable Snapshot Isolation*) anota o que cada transação **leu** e **escreveu**; se o resultado não
puder equivaler a executá-las **uma de cada vez**, ele **aborta** uma com o erro 40001
(`could not serialize access due to read/write dependencies`).

- É **otimista**: ninguém espera; se der conflito, desfaz e **tenta de novo**.
- **A aplicação precisa repetir a transação inteira** ao receber 40001/40P01. Na repetição a vaga já foi
  tomada e vem `SEM_VAGA`. O laboratório faz esse laço.
- A função tem uma **trava de segurança**: recusa-se a rodar se o isolamento não for `serializable`
  (senão voltaria a ter a anomalia sem ninguém notar). O teste final prova que ela recusa.
- Resultado: 1 matriculado, 9 `SEM_VAGA`, **9 retentativas**, 51/51.

---

## 8. `06d_comparacao_custos.sql` e `docs/comparacao_concorrencia.md`

Roda os 3 modos em 4 cenários (10 alunos sempre): **A** 1 vaga; **B** 5 vagas; **C** 10 vagas (cabe todo
mundo); **D** 1 vaga sem pausa. Usa uma tabela temporária `rodadas` e resume com `AVG`, `MAX`, `COUNT ... FILTER`.

**O que concluir:**
- Só o **ingênuo** tem overbooking (A, B e D). No C ele "funciona" por acaso, pois há vaga para todos.
- **Bloqueio:** sem retentativas; as sessões esperam em fila.
- **SERIALIZABLE:** não espera, mas aborta e repete (9 no cenário A, até 45 no C: `N(N-1)/2`), mesmo
  quando havia vaga para todos (**falso positivo**: ele detecta o *padrão* de leitura/escrita, não o resultado).
- **Escolha do sistema: bloqueio**, porque o recurso disputado é conhecido (a linha da turma), a disputa é
  alta na abertura da matrícula e a aplicação fica simples. É por isso que o 07 dá à secretaria
  `sp_matricular_bloqueio`.

---

## 9. `07_seguranca.sql`: papéis, permissões e RLS

### Como o banco sabe quem é o aluno?
O diagrama **não tem coluna de usuário** e não foi alterado. Convenção: cada aluno entra com o papel
`aluno_<id>` (ex.: `aluno_3`). `fn_id_aluno_logado()` extrai o número de `current_user` com uma expressão
regular. É seguro porque o aluno **não consegue trocar** o `current_user` (uma variável de sessão tipo
`SET app.aluno = 3` qualquer um mudaria). É `STABLE` para o planejador poder usar o índice no filtro.

### Parte 1: papéis
- `aluno`, `secretaria`, `coordenacao`: papéis de **grupo**, `NOLOGIN` (ninguém entra com eles).
- `aluno_<id>`: um por aluno (100), membro de `aluno`, criado por `sp_provisionar_login_aluno`. Também
  `NOLOGIN`: para liberar o acesso real, a administração roda `CALL sp_provisionar_login_aluno(3, 'senha')`.

### Parte 2: GRANT/REVOKE (menor privilégio)
Começa **tirando tudo** de `PUBLIC` (todo mundo) e dá só o necessário:
| Papel | Pode |
|---|---|
| `aluno` | ler `v_oferta`, `v_vagas`, `v_historico` e as tabelas que a `v_historico` precisa (limitadas pelo RLS) |
| `secretaria` | ler tudo; `INSERT/UPDATE/DELETE` nas tabelas operacionais; **sem `DELETE`** em aluno, matrícula e histórico (cancela-se mudando o status); executar `sp_matricular_bloqueio` e o refresh da MV |
| `coordenacao` | só leitura, inclusive os indicadores |

Detalhe: o `DELETE` é concedido junto e **depois retirado** (`REVOKE DELETE`) das tabelas auditáveis, para
a regra ficar explícita e visível.

### Parte 3: RLS (Row-Level Security)
`GRANT` controla **tabelas e colunas**; RLS controla **quais linhas**. Depois de `ENABLE ROW LEVEL SECURITY`,
quem não tem **policy** aplicável vê **zero linhas** (negação por padrão).
- `pol_aluno_proprio_cadastro`: `USING (id_aluno = fn_id_aluno_logado())` → só a própria linha.
- `pol_aluno_proprias_matriculas`: idem.
- `pol_aluno_proprio_historico`: o histórico **não tem `id_aluno`**, então descobre o dono pela matrícula
  (`EXISTS` em `tb_matricula`).
- `pol_secretaria_tudo` e `pol_coordenacao_leitura`: `USING (true)` (todas as linhas); o que cada um pode
  *fazer* é limitado pelos `GRANT`.

**Atenção:** RLS **não vale** para superusuário nem para o dono da tabela. Por isso a demonstração usa
`SET ROLE aluno_3` para "virar" o aluno.

### Parte 4 e 5: demonstração e testes
Mostra o histórico completo (300 linhas) e depois, como `aluno_3`, só as 4 dele. Os **testes
automáticos** (`DO $$ ... $$`) fazem, para cada regra, uma tentativa que **deve falhar** e capturam
`insufficient_privilege`. Se a tentativa **funcionar**, o teste levanta `FALHA` e o script para; se
tudo passar, imprime `TODOS OS TESTES DE SEGURANÇA PASSARAM` (18 verificações). Cada `BEGIN ... EXCEPTION`
é uma sub-transação: o erro esperado é capturado e o script continua.

**Perguntas prováveis:** *GRANT x RLS?* *Por que `security_invoker` na `v_historico`?* *Por que a
secretaria não apaga?* *E se o aluno tentar `SET ROLE secretaria`?* (não pode: só quem é membro do papel.)

---

## 10. `08_verificacao_backup.sql` e `scripts/backup_restauracao.sh`

**Pergunta que o backup precisa responder:** "restaurou **tudo** e **igual**?". "Terminou sem erro" não prova.
O `08` tira uma **impressão digital** do schema `academico`:
- por tabela: nº de linhas e **MD5 do conteúdo** (`query_to_xml` roda uma consulta montada em texto para cada
  tabela; as linhas são ordenadas antes de gerar o hash);
- a MV (sem a coluna `atualizado_em`, que muda a cada refresh), as **sequências** (a posição do próximo id),
  e as contagens de objetos (índices, constraints, policies, concessões...);
- um **teste funcional**: `aluno_3` deve ver 4 linhas.

### O script `backup_restauracao.sh` (6 passos)
1. **Impressão antes.**
2. **Backup:** `pg_dump -Fc -n academico` (formato custom, só o schema do projeto) e
   `pg_dumpall --roles-only` (os **papéis**). Papéis pertencem ao **cluster**, não ao banco: sem eles, os
   `GRANT` e as policies falhariam num servidor novo.
3. **Destino:** modo `novo_banco` cria `<banco>_restaurado` (seguro); modo `desastre` roda
   `DROP SCHEMA academico CASCADE` para simular a perda.
4. **Restaura os papéis** (os que já existem dão erro esperado e são ignorados).
5. **`pg_restore --exit-on-error`**: qualquer falha interrompe, em vez de deixar um banco pela metade.
6. **Impressão depois e `diff`:** idênticas = restauração correta.

`set -euo pipefail` faz o script parar no primeiro erro. O `pg_dump` usa um *snapshot* consistente, então o
sistema **não precisa parar** durante o backup.

**Perguntas prováveis:** *Lógico x físico?* (lógico é portável entre versões e permite restaurar só o
schema; o físico copia o cluster todo.) *Por que backup dos papéis à parte?* *Como prova que restaurou?*
*O que não é coberto?* (papéis fora do dump, configuração do servidor, senhas de conexão; e só restaura até
o instante do backup: para perder segundos, seria preciso arquivar WAL/PITR.) Detalhes em `docs/backup_restauracao.md`.

---

## 11. `09_bonus_jsonb_gin.sql`: JSONB, GIN e triggers

- `tb_log_matricula.detalhe` é `TEXT` no diagrama (que não mudou). O script passa a guardar **JSON** nele.
- **`CHECK (detalhe IS NULL OR pg_input_is_valid(detalhe, 'jsonb'))`**: recusa texto que não seja JSON válido.
- **Índice GIN sobre `(detalhe::jsonb)`**: o texto é convertido em `jsonb` na hora de indexar. O **B-tree** só
  serve para comparar o valor inteiro; o **GIN** é um índice **invertido**: indexa cada chave/valor *dentro*
  do documento e responde "quais linhas **contêm** `{"id_turma": 1}`?" (operador `@>`) sem varrer a tabela.
  `jsonb_path_ops` indexa só o que o `@>` usa: menor e mais rápido, mas não atende `?`, `?|`, `?&`.
  A consulta precisa usar **a mesma expressão** `detalhe::jsonb @> ...` para o índice ser usado.
- **Triggers de auditoria:** gatilhos que o banco dispara sozinho.
  - `trg_matricula_log_insert`: depois de cada **matrícula nova**, grava no log
    `{"origem":"trigger","id_aluno":..,"id_turma":..,"status_novo":..}`.
  - `trg_matricula_log_status`: depois que o **status** muda, grava `status_anterior` e `status_novo`. O
    `WHEN (OLD IS DISTINCT FROM NEW)` evita log sem mudança real. São duas triggers porque `OLD` não existe num `INSERT`.
  - A função é `SECURITY DEFINER` (grava o log mesmo que quem matricula não tenha permissão no log) e usa
    `session_user` (quem de fato conectou).
- **Demonstração:** o CHECK recusa "isto não é json"; dentro de `BEGIN ... ROLLBACK` (nada fica gravado)
  matricula e cancela o aluno 91 e mostra o log gerado; busca por `@>`; e um `EXPLAIN` mostrando o GIN.
  Com 2 linhas o planejador prefere varrer a tabela; por isso `enable_seqscan = off` **só para exibir o plano**.
  Com 200 mil linhas ele escolhe o GIN sozinho (veja o `evidencias_explain.txt`).

---

## 11b. Como os scripts rodam no pgAdmin (e por que há `COMMIT`)

- O pgAdmin **não entende** comandos que começam com `\` (`\echo`, `\set`, `\gexec`...): são do programa `psql`. Por isso os scripts são SQL puro.
- O pgAdmin envia o arquivo **inteiro como um único comando**, e o PostgreSQL trata isso como **uma só transação**. Duas consequências:
  1. **Sessões do `dblink` não enxergam o que ainda não foi confirmado.** O 06 cria funções e logo as usa em outras conexões; sem `COMMIT` no meio, elas "não existem" para essas conexões. Idem a carga de volume do 05b.
  2. **`ROLLBACK` desfaz tudo desde o início do arquivo.** No 09, o `COMMIT` antes do `BEGIN` impede que a demonstração desfaça o CHECK, o índice e as triggers que o próprio arquivo criou.
- `VACUUM` não pode rodar nessa situação (por isso o `dblink_exec` no 05b).
- O pgAdmin mostra só o resultado da **última** consulta; `RAISE NOTICE` aparece na aba *Messages*. Para mostrar passo a passo, selecione o trecho e execute.
- `SET LOCAL ROLE` dura até o fim da **transação**, que aqui é o arquivo todo; por isso o 07 faz `RESET ROLE` ao final dos testes.

## 12. Roteiro de estudo e de apresentação

**Ordem sugerida:** 04 (views) → 05 (índices) → 06 (leia a seção "A anomalia" duas vezes) → 06b/06c → 07 →
08/backup → 09. Na arguição cruzada **cada um responde pela parte dos outros**, então estude as seções
"Pergunta provável" de todos.

**Frases-chave para memorizar:**
- *Anomalia:* "duas transações leem a mesma contagem antes de qualquer uma gravar; as duas decidem com
  base num dado que a outra invalida (write skew), e nenhuma constraint cobre isso."
- *Bloqueio x serializable:* "bloqueio espera e não repete; serializable não espera, mas aborta e exige
  repetição, e pode abortar à toa."
- *RLS:* "GRANT decide *o que* o papel faz; RLS decide *quais linhas* ele enxerga."
- *Índice:* "o que prova o índice não é existir, é o EXPLAIN antes e depois com volume."
- *Backup:* "backup que nunca foi restaurado e conferido não é backup."

**Comandos para a demonstração ao vivo (no pgAdmin ou `psql`, schema `academico`; selecione e execute um bloco por vez):**
```sql
SELECT * FROM v_vagas WHERE id_turma = 1;          -- 50/51
SELECT * FROM sp_simular_disputa('ingenuo');       -- overbooking 9  (06)
SELECT * FROM v_vagas WHERE id_turma = 1;          -- SUPERLOTADA
SELECT sp_limpar_disputa();
SELECT * FROM sp_simular_disputa('bloqueio');      -- 0 overbooking
SELECT * FROM sp_simular_disputa('serializable');  -- 0 overbooking, 9 retentativas
SELECT sp_limpar_disputa();
SET ROLE aluno_3; SELECT COUNT(*) FROM tb_historico; RESET ROLE;   -- 4
```
