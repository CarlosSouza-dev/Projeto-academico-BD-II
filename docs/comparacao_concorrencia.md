# Transações e concorrência: a disputa pela última vaga

Scripts: `06_anomalia_vagas.sql` (anomalia), `06b_correcao_bloqueio.sql` (correção 1),
`06c_correcao_isolamento.sql` (correção 2), `06d_comparacao_custos.sql` (medição).

## 1. A anomalia

**Cenário.** A turma 1 (Banco de Dados II, `CCODM2B`) tem 51 vagas e 50 matrículas ativas: sobra
**uma** vaga. Os alunos 91 a 100, que ainda não têm matrícula, tentam entrar ao mesmo tempo.

**Código ingênuo** (`sp_matricular_ingenuo`): `COUNT(*)` das matrículas ativas; se for menor que
`vagas`, faz o `INSERT`. É o padrão "checar e depois agir".

**Por que quebra.** No nível padrão do PostgreSQL, **READ COMMITTED**, cada comando enxerga o que
foi *confirmado* antes de ele começar, e uma leitura simples não trava nada. Com 10 sessões:

1. as 10 executam o `COUNT(*)` e todas leem 50 (nenhuma matrícula nova foi confirmada ainda);
2. as 10 concluem que "há vaga";
3. as 10 executam o `INSERT`, e nada impede.

Resultado medido: **60 matrículas ativas em 51 vagas (overbooking de 9)**, e `v_vagas` passa a
mostrar `SUPERLOTADA`. É uma anomalia do tipo *write skew*: nenhuma linha foi sobrescrita (não é
*lost update*), mas a decisão de cada transação se baseou em uma leitura que a escrita das outras
invalidou.

**Nenhuma constraint do modelo impede isso.** O `UNIQUE (id_turma, id_aluno)` só barra o *mesmo* aluno
duas vezes, e o `CHECK (vagas >= 0)` olha uma linha, não uma contagem de outra tabela.

**Não é artefato da pausa.** O experimento usa uma pausa de 0,2 s entre checar e inserir para alargar
a janela. Mas no cenário D (sem pausa nenhuma) a anomalia apareceu em **10 das 10 execuções**: a
janela de microssegundos existe sempre, a pausa só a torna determinística para a demonstração.

**Como é reproduzida.** `sp_simular_disputa` abre uma conexão por aluno com `dblink`, dispara as 10
matrículas em paralelo (`dblink_send_query` é assíncrono) e lê o resultado depois do `COMMIT`.
São 10 sessões e 10 transações distintas, como 10 usuários reais.

## 2. Correção 1: bloqueio explícito (`06b`)

```sql
SELECT vagas FROM tb_turma WHERE id_turma = :turma FOR UPDATE;   -- trava a turma ANTES de contar
SELECT COUNT(*) ... ;                                            -- só então checa
INSERT INTO tb_matricula ... ;                                   -- e age
-- o bloqueio é liberado no COMMIT
```

**Abordagem pessimista:** assume que haverá conflito e impede que ele ocorra. Quem chega depois
**espera** no `FOR UPDATE`. Ao ser liberado, executa o `COUNT(*)` já enxergando a matrícula do
colega (em READ COMMITTED cada comando tira uma foto nova) e responde `SEM_VAGA`. Checar e agir
passam a ser atômicos *por turma*.

- **Escopo:** trava só a linha da turma disputada. Matrículas em turmas diferentes não esperam umas
  pelas outras (um `LOCK TABLE` pararia o sistema todo).
- **Duração:** até o fim da transação; não há como esquecer de soltar.
- **Deadlock:** não ocorre aqui porque cada transação trava um único recurso. Se uma transação
  travasse várias turmas, seria preciso travar sempre na mesma ordem (por `id_turma`).
- **Variantes:** `pg_advisory_xact_lock(id_turma)` (trava lógica, sem tocar na linha) ou
  `FOR NO KEY UPDATE` (não bloqueia as verificações de chave estrangeira de outras transações).

## 3. Correção 2: nível de isolamento (`06c`)

O corpo da função é **idêntico** ao da versão ingênua. A correção é executar em
`SERIALIZABLE` e **repetir a transação** quando o banco a abortar.

**Abordagem otimista:** ninguém espera; cada transação roda livre. O PostgreSQL implementa
SERIALIZABLE com *Serializable Snapshot Isolation* (SSI): registra o que cada transação leu
(locks `SIRead`, que não bloqueiam ninguém) e o que escreveu, e procura dependências
leitura-escrita em ciclo entre transações concorrentes. Aqui, cada uma leu um conjunto (a
contagem) que a escrita da outra altera: é um ciclo, logo o resultado não equivale a nenhuma
execução "uma por vez". O banco então aborta a transação com
`ERROR 40001 could not serialize access due to read/write dependencies`.

**A aplicação é parte da correção.** Capturar o `40001` (e o `40P01` de deadlock) e refazer a
transação *inteira* é obrigatório. Na repetição, a vaga já foi tomada e a resposta é `SEM_VAGA`.
O laboratório faz esse laço (até 30 rodadas). Sem ele o aluno veria um erro técnico e a vaga
poderia ficar sem dono.

## 4. Comparação medida (`06d`)

10 sessões concorrentes na turma 1; cada linha é a média de 3 execuções (10 no cenário D).
`vagas livres` é quantas sobram na turma durante o teste. Ambiente: PostgreSQL 16, 1 máquina.

| Cenário | Vagas livres | Modo | Matriculados | Overbooking | Retentativas | Duração média |
|---|---|---|---|---|---|---|
| A: última vaga, pausa 0,2 s | 1 | ingênuo | 10 | **9** (3 de 3 execuções) | 0 | 218 ms |
| | | bloqueio | 1 | 0 | 0 | 223 ms |
| | | serializable | 1 | 0 | 9 | 220 ms |
| B: disputa parcial | 5 | ingênuo | 10 | **5** (3 de 3) | 0 | 219 ms |
| | | bloqueio | 5 | 0 | 0 | 1.041 ms |
| | | serializable | 5 | 0 | 35 | 1.038 ms |
| C: vaga para todos | 10 | ingênuo | 10 | 0 | 0 | 219 ms |
| | | bloqueio | 10 | 0 | 0 | 2.058 ms |
| | | serializable | 10 | 0 | 45 | 2.051 ms |
| D: última vaga, **sem pausa** | 1 | ingênuo | 7,7 | **até 9** (10 de 10) | 0 | 21 ms |
| | | bloqueio | 1 | 0 | 0 | 25 ms |
| | | serializable | 1 | 0 | 8,7 | 20 ms |

*Os tempos variam por máquina e por execução; o que se mantém é o padrão: overbooking só no modo
ingênuo, e as retentativas do SERIALIZABLE (9, 35 e 45 nos cenários A, B e C) praticamente não mudam.*

### Como ler

**Correção.** Os dois métodos eliminam o overbooking em todos os cenários. A versão ingênua falha
sempre que o número de interessados supera as vagas (A, B, D). No cenário C ela "funciona" só
porque há vaga para todos: a ausência de anomalia ali não prova que o código está correto.

**Custo.**
- Disputa pela última vaga (A, D): o custo é praticamente igual ao do código sem proteção. Só quem
  ganha faz o trabalho lento (a pausa); os demais respondem `SEM_VAGA` na hora.
- Quando várias matrículas **são aceitas** (B e C), as duas correções ficam em ~1 s (5 vagas) e ~2 s
  (10 vagas): o tempo é de **0,2 s × número de matrículas aceitas**, ou seja, o trabalho
  que *poderia* ser paralelo fica **serializado**. No bloqueio isso é por construção: um
  `FOR UPDATE` por vez. No SERIALIZABLE é por consequência: em cada rodada apenas uma transação
  consegue confirmar, as outras abortam e refazem.

**Contenção.**
- *Bloqueio:* é contenção **explícita e visível**: as sessões esperam em fila (`pg_locks`,
  `wait_event = transactionid/tuple`). Fica restrita à linha da turma.
- *SERIALIZABLE:* não há espera por lock, mas há **conflito lógico**. O detalhe importante é o cenário C: havia
  vaga para todos e ainda assim houve **45 abortos** (9+8+...+1). O SSI detecta o *padrão* de
  leitura/escrita, não o resultado: ele não sabe que a contagem ainda ia sobrar. É um **falso
  positivo inevitável**: trabalho descartado, e cada transação abortada gasta CPU e IO e volta ao início.

**Retentativas.**
- Bloqueio: **zero**. A aplicação não precisa de laço de repetição.
- SERIALIZABLE: de **N−1** (disputa total, A) a **N(N−1)/2** (todos aceitos, C) para N sessões:
  cresce **quadraticamente**. Exige código de repetição na aplicação, com limite de tentativas e,
  idealmente, *backoff* com variação aleatória; e exige que a transação seja **repetível**
  (sem efeitos externos, como e-mail, antes do `COMMIT`).

### Quando usar cada uma

| | Bloqueio explícito (`FOR UPDATE`) | `SERIALIZABLE` |
|---|---|---|
| Estilo | pessimista: espera | otimista: tenta e repete |
| Escopo | a linha/recurso que você trava | qualquer conflito entre as transações |
| Retentativa | não precisa | **obrigatória** |
| Falsos positivos | não | sim (abortos sem anomalia real) |
| Risco | deadlock se travar vários recursos fora de ordem; transações longas seguram a fila | tempestade de retentativas sob alta contenção |
| Quem precisa conhecer o problema | quem escreve a transação (precisa saber **o que** travar) | ninguém: protege invariantes que você nem listou |
| Melhor para | recurso quente e conhecido (a última vaga de uma turma) | conflito raro, várias regras entre tabelas, difícil de mapear travas |

**Escolha para este sistema:** o **bloqueio explícito**. O recurso disputado é conhecido (a linha da
turma), a contenção é alta justamente na abertura da matrícula (todos querem a mesma turma ao
mesmo tempo, cenário em que o SERIALIZABLE gera mais abortos) e a aplicação fica simples, sem laço
de repetição. Por isso `07_seguranca.sql` concede à secretaria a função `sp_matricular_bloqueio`.

O SERIALIZABLE continua sendo a melhor opção quando a regra envolve **vários objetos** e não se
sabe de antemão o que travar (por exemplo, "no máximo 2 trancamentos por semestre somando todas as
tabelas"), desde que o custo de repetir seja aceitável.

### Uma terceira abordagem (fora do escopo, para a arguição)

Um contador atômico: `UPDATE tb_turma SET ocupadas = ocupadas + 1 WHERE id_turma = :t AND ocupadas < vagas`
(com `ocupadas` como coluna nova) e conferir o número de linhas afetadas. Não precisa de laço de
repetição, e o bloqueio dura só o tempo do `UPDATE`. Exigiria alterar o modelo (nova coluna), por
isso não foi adotada.

## 5. Limites do experimento (honestidade técnica)

- Uma só máquina e um só servidor. Em produção, com latência de rede e dezenas de usuários, as
  proporções mudam, mas a **ordem de grandeza** das retentativas (quadrática) e a **correção** se mantêm.
- A pausa de 0,2 s é artificial; serve para ampliar a janela de corrida e comparar as abordagens
  de forma controlada. O cenário D mostra o comportamento sem ela.
- Dez sessões é pouco para estressar o `max_connections`; o laboratório não mede vazão sustentada.
  Para isso o caminho seria `pgbench` com `--max-tries` (retentativas automáticas por falha de serialização).
- Os números do quadro vêm de PostgreSQL 16; **rode `06d` no Docker oficial (PostgreSQL 17)** e cite os valores
  que você mediu na apresentação.

## 6. Como reproduzir

```
psql -f 06_anomalia_vagas.sql         -- cria o laboratório e mostra a anomalia
psql -f 06b_correcao_bloqueio.sql     -- correção 1
psql -f 06c_correcao_isolamento.sql   -- correção 2
psql -f 06d_comparacao_custos.sql     -- tabela da seção 4 (~30 s)
```

No pgAdmin, abra cada arquivo no Query Tool e execute inteiro (F5); o resumo da disputa é a última consulta de cada
script. Os `COMMIT` dos arquivos são necessários: as sessões do `dblink` só enxergam funções já confirmadas.

Exige a extensão `dblink` (já vem na imagem oficial) e usuário superusuário (o do Docker é). Se a
conexão local pedir senha, use o parâmetro `p_conninfo` de `sp_simular_disputa` (ver cabeçalho do `06`).
Cada script devolve a turma ao estado original ao final.
