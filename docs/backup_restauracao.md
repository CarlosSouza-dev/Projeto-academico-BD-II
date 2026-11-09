# Backup e restauração

Arquivo de apoio: `08_verificacao_backup.sql`. Ele conta as linhas de cada tabela, os objetos (views,
índices, policies, triggers) e soma alguns valores. Rode **antes** do backup e **depois** da
restauração: a saída tem de ser igual. É isso que prova que a restauração trouxe tudo de volta, e não
só que "terminou sem erro".

## 1. Estratégia e justificativa

**Backup lógico com `pg_dump`, no formato custom (`-Fc`), só do schema `academico` (`-n academico`).**

| Decisão | Por quê |
|---|---|
| Lógico (`pg_dump`) | Gera um arquivo com os comandos para recriar o schema e os dados. Restaura em outro servidor e em versão igual ou mais nova do PostgreSQL. O backup físico copia o servidor inteiro e não permite restaurar só um schema. |
| `-Fc` (custom) | Arquivo compactado, que o `pg_restore` lê e pode restaurar por partes. |
| `-n academico` | Só o schema do projeto. |
| Sem parar o sistema | O `pg_dump` lê uma "foto" consistente do banco sem bloquear quem está usando. |

**O que o backup traz:** tabelas e dados, tipos e domínios, constraints, índices, views, a
materialized view, procedures e funções, a trigger, os `GRANT` e as policies de RLS.

**O que NÃO traz:** os **papéis** (`aluno`, `secretaria`, `coordenacao`, `aluno_3`...). Papel
pertence ao servidor, e não ao banco. No desastre abaixo os papéis continuam lá, porque só o schema é
apagado. Num **servidor novo**, eles precisam ser recriados antes do `pg_restore` (rodando o
`07_seguranca.sql` ou com `pg_dumpall --roles-only`).

**Política recomendada:** backup diário de madrugada e antes de qualquer mudança no schema; guardar
7 dias; manter uma cópia **fora** do servidor (backup no mesmo disco do banco não protege contra falha
do disco); testar a restauração de tempos em tempos (backup nunca restaurado não é backup).

## 2. Passo a passo (testado no PostgreSQL 17)

O contêiner do ambiente oficial se chama `bd2_aluno_postgres`. Os comandos são para o Prompt de
Comando (CMD) ou o PowerShell. O arquivo do backup fica **dentro do contêiner**, em `/tmp`.

1. **Conferência ANTES** (pgAdmin): rode o `08_verificacao_backup.sql` e guarde o resultado (ou tire
   uma foto da tela). Na carga padrão: 300 matrículas, 36 índices, 6 policies.

2. **Backup:**
   ```
   docker exec bd2_aluno_postgres pg_dump -U bd2 -d matricula -n academico -Fc -f /tmp/academico.dump
   ```

3. **O desastre** (no pgAdmin ou no terminal): apaga o schema inteiro.
   ```
   docker exec bd2_aluno_postgres psql -U bd2 -d matricula -c "DROP SCHEMA academico CASCADE"
   ```
   No pgAdmin, `SELECT COUNT(*) FROM academico.tb_matricula;` agora dá erro: a tabela não existe.

4. **Restauração:**
   ```
   docker exec bd2_aluno_postgres pg_restore -U bd2 -d matricula /tmp/academico.dump
   ```

5. **Conferência DEPOIS:** rode o `08_verificacao_backup.sql` de novo. Os números têm de ser iguais aos
   do passo 1. E o RLS continua valendo:
   ```sql
   SET ROLE aluno_3;
   SELECT COUNT(*) FROM academico.tb_historico;   -- 4
   RESET ROLE;
   ```

No teste, as 24 linhas do `08` saíram **idênticas** antes e depois, e o `aluno_3` continuou vendo
só as 4 linhas dele. O dump tem cerca de 72 kB.

Para guardar uma cópia fora do contêiner:
```
docker cp bd2_aluno_postgres:/tmp/academico.dump .
```

> Se usar o **Git Bash**, rode `export MSYS_NO_PATHCONV=1` antes, senão ele troca o `/tmp` por um caminho do Windows.

## 3. Pelo pgAdmin (sem terminal)

1. Botão direito no schema `academico` > **Backup...**: formato **Custom**, dê um nome ao arquivo.
2. Query Tool: `DROP SCHEMA academico CASCADE;`
3. Botão direito no banco `matricula` > **Restore...**: formato **Custom**, escolha o arquivo.
4. Rode o `08_verificacao_backup.sql` e compare.

Esse caminho pela interface **não foi testado** aqui; o que foi testado é o da seção 2. Ensaiem antes
da apresentação.

## 4. Roteiro da demonstração ao vivo (~3 minutos)

1. `08_verificacao_backup.sql`: mostrar 300 matrículas e as 6 policies.
2. Backup (passo 2) e desastre (passo 3): mostrar que `tb_matricula` não existe mais.
3. Restauração (passo 4).
4. `08_verificacao_backup.sql` de novo: os mesmos números. E o `SET ROLE aluno_3` vendo 4 linhas.

## 5. Perguntas prováveis

- **Por que o `pg_dump` não leva os papéis?** Papel é do servidor, e não do banco. Por isso existe o
  `pg_dumpall --roles-only`.
- **O backup bloqueia o sistema?** Não. O `pg_dump` lê uma foto consistente do banco (MVCC) sem
  impedir as escritas.
- **E se eu precisar voltar para 15h37?** O backup lógico volta para o momento do dump. Para voltar a
  um instante qualquer seria preciso backup físico com arquivamento do WAL (PITR), que não foi feito
  aqui por ser desnecessário para um banco deste tamanho.
- **A materialized view volta com os dados?** Sim: o `pg_restore` recria a MV e roda o REFRESH dela no fim.
