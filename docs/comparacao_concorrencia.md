# Transações e concorrência: a disputa pela última vaga

Scripts: `06_anomalia_vagas.sql` (a anomalia), `06b_correcao_bloqueio.sql` (correção 1) e
`06c_correcao_isolamento.sql` (correção 2). A demonstração usa **duas abas do Query Tool**: cada aba
é uma sessão separada, como dois alunos em computadores diferentes.

## 1. A anomalia

**Cenário.** A turma 1 (Banco de Dados II) tem 51 vagas e 50 matrículas ativas: sobra **uma** vaga.
Os alunos 91 e 92, que não têm matrícula, tentam entrar ao mesmo tempo.

**A matrícula faz dois passos** (`sp_matricular_ingenuo`):
1. **checa**: `SELECT COUNT(*)` das matrículas ativas e compara com `vagas`;
2. **age**: se tem vaga, faz o `INSERT`.

Entre os dois passos há um `pg_sleep(5)`, que simula o tempo que o sistema leva para validar e gravar.
Sem ele o problema também existe, mas a janela é de milissegundos e fica difícil de reproduzir à mão.

**Por que quebra.** No nível padrão do PostgreSQL, **READ COMMITTED**, cada comando só enxerga o que já
foi **confirmado** (COMMIT). A sessão A conta 50 e vai dormir; a sessão B também conta 50, porque o
`INSERT` de A ainda não aconteceu. As duas acham que tem vaga e as duas inserem.

**Resultado medido** (PostgreSQL 17): as duas abas mostram "matriculado", e a `v_vagas` passa a
mostrar **52 ocupadas para 51 vagas, SUPERLOTADA**.

**Nenhuma constraint impede isso.** O `UNIQUE (id_turma, id_aluno)` só barra o **mesmo** aluno duas
vezes, e o `CHECK (vagas >= 0)` olha uma linha, não a contagem de outra tabela.

## 2. Correção 1: bloqueio explícito (`06b`)

```sql
SELECT vagas INTO v_vagas FROM tb_turma WHERE id_turma = p_id_turma FOR UPDATE;  -- trava a turma
SELECT COUNT(*) INTO v_ocupadas ...;                                             -- checa
INSERT INTO tb_matricula ...;                                                    -- age
-- a trava é solta no fim da transação (COMMIT ou ROLLBACK)
```

O `FOR UPDATE` trava **a linha da turma**. A sessão B chega no mesmo `SELECT ... FOR UPDATE` e
**espera** a sessão A terminar. Quando continua, o `COUNT(*)` já enxerga a matrícula de A (51 de 51)
e B recebe "sem vaga".

**Resultado medido:** a aba B ficou esperando por cerca de **4,7 s** (o tempo que faltava para A
terminar) e recebeu `Turma 1 sem vaga: 51 ocupadas de 51 vagas`. A v_vagas mostra **51/51, LOTADA**.

- Só trava matrículas da **mesma** turma; as outras turmas seguem normalmente.
- A trava é solta sozinha no COMMIT/ROLLBACK, então não há como esquecer de soltar.
- Deadlock não acontece aqui porque cada matrícula trava um único recurso.

## 3. Correção 2: nível de isolamento (`06c`)

O código é **o mesmo** da versão com o problema (`sp_matricular_ingenuo`). A única mudança é o nível
de isolamento da sessão:

```sql
SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```

No **SERIALIZABLE** o banco garante que o resultado seja igual ao de rodar as transações **uma de
cada vez**. Ninguém espera: as duas matrículas rodam juntas. Quando o banco percebe que as duas leram a
mesma contagem e as duas vão inserir, ele **cancela** uma delas com o erro
`40001 could not serialize access due to read/write dependencies among transactions`.

**A retentativa faz parte da correção.** Quem recebeu o erro precisa repetir a transação. Na repetição
a vaga já foi tomada e a resposta certa aparece.

**Resultado medido:** a aba B **não esperou**. No fim dos seus próprios 5 s recebeu o erro 40001 (a
matrícula dela foi desfeita). Repetindo o `CALL`, recebeu `Turma 1 sem vaga: 51 ocupadas de 51 vagas`.
A v_vagas mostra **51/51, LOTADA**.

## 4. Comparação

| | Bloqueio (`FOR UPDATE`) | `SERIALIZABLE` |
|---|---|---|
| Estilo | **pessimista**: impede o conflito, quem chega depois espera | **otimista**: deixa rodar e cancela se der conflito |
| O que muda no código | uma linha (`FOR UPDATE`) | nada no código; muda o nível de isolamento |
| Contenção | as matrículas da mesma turma fazem **fila** (no teste, B esperou ~4,7 s) | não há fila; o conflito aparece como **erro** no fim |
| Retentativa | **não precisa**: B recebe a resposta certa de primeira | **obrigatória**: a aplicação precisa capturar o 40001 e repetir |
| Custo | o tempo de espera de quem está na fila | o trabalho de quem foi cancelado é jogado fora e refeito; o banco ainda gasta para vigiar o que cada transação leu |
| Quem precisa conhecer o problema | quem escreve a procedure (precisa saber **o que** travar) | ninguém: protege mesmo regras que não foram previstas |
| Melhor para | um recurso disputado e conhecido (a vaga de uma turma) | conflitos raros, ou regras que envolvem várias tabelas |

**Escolha para o sistema: o bloqueio explícito.** O recurso disputado é conhecido (a linha da turma), a
disputa é forte justamente na abertura da matrícula (todos querendo a mesma turma), cenário em que o
SERIALIZABLE cancelaria muitas transações, e a aplicação fica simples, sem laço de repetição. Por isso
o `07_seguranca.sql` deixa a secretaria executar só a `sp_matricular_bloqueio`.

## 5. Limites do teste

- Duas sessões em uma máquina. Com dezenas de alunos ao mesmo tempo, a fila do bloqueio fica maior e
  o SERIALIZABLE cancela mais transações (cada uma que perde precisa repetir).
- O `pg_sleep(5)` é artificial: serve para abrir a janela da disputa e permitir a demonstração à mão.
