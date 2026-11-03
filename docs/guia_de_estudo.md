# Guia de estudo: como cada script funciona (03 ao 09)

Para quem precisa **entender e defender** o projeto na apresentação e na arguição cruzada. Cada seção diz:
o que o arquivo faz, como funciona por dentro (na ordem em que o código roda), o que dizer em voz alta
e as perguntas que o professor provavelmente fará.

## 0. O mapa em uma página

| Arquivo | Pergunta que responde | Ideia central |
|---|---|---|
| 03 consultas | "Sei consultar dados com SQL avançado?" | 10 consultas: JOIN, agregação, self-join, NOT EXISTS, HAVING, LEFT JOIN, recursão, janelas |
| 04 views | "Como simplifico e protejo o acesso?" | Views guardam consultas; a view *materializada* guarda também o **resultado** |
| 05 índices | "Como deixo consultas rápidas?" | Índice = "índice remissivo" do livro: evita ler a tabela inteira |
| 05b evidências | "Prove que ficou mais rápido" | Testa com 240 mil linhas, `EXPLAIN ANALYZE` antes e depois |
| 06 a 06d concorrência | "O que acontece quando muita gente matricula ao mesmo tempo?" | Duas pessoas pegam a mesma última vaga; como evitar e quanto custa |
| 07 segurança | "Quem pode ver/fazer o quê?" | Papéis, GRANT/REVOKE e RLS (cada aluno só vê as próprias linhas) |
| 08 + script de backup | "E se o banco for perdido?" | Backup, restauração e prova de que voltou igual |
| 09 bônus | JSONB + GIN | Busca dentro de documentos JSON, e auditoria automática |

**Ordem lógica:** 01-02 criam e enchem o banco → 03 consulta → 04 cria "janelas" sobre os dados → 05
acelera → 06 mostra um defeito sob concorrência e o corrige → 07 tranca o acesso → 08 garante que dá para
recuperar → 09 extra.

**Vocabulário mínimo**
- **Schema**: "pasta" dentro do banco (`academico`). Os scripts começam com `SET search_path TO academico` para
  você escrever `tb_aluno` em vez de `academico.tb_aluno`.
- **Transação**: bloco de comandos que vale tudo ou nada (`BEGIN`... `COMMIT`/`ROLLBACK`).
- **Sessão**: uma conexão aberta com o banco (um usuário).
- **Papel (role)**: usuário ou grupo de usuários.

---

## 1. `03_dql_consultas.sql` (as 10 consultas)

DQL = linguagem de consulta (só `SELECT`; nada é alterado). Cada consulta introduz uma técnica nova.

| # | Técnica | Como funciona |
|---|---|---|
| 1 | JOIN encadeado | `tb_aluno → tb_curriculo → tb_curso`: cada `JOIN ... ON` liga uma chave estrangeira à chave primária da outra tabela. |
| 2 | Agregação (`GROUP BY`) | Junta turma, disciplina, matrícula e histórico, **agrupa por turma** e calcula `COUNT` e `AVG`. Tudo que está no `SELECT` e não é agregado precisa estar no `GROUP BY`. |
| 3 | Self-join | A tabela `tb_disciplina` aparece **duas vezes** (`d1` = a disciplina, `d2` = o pré-requisito), ligadas por `tb_pre_requisito`. |
| 4 | `NOT EXISTS` | "Alunos para os quais **não existe** matrícula". Melhor que `NOT IN`, que dá resultado errado se a subconsulta devolver `NULL`. |
| 5 | `HAVING` | `WHERE` filtra **linhas** antes de agrupar; `HAVING` filtra **grupos** depois (turmas com mais de 30 matrículas). |
| 6 | `LEFT JOIN` | Mantém todos os professores, mesmo sem turma (aparecem com 0). Com `JOIN` comum eles sumiriam. |
| 7 | Recursiva | Veja abaixo. |
| 8 | Recursiva + `NOT EXISTS` duplo | Veja abaixo. |
| 9 | Função de janela `RANK` e `PERCENT_RANK` | Calcula valores **sem juntar as linhas** (diferente do `GROUP BY`). |
| 10 | `LAG` | Olha a linha **anterior** dentro do grupo. |

### Consulta 7 (recursiva): o ponto mais perguntado
```
WITH RECURSIVE arvore AS (
   <parte inicial>       -- nível 1: pré-requisitos diretos
   UNION ALL
   <parte recursiva>     -- usa o resultado anterior para achar o próximo nível
)
```
1. A parte inicial pega todos os pares (disciplina, requisito) com `nivel = 1`.
2. A parte recursiva liga cada linha já encontrada ao pré-requisito **do pré-requisito** e soma 1 ao nível.
3. Repete até não surgirem linhas novas.
4. `WHERE nivel < 10` é um **freio**: se houvesse um ciclo nos dados (A exige B, B exige A), a recursão não terminaria nunca.

Exemplo: se Cálculo II exige Cálculo I e Cálculo III exige Cálculo II, aparecem (Cálculo III, Cálculo II, nível 1),
(Cálculo III, Cálculo I, nível 2).

### Consulta 8 (disciplinas liberadas para o aluno 3)
Três blocos:
1. `cadeia_prerequisitos`: todos os pré-requisitos obrigatórios, diretos e indiretos (mesma ideia da 7, com `UNION` para eliminar repetidos).
2. `aprovadas`: quais disciplinas cada aluno já passou (`situacao = 'Aprovado'`).
3. A consulta final percorre as disciplinas do currículo do aluno e mantém só as que satisfazem **duas negações**:
   - **não** foi aprovado nela ainda; e
   - **não existe** pré-requisito dela em que ele **não** tenha sido aprovado (`NOT EXISTS ( ... NOT EXISTS ( ... ))`).
   Em português: "todos os pré-requisitos estão cumpridos".

### Consulta 9
`PARTITION BY id_turma` reinicia o cálculo a cada turma. `RANK() ... ORDER BY media DESC` dá 1 ao maior.
`PERCENT_RANK()` em ordem crescente vale `(posição−1)/(n−1)`: 1,00 é o melhor da turma, 0,00 o pior.

### Consulta 10
`LAG(media) OVER (PARTITION BY aluno ORDER BY ano, semestre, turma)` traz a média da matrícula anterior **do mesmo
aluno**. A diferença `nota_atual - nota_anterior` mostra a evolução (a primeira linha de cada aluno tem `NULL`, pois não há anterior).

**Perguntas prováveis:** diferença entre `WHERE` e `HAVING`? Por que `NOT EXISTS` e não `NOT IN`? O que acontece se houver ciclo na recursão? Qual a diferença entre `GROUP BY` e função de janela?

---

## 2. `04_views.sql`

**View** = consulta salva com nome. Não guarda dados: a cada uso, o banco executa a consulta de novo. Serve para (1) simplificar e (2) **esconder** colunas e linhas.

### `v_oferta` (oferta de turmas)
- Junta turma, período, disciplina e professor.
- `periodo_vigente`: `CURRENT_DATE BETWEEN data_inicio AND data_fim` (verdadeiro/falso).
- **`LEFT JOIN LATERAL`**: uma subconsulta que é executada **para cada turma** e pode usar `t.id_turma` de fora. Ela monta o texto dos horários: para cada linha de `tb_turma_horario` cria "Seg 08:15-11:00 (JB1)" e junta tudo com `string_agg(..., '; ')`.
  - `(ARRAY['Dom','Seg',...])[dia_semana]` converte o número do dia em nome (1=Dom ... 7=Sáb).
  - `substring(faixa ...)` recorta as horas do texto do intervalo.
  - `LEFT` + `COALESCE(..., 'A definir')`: turma sem horário não some, só mostra "A definir".
- É view **comum**: executa com os direitos do dono. Por isso o aluno consulta sem ter acesso à tabela do professor (o e-mail dele não vaza).

### `v_vagas` (ocupação)
- Subconsulta conta matrículas **`Ativa`** por turma (trancada/cancelada libera a vaga).
- `livres = vagas − ocupadas`; `NULLIF(vagas, 0)` evita divisão por zero.
- `CASE`: `COM VAGAS` / `LOTADA` / `SUPERLOTADA`. A última só aparece com **overbooking**; é por ela que enxergamos a anomalia do arquivo 06.

### `v_historico` com `security_invoker = true`
- Junta nota, frequência, disciplina, período, curso por aluno.
- Normalmente a view roda como **dono** (que ignora o RLS). Com `security_invoker`, roda como **quem consulta**, então o RLS do arquivo 07 vale. Sem isso, o aluno 3 veria o histórico de todos pela view. **Esta é a pegadinha clássica.**

### `mv_indicadores_disciplina` (materialized view)
- Guarda o **resultado** (taxa de aprovação, reprovações, médias por disciplina e período). Rápida de ler, mas fica "velha" até um `REFRESH`.
- `COUNT(*) FILTER (WHERE situacao = 'Aprovado')` conta só as linhas que atendem à condição (várias contagens em uma passada).
- **Política de atualização** (o PDF exige justificar): diário às 02:00 + sob demanda após lançar notas. Não por trigger, porque as notas entram em rajada e recalcular tudo a cada linha seria caro.
- **`REFRESH ... CONCURRENTLY`**: atualiza sem travar quem está lendo; **exige um índice único** (`ux_mv_indicadores_disciplina`).
- **`sp_atualizar_indicadores()`** é `SECURITY DEFINER`: roda com os direitos do dono, para a secretaria poder atualizar sem ter acesso às tabelas de base. `SET search_path` fixo evita que alguém crie um objeto falso com o mesmo nome e sequestre a função.

**Perguntas prováveis:** view × materialized view? Para que serve `security_invoker`? Por que o índice único na MV? Por que não atualizar por trigger? O que é `SECURITY DEFINER` e qual o risco?

---

## 3. `05_indices.sql`

**Índice** = estrutura auxiliar (B-tree) que localiza linhas sem ler a tabela toda, como o índice remissivo de um livro. Custo: ocupa espaço e deixa `INSERT/UPDATE` um pouco mais lentos. Por isso cada um tem uma **consulta real** que o justifica.

O PostgreSQL já indexa PK e `UNIQUE`, mas **não** indexa chave estrangeira.

| Índice | Tipo | Para quê |
|---|---|---|
| `idx_matricula_aluno (id_aluno)` | comum (FK) | "Matrículas de um aluno". O `UNIQUE (id_turma, id_aluno)` existente **não serve**: um índice composto só ajuda quando a busca começa pela **primeira** coluna (id_turma). |
| `idx_matricula_turma_ativa (id_turma) WHERE status = 'Ativa'` | **parcial** | Conta vagas ocupadas. Indexa só as matrículas ativas (poucas): índice pequeno e barato de manter; permite *index-only scan*. |
| `idx_aluno_nome_lower (lower(nome_aluno) text_pattern_ops)` | **de expressão** | Busca `WHERE lower(nome_aluno) LIKE 'mar%'`. O índice guarda o **resultado** de `lower(...)`; `text_pattern_ops` faz o `LIKE 'prefixo%'` funcionar mesmo com collation que não é "C". |
| `idx_historico_reprovado_falta (frequencia) INCLUDE (id_matricula) WHERE situacao = 'Reprovado por Falta'` | parcial + **cobertura** | Os 20 reprovados com menor frequência. Ordenado por `frequencia`; `INCLUDE` carrega a coluna extra para a consulta ser respondida **só pelo índice**, sem ir à tabela. |

`ANALYZE` atualiza as estatísticas para o planejador decidir bem. O `SELECT` final lista os índices; **a sua tela mostra os 4 esperados** (o GIN é do 09).

Regra de ouro: o índice só é usado se a consulta tem a **mesma forma**. `WHERE lower(nome_aluno) LIKE 'mar%'` usa o índice 3; `WHERE nome_aluno LIKE 'Mar%'` não usa.

**Perguntas prováveis:** por que o UNIQUE composto não resolve a busca por id_aluno? O que é índice parcial e qual a vantagem? Quando um índice **piora** o desempenho? Por que o planejador ignora índice em tabela pequena?

---

## 4. `05b_evidencias_explain.sql` (a prova do ganho)

**Problema:** com 300 matrículas o PostgreSQL varre a tabela inteira porque é mais barato que usar índice. Medir ali não prova nada.

**Solução do script:**
1. Confere que o 05 já rodou (um bloco `DO` consulta o catálogo e para com mensagem de erro se faltar).
2. Cria o schema **separado** `academico_perf` com tabelas de mesma estrutura (`LIKE ... INCLUDING ALL`) e **remove os índices de otimização** copiados, para o "antes" ser honesto. (Os dados reais não são tocados.)
3. Gera volume com `generate_series` e `random()`: 30 mil alunos, 9.600 turmas, 240 mil matrículas e históricos (6.370 reprovados por falta) e 200 mil logs com JSON.
4. Para cada uma das 5 consultas:
   - roda `EXPLAIN (ANALYZE, BUFFERS)` **sem** índice (guarda tempo, blocos lidos, tipo de varredura);
   - cria o índice (definição lida do catálogo com `pg_get_indexdef`, trocando o schema);
   - roda de novo e compara.
   A função temporária lê o `EXPLAIN` em formato JSON para extrair tempo e buffers (melhor de 5 execuções, depois de 1 de aquecimento).
5. Imprime o quadro-resumo e apaga o `academico_perf`.

**Como ler o `EXPLAIN`:** `Seq Scan` = leu a tabela toda; `Index Scan`/`Bitmap Index Scan`/`Index Only Scan` = usou índice; `Execution Time` = tempo real; `Buffers` = blocos de 8 kB lidos (menos = melhor).

**Seus resultados:** 104× (matrícula por aluno), 4,4× (turma ativa), 92× (nome), 1.003× (reprovados por falta: de 2.224 para 3 blocos), 318× (GIN).

**Perguntas prováveis:** diferença entre `EXPLAIN` e `EXPLAIN ANALYZE`? O que significam os buffers? Por que o ganho do índice 2 é menor? (A consulta precisa contar muitas linhas; mesmo assim passa a ler só o índice.)

---

## 5. Concorrência: `06`, `06b`, `06c`, `06d`

### O problema (a anomalia)
A turma 1 tem 51 vagas e 50 ocupadas. Dez alunos tentam entrar juntos na última vaga. O código "ingênuo" faz:
```
1) conta as matrículas ativas   -> 50 de 51: "tem vaga!"
2) insere a matrícula
```
No nível padrão **READ COMMITTED**, cada sessão só enxerga o que já foi **confirmado**. As 10 contam 50 antes de qualquer uma inserir, as 10 acham que há vaga e as 10 inserem: **60 em 51 vagas**. Nenhuma regra do banco impede (o `UNIQUE` só barra o mesmo aluno duas vezes). Esse padrão é "checar e depois agir" (*write skew* / condição de corrida).

### `06_anomalia_vagas.sql`
- **`sp_matricular_ingenuo`**: o código com defeito. `pg_sleep(p_pausa)` entre checar e inserir amplia a janela da corrida para a demonstração (sem pausa o erro ainda ocorre, só que menos previsível; o 06d mostra 10 de 10).
- **`sp_limpar_disputa`**: desfaz o experimento. Só apaga matrículas **sem histórico** (as reais da carga têm), então não destrói dados verdadeiros mesmo se usada errado.
- **`sp_simular_disputa` (o "laboratório")**: o difícil é provocar concorrência **dentro do SQL**. Solução: extensão **`dblink`**, que abre conexões independentes:
  1. conexão de controle `ctl` prepara o estado e lê o resultado (cada comando confirma na hora);
  2. ajusta `vagas` para ter exatamente `p_vagas_livres` livres durante o teste;
  3. abre uma conexão `disp_1..disp_10`, uma por aluno (no modo `serializable`, cada uma nasce com `SET default_transaction_isolation TO serializable`);
  4. `dblink_send_query` dispara as 10 chamadas **sem esperar** (isso é o paralelismo);
  5. `dblink_get_result` recolhe as respostas: `MATRICULADO`, `SEM_VAGA`, ou erro `40001`/`40P01`; nos erros, **repete** na rodada seguinte (retentativa);
  6. mede `overbooking = ocupadas − vagas`, restaura as vagas originais (também se der erro) e devolve uma tabela-resumo.
  - Há uma **trava**: recusa rodar se algum aluno já tiver matrícula real na turma.
- No fim: roda `'ingenuo'` (resultado: 60 em 51, `v_vagas` mostra `SUPERLOTADA`) e limpa.

### `06b_correcao_bloqueio.sql` (pessimista)
Mesma função com **uma linha a mais**: `SELECT vagas ... FROM tb_turma WHERE id_turma = X FOR UPDATE` **antes** de contar. `FOR UPDATE` tranca a linha da turma até o `COMMIT`; as demais sessões **esperam na fila**. Quando entram, o `COUNT` já enxerga a matrícula confirmada pela anterior e respondem `SEM_VAGA`. Resultado: 1 matriculado, 9 `SEM_VAGA`, 0 retentativas, 51/51.
- Tranca só **a turma disputada**; outras turmas não esperam (um `LOCK TABLE` pararia o sistema).
- Risco: deadlock se uma transação trancar várias turmas em ordens diferentes (solução: sempre na mesma ordem).

### `06c_correcao_isolamento.sql` (otimista)
O corpo é **igual ao ingênuo**; muda só o nível: **SERIALIZABLE**. O PostgreSQL (SSI) observa o que cada transação leu e escreveu; ao perceber que o resultado não equivaleria a nenhuma execução "uma de cada vez", **aborta** uma com `ERROR 40001 could not serialize access`. A aplicação precisa **capturar e repetir** a transação inteira (o laboratório faz isso). Na repetição a vaga já foi tomada → `SEM_VAGA`. Há uma trava: se chamarem fora de SERIALIZABLE, a função recusa (provado no teste final do arquivo). Resultado: 1 matriculado, 9 retentativas.

### `06d_comparacao_custos.sql`
Roda os três modos em quatro cenários e tira a média:
- A: 1 vaga, B: 5 vagas, C: 10 vagas (para todos), D: 1 vaga **sem pausa**.
Conclusões (veja `docs/comparacao_concorrencia.md`): só o ingênuo tem overbooking; as retentativas do SERIALIZABLE crescem **quadraticamente** (9, 35, 45) e ocorrem até quando há vaga para todos (falso positivo); o bloqueio não tem retentativa. **Decisão do projeto: bloqueio**, porque o recurso disputado é conhecido (a turma) e a contenção é alta justamente na abertura da matrícula.

**Perguntas prováveis:** O que é READ COMMITTED? Por que `SELECT` puro não impede o problema? Pessimista × otimista? O que é erro 40001 e o que a aplicação deve fazer? Por que as retentativas crescem no SERIALIZABLE? Como o `dblink` provoca concorrência de verdade? Qual a vantagem do `FOR UPDATE` sobre `LOCK TABLE`?

---

## 6. `07_seguranca.sql`

### 6.1 Quem é o aluno logado?
O diagrama não tem coluna de usuário e não pode mudar. Convenção: cada aluno tem um papel **`aluno_<id>`** (ex.: `aluno_3`), membro do grupo **`aluno`**.
`fn_id_aluno_logado()` extrai o número de `current_user` com uma expressão regular: `aluno_3` → 3; qualquer outro papel → `NULL`.
É seguro porque o usuário **não consegue trocar** o próprio `current_user` (uma variável de sessão `SET app.aluno = 3` qualquer um mudaria).
- `sp_provisionar_login_aluno(id, senha)` cria o papel; `NOLOGIN` por padrão (ninguém entra sem ser liberado); com senha, vira `LOGIN`.
- A função é `STABLE`: calculada uma vez por consulta, o que deixa o planejador usar índice no filtro.

### 6.2 Papéis e privilégios (menor privilégio)
1. **`REVOKE ALL ... FROM PUBLIC`** (tabelas, funções, procedures) e `ALTER DEFAULT PRIVILEGES`: parte do zero; nada é liberado "de graça".
2. `GRANT` por papel:
   - **aluno:** lê `v_oferta`, `v_vagas`, `v_historico` e as tabelas que a `v_historico` precisa (restritas pelo RLS). Não escreve nada.
   - **secretaria:** lê tudo; insere/atualiza em aluno, matrícula, histórico, turma, horário; insere no log; **`REVOKE DELETE`** em aluno, matrícula e histórico (nunca se apaga histórico: cancela-se mudando o status); executa `sp_atualizar_indicadores` e `sp_matricular_bloqueio`.
   - **coordenação:** só leitura, inclusive a MV.

### 6.3 RLS (Row-Level Security)
`GRANT` controla **tabela/coluna**; RLS controla **linhas**. Com `ENABLE ROW LEVEL SECURITY`, quem não tem política aplicável não vê **nenhuma** linha (negação por padrão).
- `pol_aluno_proprio_cadastro`: `USING (id_aluno = fn_id_aluno_logado())`, ou seja, só a própria linha de `tb_aluno`.
- `pol_aluno_proprias_matriculas`: mesmo filtro em `tb_matricula`.
- `pol_aluno_proprio_historico`: o histórico não tem `id_aluno`, então a política olha a matrícula dona (`EXISTS`).
- `pol_secretaria_tudo` e `pol_coordenacao_leitura`: `USING (true)` (todas as linhas); o que cada um pode **fazer** com elas é limitado pelos `GRANT`.
- `USING` filtra o que se **lê**; `WITH CHECK` valida o que se **grava**.

**Atenção:** o RLS **não vale para superusuário nem dono das tabelas**. Por isso a demonstração usa `SET ROLE aluno_3` (vira aquele usuário) e depois `RESET ROLE`.

### 6.4 Testes automáticos
O bloco `DO` testa cada regra com `SET LOCAL ROLE` e **falha com erro** se algo estiver aberto. Padrão de cada teste negativo:
```
BEGIN
   SET LOCAL ROLE aluno_3;  UPDATE ...;
   RAISE EXCEPTION 'FALHA: ...';                 -- só chega aqui se a permissão NÃO bloqueou
EXCEPTION WHEN insufficient_privilege THEN
   RAISE NOTICE 'OK ...';                         -- bloqueou: esperado
END;
```
São 18 verificações: aluno vê só 4 linhas, não vê o aluno 4, não altera nota, não lê log/professor/indicadores, não executa a função de matrícula; secretaria lê tudo, lança nota, **não apaga**; coordenação lê, **não escreve**.

**Perguntas prováveis:** GRANT × RLS? Por que a view precisa de `security_invoker`? Por que `current_user` e não uma variável de sessão? O RLS vale para o dono? Para que serve `REVOKE ... FROM PUBLIC`? Como a secretaria "cancela" uma matrícula se não pode apagar?

---

## 7. `08_verificacao_backup.sql` e `scripts/backup_restauracao.sh`

**Ideia:** "terminou sem erro" não prova que restaurou tudo. O `08` tira uma **impressão digital** do schema:
- por tabela: nº de linhas + `md5` do conteúdo (as linhas viram texto, ordenadas, e passam por MD5); `query_to_xml` executa uma consulta montada por nome de tabela;
- a MV, as sequências (o próximo id), a contagem de objetos (índices, constraints, policies, concessões), o RLS ativo e um teste funcional (`aluno_3` deve ver 4 linhas).
Duas impressões **idênticas** = restauração correta.

**O script (6 passos):** 1) impressão antes → 2) `pg_dump -Fc -n academico` (schema em formato compactado) e `pg_dumpall --roles-only` (papéis, que são do **cluster**, não do banco, e sem eles `GRANT` e RLS falhariam num servidor novo) → 3) destino: banco novo vazio ou `DROP SCHEMA academico CASCADE` (desastre) → 4) recria os papéis → 5) `pg_restore --exit-on-error` → 6) impressão depois e `diff`.
Detalhes completos em `docs/backup_restauracao.md`.

**Perguntas prováveis:** backup lógico × físico? Por que os papéis ficam de fora do `pg_dump`? Como você sabe que a restauração está correta? O `pg_dump` bloqueia o sistema? (Não: usa um *snapshot* consistente.) O que é RPO e como melhorá-lo (WAL/PITR)?

---

## 8. `09_bonus_jsonb_gin.sql`

`tb_log_matricula.detalhe` é `TEXT` no diagrama (não alterado). O script faz esse texto guardar **JSON** sem mudar o tipo:
1. `CHECK (pg_input_is_valid(detalhe, 'jsonb'))`: recusa texto que não seja JSON válido.
2. **Índice GIN** sobre a expressão `(detalhe::jsonb)` com `jsonb_path_ops`. B-tree só compara o valor inteiro; o **GIN é um índice invertido**: indexa cada chave/valor **dentro** do documento e responde "quais linhas contêm `{"id_turma": 1}`?" (operador `@>`) sem ler a tabela. `jsonb_path_ops` é menor e mais rápido, mas só atende `@>` (não `?`).
3. **Triggers**: `AFTER INSERT` em `tb_matricula` grava o log "MATRICULA"; `AFTER UPDATE OF status_matricula ... WHEN (OLD IS DISTINCT FROM NEW)` grava "STATUS_ALTERADO" só quando o status muda. A função é `SECURITY DEFINER` para gravar o log mesmo se quem matricula não tiver direito de escrever nele (a trilha de auditoria não depende de quem a gera); `session_user` registra quem conectou de verdade. `OLD`/`NEW` são a linha antes/depois da mudança.
4. A demonstração roda dentro de `BEGIN ... ROLLBACK`, então **não deixa sujeira** no banco.

**Perguntas prováveis:** GIN × B-tree? `json` × `jsonb`? Por que duas triggers? Por que a trigger é `SECURITY DEFINER`? Que operadores o `jsonb_path_ops` não atende?

---

## 9. Roteiro para estudar rodando (30 min)

1. Rode 01 e 02; **leia** a saída da 03 consulta por consulta e explique o `JOIN` de cada uma.
2. Rode 04 e, no `psql` ou no pgAdmin, `SELECT * FROM v_vagas;` e `SELECT definition FROM pg_views WHERE viewname='v_vagas';`.
3. Rode 05 e depois `EXPLAIN ANALYZE SELECT * FROM tb_matricula WHERE id_aluno = 5;` (com 300 linhas ele usa Seq Scan: explique por quê). Rode o 05b e leia o quadro-resumo.
4. Rode 06: veja `SUPERLOTADA`. Rode 06b e 06c e compare `retentativas`. Rode o 06d e relacione com a tabela do `docs/comparacao_concorrencia.md`.
5. Rode 07 e leia as linhas `OK`. Depois: `SET ROLE aluno_3; SELECT COUNT(*) FROM tb_historico; RESET ROLE;`.
6. Rode o script de backup em modo `desastre` e acompanhe os 6 passos.
7. Rode 09 e leia a saída da demonstração.

**Se cair na arguição e você não souber:** diga o **problema** que o arquivo resolve e a **ideia central** (a tabela do início deste guia). Isso costuma bastar para o professor conduzir o resto.
