# Issues do Marco 2: avaliação e textos revisados

Prazo do Marco 2: **06/11/2026**. Seminários: 09/11 e 16/11 (demonstração ao vivo no Docker PostgreSQL 17
e arguição cruzada entre os integrantes).

## 1. Avaliação das issues existentes

As quatro issues (#7 Views, #8 Índices e Provas de Ganho, #9 Transações e Anomalia de Concorrência,
#10 Segurança e Controle de Acesso) cobrem os temas certos, mas **não estão suficientemente
específicas para serem aceitas como estão**. Faltam critérios que o PDF cobra e que a nota depende de provar.

| Issue | Situação | O que falta / está errado |
|---|---|---|
| #7 Views | Parcial | Não exige `security_invoker` na view de histórico (sem isso o RLS da #10 é **contornado** pela view); a materialized view precisa de **índice único** (senão `REFRESH ... CONCURRENTLY` não funciona) e de **política de atualização justificada** (o PDF pede explicitamente). |
| #8 Índices | Parcial | Não exige o **ganho medido** (EXPLAIN ANALYZE antes/depois), nem **volume de dados**: com 300 matrículas o planejador ignora índices e a prova de ganho fica falsa. Não define o arquivo `evidencias_explain.txt`. Não pede os tipos de índice variados (parcial, expressão, cobertura). |
| #9 Transações | Parcial | Não exige reprodução com **sessões realmente concorrentes**, nem **as duas** correções (bloqueio e isolamento), nem a **comparação de custo/contenção/retentativas** pedida no PDF. |
| #10 Segurança | Parcial | Não diz **como identificar o aluno logado**: o diagrama (correto, não será alterado) não tem coluna de usuário. Solução adotada: papel individual `aluno_<id>` + `current_user`. Faltam testes que provem o bloqueio. |
| (ausente) | **Faltando** | **Backup e restauração**: obrigatório no Marco 2 e na demonstração ao vivo. Não existe issue. |
| (ausente) | Faltando | Bônus (JSONB + GIN, até +0,5 na A2), atualização do README/AUTORES e plano de commits. |
| Responsáveis | Atenção | As issues não mostram responsável. O PDF atribui: índices → responsável 1 (Lucas); transações → responsável 2 (Ana Luiza); views, segurança e backup → responsável 3 (Carlos). |

**Importante (nota):** o histórico de commits entra na avaliação (penalidade de até −1,0 para commit único
ou uma só pessoa). Cada integrante deve commitar a parte dele.

## 2. Textos revisados (colar nas issues)

### #7 Views e Materialized View
**Responsável:** Carlos Eduardo · **Arquivo:** `04_views.sql` · **Marco 2**

Criar, no schema `academico`, views que simplifiquem o acesso e a segurança.

Critérios de aceite:
- [ ] `v_oferta`: turmas com disciplina, professor, sala, período e horários formatados (convenção 1=Dom ... 7=Sáb).
- [ ] `v_vagas`: vagas, ocupadas (**somente matrículas `Ativa`**), livres e situação (`COM VAGAS`/`LOTADA`/`SUPERLOTADA`).
- [ ] `v_historico` criada com `WITH (security_invoker = true)`, para que o RLS da #10 valha também por ela.
- [ ] `mv_indicadores_disciplina` (taxa de aprovação, reprovações por nota e por falta, médias) com **índice único** `ux_mv_indicadores_disciplina`.
- [ ] Política de atualização **justificada** no `COMMENT` da MV: `REFRESH ... CONCURRENTLY` diário às 02:00 e sob demanda após fechamento de notas; sem trigger (custo em cada matrícula).
- [ ] `sp_atualizar_indicadores()` (`SECURITY DEFINER`, `SET search_path` fixo) para quem não é dono poder atualizar.
- [ ] Script idempotente, rodando após 01 e 02.

### #8 Índices e provas de ganho
**Responsável:** Lucas Pessoa Ranieri · **Arquivos:** `05_indices.sql`, `05b_evidencias_explain.sql`, `evidencias_explain.txt`

Criar índices **justificados por consulta** e provar o ganho com medição.

Critérios de aceite:
- [ ] Pelo menos 4 índices, de tipos diferentes: comum (FK sem índice), **parcial** (`WHERE status_matricula = 'Ativa'`), **de expressão** (`lower(nome_aluno)` com `text_pattern_ops`) e **de cobertura** (`INCLUDE`).
- [ ] Cada índice ligado a uma consulta real, com a justificativa no cabeçalho do `05_indices.sql`.
- [ ] Prova em **volume** (cópia do schema com dezenas de milhares de linhas, para o planejador escolher o índice): `EXPLAIN (ANALYZE, BUFFERS)` **antes e depois**, com tempo, buffers e tipo de varredura.
- [ ] `evidencias_explain.txt` gerado pelo script (`psql -q -f 05b_evidencias_explain.sql > evidencias_explain.txt`) e quadro-resumo com o ganho (x vezes).
- [ ] Não alterar o schema `academico` com os dados de volume (a carga fica em `academico_perf`, removida ao final).
- [ ] Rodar no Docker oficial (PG 17) e citar os números lá medidos.

### #9 Transações e anomalia de concorrência
**Responsável:** Ana Luiza · **Arquivos:** `06_anomalia_vagas.sql`, `06b_correcao_bloqueio.sql`, `06c_correcao_isolamento.sql`, `06d_comparacao_custos.sql`, `docs/comparacao_concorrencia.md`

Demonstrar uma anomalia real de concorrência e corrigi-la de duas formas.

Critérios de aceite:
- [ ] Anomalia reproduzida com **sessões concorrentes de verdade** (`dblink` assíncrono): N alunos disputando a última vaga de uma turma, resultando em overbooking (`v_vagas` = `SUPERLOTADA`).
- [ ] **Correção 1:** bloqueio pessimista (`SELECT ... FOR UPDATE` na linha de `tb_turma`).
- [ ] **Correção 2:** `SERIALIZABLE` com laço de retentativa (`40001`/`40P01`).
- [ ] Comparação **medida** entre as três versões: correção, tempo, contenção e número de retentativas, em mais de um cenário.
- [ ] Explicação do **por quê** (READ COMMITTED, *write skew*) e decisão justificada de qual correção o sistema adota.
- [ ] Cada script devolve o banco ao estado original.

### #10 Segurança e controle de acesso
**Responsável:** Carlos Eduardo · **Arquivo:** `07_seguranca.sql`

Criar papéis, privilégios mínimos e RLS.

Critérios de aceite:
- [ ] Papéis de grupo `aluno`, `secretaria`, `coordenacao` (`NOLOGIN`) e papéis individuais `aluno_<id>` (membros de `aluno`) para os 100 alunos. O aluno logado é identificado por `fn_id_aluno_logado()`, que lê `current_user`; **o diagrama não é alterado**.
- [ ] `REVOKE ALL FROM PUBLIC` e `GRANT` mínimo por papel, incluindo `ALTER DEFAULT PRIVILEGES`.
- [ ] RLS em `tb_aluno`, `tb_matricula` e `tb_historico`: o aluno vê apenas os próprios registros; secretaria e coordenação conforme a função.
- [ ] Aluno não lê `tb_professor` nem `tb_log_matricula`, não altera dados e não executa a função de matrícula.
- [ ] Secretaria matricula (`sp_matricular_bloqueio`), mas **não apaga** alunos, matrículas nem históricos; coordenação só lê.
- [ ] **Testes automáticos** (`SET LOCAL ROLE` + `insufficient_privilege`) que falham se qualquer regra quebrar.

### Nova: Backup e restauração (obrigatório no Marco 2)
**Responsável:** Carlos Eduardo · **Arquivos:** `08_verificacao_backup.sql`, `scripts/backup_restauracao.sh`, `docs/backup_restauracao.md`

Critérios de aceite:
- [ ] Estratégia documentada e justificada (lógico `pg_dump -Fc -n academico`; papéis à parte com `pg_dumpall --roles-only`; política de frequência, retenção e cópia externa).
- [ ] Script que faz o ciclo completo: impressão digital → backup → destino → papéis → restauração → impressão digital → comparação.
- [ ] Prova de integridade: linhas e MD5 do conteúdo por tabela, MV, sequências, índices, policies e concessões **idênticos** antes e depois, e RLS funcionando no banco restaurado.
- [ ] Cenários testados: banco novo, desastre (`DROP SCHEMA`) e servidor sem nenhum papel.
- [ ] Comandos do Docker documentados e ensaiados para a demonstração ao vivo.

### Nova: Bônus JSONB + GIN
**Responsável:** Lucas Pessoa Ranieri (índices) · **Arquivo:** `09_bonus_jsonb_gin.sql`

- [ ] `CHECK` garantindo JSON válido em `tb_log_matricula.detalhe`.
- [ ] Índice GIN `jsonb_path_ops` sobre `(detalhe::jsonb)`, com ganho medido (consulta 5 do `05b`).
- [ ] Triggers de auditoria automática (matrícula e mudança de status).

### Nova: Documentação e fechamento
**Responsável:** todos

- [ ] `README.md` com ordem de execução 01 a 09, comandos Docker e links dos docs.
- [ ] `AUTORES.md` completo (falta a matrícula da Ana Luiza).
- [ ] `evidencias_explain.txt` regenerado no Docker PG 17.
- [ ] Ensaiar a demonstração e a arguição cruzada (cada um deve saber explicar a parte dos outros).
- [ ] Commits por autor, com mensagens descritivas (um commit por entrega, não um único commit final).

## 3. Divisão sugerida de commits (histórico entra na nota)

| Autor | Commit | Arquivos |
|---|---|---|
| Carlos | `feat(views): views de oferta, vagas e histórico + MV com política de refresh` | `04_views.sql` |
| Lucas | `perf(indices): índices parcial, expressão e cobertura com provas EXPLAIN` | `05_indices.sql`, `05b_evidencias_explain.sql`, `evidencias_explain.txt` |
| Ana Luiza | `feat(concorrencia): anomalia da última vaga e correções (bloqueio e SERIALIZABLE)` | `06*.sql`, `docs/comparacao_concorrencia.md` |
| Carlos | `feat(seguranca): papéis, GRANT/REVOKE e RLS com testes automáticos` | `07_seguranca.sql` |
| Carlos | `feat(backup): backup e restauração verificáveis` | `08_verificacao_backup.sql`, `scripts/`, `docs/backup_restauracao.md` |
| Lucas | `feat(bonus): JSONB com GIN e triggers de auditoria` | `09_bonus_jsonb_gin.sql` |
| Todos | `docs: README, AUTORES e evidências do Marco 2` | `README.md`, `AUTORES.md` |

## 4. Observação sobre a execução

Não consigo editar as issues no GitHub daqui: os textos acima são para colar. Tudo foi testado em
PostgreSQL 16; o ambiente oficial é o 17 (Docker), então **reexecute `05b`, `06d` e o backup lá** e use os
números que você medir na apresentação.
