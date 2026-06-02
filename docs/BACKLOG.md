# ProcessFlow — Backlog

Last updated: 2026-06-02

---

## In Progress / Next

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| 9 | **AppExchange packaging** — managed package com namespace `pflow`, security review, free listing | 🔴 Final milestone | Requires all items below to be done first |

---

## Done

- [x] Conditional branching on stages (AND/OR conditions)
- [x] HTTP/REST step type (Named Credentials, body/response mapping, retry)
- [x] Approval step type (native SF Approval Process integration)
- [x] Rollback + Execution history (stage rollback, FinalStatus, pflowHistory)
- [x] Concurrent execution control (per user+process+record)
- [x] Builder validation (empty stages, HTTP Named Credential, FieldsConfig JSON, Notification template)
- [x] Security hardening (stripInaccessible, XSS Chatter, targetRecord access, workitem fix)
- [x] Performance (N+1 eliminated, batch step loading, JSON versioning)
- [x] Reliability (Savepoint rollback, disconnectedCallback, error boundaries)
- [x] Operational (ExecutionCleanupJob, ProcessFlowJsonUtil schemas)
- [x] HTTP Retry real (up to 2 retries on 5xx/network errors)
- [x] Approval rejection tests (ApprovalControllerTest — 6 tests)
- [x] Restore execution state (inline resume prompt, positionAtStep fix)
- [x] Update Record dynamic lookup (Record ID input in Runner)
- [x] Email notification channel (Chatter or Email with recipient fallback)
- [x] Step-level conditional skip (SkipConditionsConfig__c + SkipConditionLogic__c)
