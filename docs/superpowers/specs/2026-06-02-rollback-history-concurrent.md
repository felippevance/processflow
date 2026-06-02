# Rollback + Execution History + Concurrent Execution Control — Design

**Date:** 2026-06-02

---

## Overview

Three related improvements to the ProcessFlow execution lifecycle:

1. **Rollback on failure** — when a step fails, automatically delete records created in the same stage
2. **Execution history** — preserve completed/failed executions and surface them in pflowHistory
3. **Concurrent execution control** — prevent the same user from running the same process for the same target record simultaneously

---

## Data Model Changes

### Execution__c — new fields

| Field | Type | Description |
|---|---|---|
| `TargetRecordId__c` | Text(18) | ID of the context record (optional, set by Runner when useRecordId=true) |
| `CompletedAt__c` | DateTime | Timestamp when execution completed, failed, or was cancelled |
| `FinalStatus__c` | Picklist: Completed / Failed / Cancelled | Set when execution ends; null = still in progress |

### Behavior change: Execution__c is no longer deleted on completion

Previously: `delete new Execution__c(Id = executionId)` on last step.

Now: update `FinalStatus__c = 'Completed'`, `CompletedAt__c = now()`.

A future scheduled job can archive/delete old completed executions.

---

## Rollback Design

When `executeWithData()` throws an exception on any step, `ProcessRunnerController.executeStep()` catches it, calls `RollbackService.rollbackStage(executionId, stageId)`, marks the execution as Failed, then re-throws the AuraHandledException to the LWC.

### RollbackService

New class `RollbackService` with one public method:

```apex
public static void rollbackStage(Id executionId, Id stageId)
```

Logic:
1. Query `Execution__c.ExecutionData__c` for the executionId
2. Parse `createdRecords` map from ExecutionData__c JSON — format: `{ stepId: { __id, __objectType, ... } }`
3. Query `Step__c` records for the stageId to get the set of stepIds belonging to this stage
4. Filter `createdRecords` to only entries whose key (stepId) is in the stage's steps
5. Group record Ids by `__objectType`
6. Delete each group — ignore errors if record already deleted
7. Update `Execution__c.FinalStatus__c = 'Failed'`, `CompletedAt__c = now()`

### Rollback scope

Only records created by ProcessFlow in the current stage are rolled back. Records from previous stages are preserved.

---

## Concurrent Execution Control

### Rule

A user cannot have two `In Progress` executions of the same process for the same `TargetRecordId__c`.

- If `TargetRecordId__c` is null (process without record context): allow only one in-progress execution per process per user.
- If `TargetRecordId__c` is set: allow only one in-progress execution per process + targetRecordId combination per user.

### Implementation

In `ProcessRunnerController.startExecution()`, add a check before insert:

```apex
List<Execution__c> existing = [
    SELECT Id FROM Execution__c
    WHERE Process__c = :processId
      AND User__c = :UserInfo.getUserId()
      AND FinalStatus__c = null
      AND TargetRecordId__c = :targetRecordId  // null-safe comparison
    WITH SECURITY_ENFORCED
    LIMIT 1
];
if (!existing.isEmpty()) {
    throw new AuraHandledException('A process execution is already in progress for this record.');
}
```

`startExecution` signature changes to accept optional `targetRecordId`:
```apex
public static Execution__c startExecution(Id processId, String targetRecordId)
```

### Runner LWC

The Runner passes `recordId` as `targetRecordId` when `useRecordId = true`. The existing error banner displays the conflict message if thrown.

---

## Execution History Design

### Execution__c query

New method `getExecutionHistory(Id processId)` in `ProcessRunnerController`:

```apex
SELECT Id, Name, FinalStatus__c, StartedAt__c, CompletedAt__c,
       TargetRecordId__c, User__r.Name
FROM Execution__c
WHERE Process__c = :processId
WITH SECURITY_ENFORCED
ORDER BY StartedAt__c DESC
LIMIT 100
```

Only returns executions with `FinalStatus__c != null` (completed/failed/cancelled).

### ExecutionLog__c query per execution

New method `getLogsForExecution(Id executionId)`:

```apex
SELECT Id, Step__r.Name, Status__c, ExecutedAt__c, ErrorMessage__c
FROM ExecutionLog__c
WHERE Execution__c = :executionId
WITH SECURITY_ENFORCED
ORDER BY ExecutedAt__c ASC
```

### pflowHistory LWC refactor

Replace the current step-centric datatable with an execution-centric view:

**Top level:** `lightning-datatable` of executions — columns: Status (with color), Started At, Completed At, Target Record, User.

**Expandable row:** clicking a row loads and displays the step logs for that execution inline (lazy loaded via `getLogsForExecution`).

---

## Components Affected

| Component | Change |
|---|---|
| `Execution__c` | +3 fields: TargetRecordId__c, CompletedAt__c, FinalStatus__c |
| `ProcessExecutionEngine` | Remove `delete exec` on last step; update FinalStatus__c/CompletedAt__c instead |
| `ProcessRunnerController` | Update startExecution() signature + concurrent check; add getExecutionHistory() + getLogsForExecution(); update cancelExecution() to set FinalStatus__c=Cancelled |
| `RollbackService` | New class — rollback stage records on failure |
| `ProcessRunnerController.executeStep()` | Catch engine exception, call RollbackService, re-throw |
| `pflowRunner` | Pass targetRecordId to startExecution; update init() to cancel stale executions by FinalStatus__c=null only |
| `pflowHistory` | Refactor to show executions with expandable step logs |
| `ProcessFlow_Admin` PS | +3 new field permissions |
