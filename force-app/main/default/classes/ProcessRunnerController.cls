public with sharing class ProcessRunnerController {

    public class StageWithSteps {
        @AuraEnabled public Stage__c stage { get; set; }
        @AuraEnabled public List<Step__c> steps { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<Process__c> getActiveProcesses() {
        return [
            SELECT Id, Name, Description__c
            FROM Process__c
            WHERE IsActive__c = true AND IsCurrentVersion__c = true
            WITH SECURITY_ENFORCED
            ORDER BY Name
        ];
    }

    @AuraEnabled
    public static Execution__c getOpenExecution() {
        List<Execution__c> execs = [
            SELECT Id, Process__c, Process__r.Name,
                   Status__c, CurrentStage__c, CurrentStep__c,
                   ExecutionData__c
            FROM Execution__c
            WHERE User__c = :UserInfo.getUserId()
              AND FinalStatus__c = null
            WITH SECURITY_ENFORCED
            ORDER BY StartedAt__c DESC
            LIMIT 1
        ];
        return execs.isEmpty() ? null : execs[0];
    }

    @AuraEnabled
    public static Execution__c getOpenExecutionForProcess(Id processId) {
        List<Execution__c> execs = [
            SELECT Id, Process__c, Process__r.Name,
                   Status__c, CurrentStage__c, CurrentStep__c,
                   ExecutionData__c
            FROM Execution__c
            WHERE User__c = :UserInfo.getUserId()
              AND FinalStatus__c = null
              AND Process__c = :processId
            WITH SECURITY_ENFORCED
            ORDER BY StartedAt__c DESC
            LIMIT 1
        ];
        return execs.isEmpty() ? null : execs[0];
    }

    @AuraEnabled
    public static Execution__c startExecution(Id processId, String targetRecordId) {
        // Concurrent execution check
        List<Execution__c> existing = [
            SELECT Id FROM Execution__c
            WHERE Process__c = :processId
              AND User__c = :UserInfo.getUserId()
              AND FinalStatus__c = null
              AND TargetRecordId__c = :targetRecordId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            throw new AuraHandledException(
                'A process execution is already in progress' +
                (String.isNotBlank(targetRecordId) ? ' for this record.' : '.')
            );
        }

        Stage__c firstStage = [
            SELECT Id FROM Stage__c
            WHERE Process__c = :processId
            WITH SECURITY_ENFORCED
            ORDER BY Sequence__c ASC
            LIMIT 1
        ];
        Step__c firstStep = [
            SELECT Id FROM Step__c
            WHERE Stage__c = :firstStage.Id
            WITH SECURITY_ENFORCED
            ORDER BY Sequence__c ASC
            LIMIT 1
        ];

        Execution__c exec = new Execution__c(
            Process__c        = processId,
            User__c           = UserInfo.getUserId(),
            StartedAt__c      = System.now(),
            Status__c         = 'In Progress',
            CurrentStage__c   = firstStage.Id,
            CurrentStep__c    = firstStep.Id,
            TargetRecordId__c = targetRecordId,
            ExecutionData__c  = '{}'
        );
        insert exec;
        return exec;
    }

    @AuraEnabled
    public static List<StageWithSteps> getProcessSteps(Id processId) {
        List<Stage__c> stages = [
            SELECT Id, Name, Sequence__c, Process__r.Name,
                   ConditionLogic__c, ConditionsConfig__c
            FROM Stage__c
            WHERE Process__c = :processId
            WITH SECURITY_ENFORCED
            ORDER BY Sequence__c ASC
        ];

        List<Id> stageIds = new List<Id>();
        for (Stage__c s : stages) { stageIds.add(s.Id); }

        List<Step__c> steps = [
            SELECT Id, Name, Sequence__c, Stage__c,
                   Type__c, TargetObject__c, FieldsConfig__c, IsRequired__c,
                   RequiresApproval__c, ApprovalProcessName__c,
                   SkipConditionsConfig__c, SkipConditionLogic__c
            FROM Step__c
            WHERE Stage__c IN :stageIds
            WITH SECURITY_ENFORCED
            ORDER BY Stage__r.Sequence__c ASC, Sequence__c ASC
        ];

        Map<Id, List<Step__c>> stepsByStage = new Map<Id, List<Step__c>>();
        for (Step__c st : steps) {
            if (!stepsByStage.containsKey(st.Stage__c)) {
                stepsByStage.put(st.Stage__c, new List<Step__c>());
            }
            stepsByStage.get(st.Stage__c).add(st);
        }

        List<StageWithSteps> result = new List<StageWithSteps>();
        for (Stage__c stage : stages) {
            StageWithSteps sws = new StageWithSteps();
            sws.stage = stage;
            sws.steps = stepsByStage.containsKey(stage.Id) ? stepsByStage.get(stage.Id) : new List<Step__c>();
            result.add(sws);
        }
        return result;
    }

    public class NextStageResult {
        @AuraEnabled public Stage__c stage          { get; set; }
        @AuraEnabled public List<Step__c> steps     { get; set; }
        @AuraEnabled public Boolean processComplete { get; set; }
    }

    @AuraEnabled
    public static NextStageResult getNextStage(Id executionId, Id currentStageId) {
        Execution__c exec = [
            SELECT Id, Process__c, ExecutionData__c
            FROM Execution__c WHERE Id = :executionId WITH SECURITY_ENFORCED
        ];

        Decimal currentSeq = [
            SELECT Sequence__c FROM Stage__c WHERE Id = :currentStageId WITH SECURITY_ENFORCED
        ].Sequence__c;

        List<Stage__c> remainingStages = [
            SELECT Id, Name, Sequence__c, ConditionLogic__c, ConditionsConfig__c
            FROM Stage__c
            WHERE Process__c = :exec.Process__c
              AND Sequence__c > :currentSeq
            WITH SECURITY_ENFORCED
            ORDER BY Sequence__c ASC
        ];

        String execData = exec.ExecutionData__c;

        // Batch load all steps for all remaining stages — avoids N+1 queries
        List<Id> remainingStageIds = new List<Id>();
        for (Stage__c s : remainingStages) remainingStageIds.add(s.Id);

        Map<Id, List<Step__c>> stepsByStage = new Map<Id, List<Step__c>>();
        if (!remainingStageIds.isEmpty()) {
            for (Step__c st : [
                SELECT Id, Name, Sequence__c, Stage__c,
                       Type__c, TargetObject__c, FieldsConfig__c, IsRequired__c,
                       RequiresApproval__c, ApprovalProcessName__c,
                       SkipConditionsConfig__c, SkipConditionLogic__c
                FROM Step__c
                WHERE Stage__c IN :remainingStageIds
                WITH SECURITY_ENFORCED
                ORDER BY Stage__r.Sequence__c ASC, Sequence__c ASC
            ]) {
                if (!stepsByStage.containsKey(st.Stage__c)) {
                    stepsByStage.put(st.Stage__c, new List<Step__c>());
                }
                stepsByStage.get(st.Stage__c).add(st);
            }
        }

        for (Stage__c candidate : remainingStages) {
            Boolean passes = ConditionEvaluator.evaluate(
                candidate.ConditionsConfig__c,
                candidate.ConditionLogic__c,
                execData
            );
            if (passes) {
                List<Step__c> steps = stepsByStage.containsKey(candidate.Id)
                    ? stepsByStage.get(candidate.Id)
                    : new List<Step__c>();
                exec.CurrentStage__c = candidate.Id;
                exec.CurrentStep__c  = steps.isEmpty() ? null : steps[0].Id;
                update exec;

                NextStageResult res = new NextStageResult();
                res.stage           = candidate;
                res.steps           = steps;
                res.processComplete = false;
                return res;
            }
        }

        // No more stages pass — process complete
        exec.FinalStatus__c = 'Completed';
        exec.CompletedAt__c = System.now();
        update exec;
        NextStageResult res = new NextStageResult();
        res.processComplete = true;
        return res;
    }

    @AuraEnabled
    public static ProcessExecutionEngine.StepResult executeStep(
        Id stepId, String stepType, String targetObject, String fieldsConfig,
        String inputDataJson, Id executionId, Boolean isLastStep
    ) {
        String safeFieldsConfig = String.isBlank(fieldsConfig) ? '[]' : fieldsConfig;
        String safeInputJson    = String.isBlank(inputDataJson) ? '{}' : inputDataJson;

        Map<String, Object> inputData = (Map<String, Object>) JSON.deserializeUntyped(safeInputJson);
        if (isLastStep) inputData.put('isLastStep', true);

        ProcessExecutionEngine.StepResult result;
        String errorMsg = null;

        try {
            result = ProcessExecutionEngine.executeWithData(stepId, stepType, targetObject, safeFieldsConfig, inputData, executionId);
        } catch (Exception e) {
            errorMsg = e.getMessage();
            writeLog(executionId, stepId, 'Error', safeInputJson, errorMsg);
            // Rollback records created in the current stage
            try {
                Step__c failedStep = [SELECT Stage__c FROM Step__c WHERE Id = :stepId WITH SECURITY_ENFORCED];
                RollbackService.rollbackStage(executionId, failedStep.Stage__c);
            } catch (Exception rollbackEx) {
                System.debug('Rollback failed: ' + rollbackEx.getMessage());
            }
            throw new AuraHandledException(e.getMessage());
        }

        // Log success
        writeLog(executionId, stepId, 'Success', safeInputJson, null);
        return result;
    }

    private static void writeLog(Id executionId, Id stepId, String status, String inputData, String errorMessage) {
        try {
            ExecutionLog__c log = new ExecutionLog__c(
                Execution__c    = executionId,
                Step__c         = stepId,
                Status__c       = status,
                InputData__c    = inputData?.left(32768),
                ErrorMessage__c = errorMessage?.left(32768),
                ExecutedAt__c   = System.now()
            );
            insert log;
        } catch (Exception e) {
            // Never let logging failure break the main flow
            System.debug('ExecutionLog write failed: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static List<ExecutionLog__c> getExecutionLogs(Id processId) {
        return [
            SELECT Id, Name, Step__c, Step__r.Name, Status__c,
                   InputData__c, ErrorMessage__c, ExecutedAt__c,
                   Execution__c, Execution__r.User__r.Name
            FROM ExecutionLog__c
            WHERE Execution__r.Process__c = :processId
            WITH SECURITY_ENFORCED
            ORDER BY ExecutedAt__c DESC
            LIMIT 200
        ];
    }

    @AuraEnabled
    public static List<Execution__c> getExecutionHistory(Id processId) {
        return [
            SELECT Id, Name, FinalStatus__c, StartedAt__c, CompletedAt__c,
                   TargetRecordId__c, User__r.Name
            FROM Execution__c
            WHERE Process__c = :processId
              AND FinalStatus__c != null
            WITH SECURITY_ENFORCED
            ORDER BY StartedAt__c DESC
            LIMIT 100
        ];
    }

    @AuraEnabled
    public static List<ExecutionLog__c> getLogsForExecution(Id executionId) {
        return [
            SELECT Id, Step__r.Name, Status__c, ExecutedAt__c, ErrorMessage__c
            FROM ExecutionLog__c
            WHERE Execution__c = :executionId
            WITH SECURITY_ENFORCED
            ORDER BY ExecutedAt__c ASC
        ];
    }

    @AuraEnabled
    public static Boolean checkSkipConditions(Id stepId, Id executionId) {
        Step__c step = [
            SELECT Id, SkipConditionsConfig__c, SkipConditionLogic__c
            FROM Step__c WHERE Id = :stepId WITH SECURITY_ENFORCED
        ];
        if (String.isBlank(step.SkipConditionsConfig__c)) return false;

        Execution__c exec = [
            SELECT ExecutionData__c FROM Execution__c WHERE Id = :executionId WITH SECURITY_ENFORCED
        ];
        return ConditionEvaluator.evaluate(
            step.SkipConditionsConfig__c,
            step.SkipConditionLogic__c,
            exec.ExecutionData__c
        );
    }

    @AuraEnabled
    public static void cancelExecution(Id executionId) {
        Execution__c exec = [
            SELECT Id FROM Execution__c WHERE Id = :executionId WITH SECURITY_ENFORCED
        ];
        exec.FinalStatus__c = 'Cancelled';
        exec.CompletedAt__c = System.now();
        update exec;
    }
}
