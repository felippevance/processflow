# ProcessFlow — Backlog

Last updated: 2026-06-02

---

## In Progress / Next

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| ~~1~~ | ~~**XSS Chatter sanitization** — `escapeSingleQuotes` não previne HTML/script em `messageTemplate`; precisa sanitizar completamente | 🔴 High (security before AppExchange) | `ProcessExecutionEngine.sendNotification()` |
| 2 | **HTTP Retry real** — flag `retry=true` só adiciona header `X-Retry-Enabled`; sem retry real no Apex para falhas transitórias | 🟠 High | `HttpRequestExecutor.execute()` |
| 3 | **Testes do fluxo de rejeição de aprovação** — `pollApprovalStatus` rejection path não tem cobertura de testes | 🟠 High | `pflowRunner.js` |

---

## Backlog (próximas sprints)

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| 4 | **Restaurar estado de execução** — Runner sempre começa do zero; não restaura campos já preenchidos se usuário recarregar | 🟡 Medium | `pflowRunner.js init()` |
| 5 | **Validação server-side profunda** — `validatePayload` valida campos obrigatórios mas não integridade do JSON em `FieldsConfig__c` | 🟡 Medium | `ProcessBuilderController.validatePayload()` |
| 6 | **Update Record com lookup dinâmico** — step de Update exige que o usuário saiba o ID; poderia ter um lookup field no formulário | 🟡 Medium | Builder + Runner |
| 7 | **Notificação por email** — além de Chatter, enviar via `Messaging.SingleEmailMessage` | 🟡 Medium | New step type or option |
| 8 | **Conditional branching em steps** — condições hoje só por Stage; poderia ter por Step também | 🟢 Low | Extend ConditionEvaluator |

---

## AppExchange

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| 9 | **Managed package** — namespace `pflow`, security review, free listing | 🔴 Final milestone | Requires all High items done first |

---

## Done (reference)

- [x] Conditional branching on stages
- [x] HTTP/REST step type
- [x] Approval step type
- [x] Rollback + Execution history
- [x] Concurrent execution control
- [x] Builder validation
- [x] Security hardening (stripInaccessible, workitem fix, targetRecord access)
- [x] Performance (N+1 eliminated, batch step loading, JSON versioning)
- [x] Reliability (Savepoint rollback, disconnectedCallback, error boundaries)
- [x] Operational (ExecutionCleanupJob, ProcessFlowJsonUtil schemas)
