# Approval Step Type — Design

**Date:** 2026-06-02

---

## Overview

Adds native Salesforce Approval Process integration to ProcessFlow. When a `Create Record` step has `RequiresApproval__c = true`, the Engine submits the created record to a configured `ApprovalProcess` and pauses execution until the approver responds. Approved → continues. Rejected → optional rejection stage or process failure.

---

## Data Model

### Step__c — new fields

| Field | Type | Description |
|---|---|---|
| `RequiresApproval__c` | Checkbox (default false) | If true, the created record is submitted to an approval process before advancing |
| `ApprovalProcessName__c` | Text(80) | Developer name of the ApprovalProcess to submit to |
| `RejectionStageId__c` | Lookup → Stage__c | Stage to execute if approval is rejected (optional) |
| `OnRejection__c` | Picklist: Stop / Execute Stage | What to do when rejected |

### Execution__c — new fields

| Field | Type | Description |
|---|---|---|
| `PendingApprovalId__c` | Text(18) | ProcessInstance Id awaiting response |
| `PendingApprovalRecordId__c` | Text(18) | Id of the record submitted for approval |

---

## Execution Flow

```
Runner clicks Next on a Create Record step with RequiresApproval=true
  └─ ProcessExecutionEngine.createRecord() creates the record
  └─ ApprovalService.submit(recordId, approvalProcessName, executionId)
       └─ Approval.ProcessSubmitRequest → submits to native ApprovalProcess
       └─ Saves ProcessInstance.Id to Execution__c.PendingApprovalId__c
       └─ Saves recordId to Execution__c.PendingApprovalRecordId__c
  └─ Engine returns StepResult with isWaitingApproval = true
  └─ Runner shows "Awaiting approval..." screen with 5s polling

Polling (Runner LWC calls ApprovalController.checkApprovalStatus(executionId))
  └─ Query ProcessInstance WHERE TargetObjectId = PendingApprovalRecordId__c AND Status != 'Pending'
  └─ If Approved:
       └─ Clear PendingApprovalId__c / PendingApprovalRecordId__c
       └─ Runner advances to next step normally
  └─ If Rejected:
       └─ If RejectionStageId__c configured → Runner navigates to that stage
       └─ If not → Execution marked Failed + RollbackService.rollbackStage()
  └─ If still Pending → Runner continues polling
```

---

## New Apex Classes

### ApprovalService

```apex
public with sharing class ApprovalService {

    public class ApprovalResult {
        @AuraEnabled public String status { get; set; }   // Pending / Approved / Rejected
        @AuraEnabled public String instanceId { get; set; }
    }

    // Submit a record to an approval process and store the instance on the execution
    public static ApprovalResult submit(Id recordId, String approvalProcessName, Id executionId) {
        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
        req.setObjectId(recordId);
        req.setProcessDefinitionNameOrId(approvalProcessName);
        req.setSubmitterId(UserInfo.getUserId());
        Approval.ProcessResult result = Approval.process(req);

        // Store pending approval info on execution
        Execution__c exec = new Execution__c(
            Id = executionId,
            PendingApprovalId__c = result.getInstanceId(),
            PendingApprovalRecordId__c = recordId
        );
        update exec;

        ApprovalResult ar = new ApprovalResult();
        ar.status     = 'Pending';
        ar.instanceId = result.getInstanceId();
        return ar;
    }

    // Check the current status of a pending approval
    public static ApprovalResult checkStatus(Id executionId) {
        Execution__c exec = [
            SELECT PendingApprovalId__c, PendingApprovalRecordId__c
            FROM Execution__c WHERE Id = :executionId WITH SECURITY_ENFORCED
        ];
        if (String.isBlank(exec.PendingApprovalId__c)) {
            ApprovalResult ar = new ApprovalResult();
            ar.status = 'Approved'; // no pending = already resolved
            return ar;
        }
        List<ProcessInstance> instances = [
            SELECT Id, Status FROM ProcessInstance
            WHERE Id = :exec.PendingApprovalId__c
            LIMIT 1
        ];
        ApprovalResult ar = new ApprovalResult();
        ar.instanceId = exec.PendingApprovalId__c;
        ar.status     = instances.isEmpty() ? 'Approved' : instances[0].Status;
        return ar;
    }
}
```

### ApprovalController

```apex
@AuraEnabled methods:
- getApprovalProcesses()         — query ProcessDefinition WHERE Type='Approval' ORDER BY Name
- checkApprovalStatus(executionId) — delegates to ApprovalService.checkStatus()
- cancelApproval(executionId)    — recalls the approval + marks execution Failed
```

---

## ProcessExecutionEngine Changes

In `createRecord()`, after inserting the record, check if `RequiresApproval__c = true` on the step. If so, call `ApprovalService.submit()` and set `StepResult.isWaitingApproval = true`.

The step's `fieldsConfig` must carry `requiresApproval`, `approvalProcessName`, `onRejection`, and `rejectionStageId` from the Builder.

---

## pflowRunner LWC Changes

### New state

```javascript
@track isWaitingApproval = false;
@track approvalPollingInterval = null;
```

### New screen

When `isWaitingApproval = true`, show:
```
⏳ Awaiting Approval
The record has been submitted for approval.
This page will update automatically.
[Cancel Process]
```

### Polling

Every 5 seconds, call `checkApprovalStatus`. On Approved: clear flag, advance. On Rejected: navigate to rejection stage or show failure.

---

## pflowBuilder LWC Changes

In Screen 3, when step type is `Create Record`, show below the field picker:

```
[ ] Requires Approval before advancing
    (if checked):
    Approval Process: [ dropdown of ApprovalProcesses ]
    On Rejection:     [ Stop Process | Execute Stage ]
    Rejection Stage:  [ dropdown of stages in current process ] (if Execute Stage)
```

`getApprovalProcesses()` loaded lazily when checkbox is ticked.

---

## pflowViewer LWC Changes

Steps with `RequiresApproval__c = true` show a badge "⏳ Approval Required" below the step name.

---

## Components Affected

| Component | Change |
|---|---|
| `Step__c` | +4 fields: RequiresApproval__c, ApprovalProcessName__c, OnRejection__c, RejectionStageId__c |
| `Execution__c` | +2 fields: PendingApprovalId__c, PendingApprovalRecordId__c |
| `ApprovalService` | New class — submit + checkStatus |
| `ApprovalController` | New class — AuraEnabled wrappers + getApprovalProcesses |
| `ProcessExecutionEngine` | createRecord() checks RequiresApproval, calls ApprovalService |
| `ProcessRunnerController` | executeStep returns isWaitingApproval flag |
| `ProcessBuilderController` | saveProcess persists approval fields; getApprovalProcesses added |
| `pflowRunner` | Waiting approval screen + polling |
| `pflowBuilder` | Approval panel in Screen 3 Create Record steps |
| `pflowViewer` | Badge on approval steps |
| `ProcessFlow_Admin` PS | +6 new field permissions |
