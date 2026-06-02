@IsTest
private class ProcessRunnerControllerTest {

    // ─── Test Setup ───────────────────────────────────────────────────────────

    @TestSetup
    static void setup() {
        Process__c proc = new Process__c(
            Name = 'Test',
            IsActive__c = true,
            Version__c = 1,
            IsCurrentVersion__c = true,
            Description__c = 'Test process'
        );
        insert proc;

        Stage__c s1 = new Stage__c(Name = 'Stage 1', Sequence__c = 1, Process__c = proc.Id);
        Stage__c s2 = new Stage__c(
            Name = 'Stage 2',
            Sequence__c = 2,
            Process__c = proc.Id,
            ConditionLogic__c = 'AND',
            ConditionsConfig__c = '[{"source":"fieldValue","field":"Status","operator":"equals","value":"Active"}]'
        );
        insert new List<Stage__c>{ s1, s2 };

        Step__c st1 = new Step__c(
            Name = 'Step 1',
            Sequence__c = 1,
            Stage__c = s1.Id,
            Type__c = 'Notification',
            FieldsConfig__c = '{"messageTemplate":"Test"}'
        );
        Step__c st2 = new Step__c(
            Name = 'Step 2',
            Sequence__c = 1,
            Stage__c = s2.Id,
            Type__c = 'Notification',
            FieldsConfig__c = '{"messageTemplate":"Test 2"}'
        );
        insert new List<Step__c>{ st1, st2 };
    }

    // ─── Helper ───────────────────────────────────────────────────────────────

    private static Execution__c createExecution(Id processId, Id stageId, Id stepId, String finalStatus) {
        Execution__c exec = new Execution__c(
            Process__c       = processId,
            User__c          = UserInfo.getUserId(),
            StartedAt__c     = System.now(),
            Status__c        = 'In Progress',
            CurrentStage__c  = stageId,
            CurrentStep__c   = stepId,
            ExecutionData__c = '{}',
            FinalStatus__c   = finalStatus
        );
        insert exec;
        return exec;
    }

    // ─── getActiveProcesses ───────────────────────────────────────────────────

    @IsTest
    static void testGetActiveProcesses_returnsActiveCurrentOnly() {
        // Add inactive and non-current versions to make sure filtering works
        Process__c inactive = new Process__c(Name = 'Inactive', IsActive__c = false, IsCurrentVersion__c = true);
        Process__c oldVersion = new Process__c(Name = 'Old Version', IsActive__c = true, IsCurrentVersion__c = false);
        insert new List<Process__c>{ inactive, oldVersion };

        Test.startTest();
        List<Process__c> results = ProcessRunnerController.getActiveProcesses();
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should only return active+current processes');
        System.assertEquals('Test', results[0].Name);
    }

    @IsTest
    static void testGetActiveProcesses_emptyWhenNone() {
        // Delete setup process to test empty state
        delete [SELECT Id FROM Process__c];

        Test.startTest();
        List<Process__c> results = ProcessRunnerController.getActiveProcesses();
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return empty list when no active processes');
    }

    // ─── getOpenExecution ─────────────────────────────────────────────────────

    @IsTest
    static void testGetOpenExecution_returnsInProgress() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];
        Stage__c stage = [SELECT Id FROM Stage__c WHERE Name = 'Stage 1' LIMIT 1];
        Step__c step = [SELECT Id FROM Step__c WHERE Name = 'Step 1' LIMIT 1];

        createExecution(proc.Id, stage.Id, step.Id, null);

        Test.startTest();
        Execution__c result = ProcessRunnerController.getOpenExecution();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should find the open execution');
        System.assertEquals('In Progress', result.Status__c);
    }

    @IsTest
    static void testGetOpenExecution_returnsNullWhenNone() {
        Test.startTest();
        Execution__c result = ProcessRunnerController.getOpenExecution();
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null when no open execution exists');
    }

    @IsTest
    static void testGetOpenExecution_ignoresCompletedExecutions() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];
        Stage__c stage = [SELECT Id FROM Stage__c WHERE Name = 'Stage 1' LIMIT 1];
        Step__c step = [SELECT Id FROM Step__c WHERE Name = 'Step 1' LIMIT 1];

        createExecution(proc.Id, stage.Id, step.Id, 'Completed');

        Test.startTest();
        Execution__c result = ProcessRunnerController.getOpenExecution();
        Test.stopTest();

        System.assertEquals(null, result, 'Should not return completed executions');
    }

    // ─── getOpenExecutionForProcess ───────────────────────────────────────────

    @IsTest
    static void testGetOpenExecutionForProcess_returnsMatchingProcess() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];
        Stage__c stage = [SELECT Id FROM Stage__c WHERE Name = 'Stage 1' LIMIT 1];
        Step__c step = [SELECT Id FROM Step__c WHERE Name = 'Step 1' LIMIT 1];

        createExecution(proc.Id, stage.Id, step.Id, null);

        Test.startTest();
        Execution__c result = ProcessRunnerController.getOpenExecutionForProcess(proc.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should find open execution for the process');
        System.assertEquals(proc.Id, result.Process__c);
    }

    @IsTest
    static void testGetOpenExecutionForProcess_returnsNullForOtherProcess() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];
        Stage__c stage = [SELECT Id FROM Stage__c WHERE Name = 'Stage 1' LIMIT 1];
        Step__c step = [SELECT Id FROM Step__c WHERE Name = 'Step 1' LIMIT 1];

        createExecution(proc.Id, stage.Id, step.Id, null);

        // Create another process that has no execution
        Process__c anotherProc = new Process__c(Name = 'Other', IsActive__c = true, IsCurrentVersion__c = true);
        insert anotherProc;

        Test.startTest();
        Execution__c result = ProcessRunnerController.getOpenExecutionForProcess(anotherProc.Id);
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null for different process');
    }

    // ─── startExecution ───────────────────────────────────────────────────────

    @IsTest
    static void testStartExecution_createsExecutionRecord() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];
        Stage__c stage1 = [SELECT Id FROM Stage__c WHERE Name = 'Stage 1' LIMIT 1];
        Step__c step1 = [SELECT Id FROM Step__c WHERE Name = 'Step 1' LIMIT 1];

        Test.startTest();
        Execution__c exec = ProcessRunnerController.startExecution(proc.Id, null);
        Test.stopTest();

        System.assertNotEquals(null, exec.Id, 'Execution should have an Id');
        System.assertEquals('In Progress', exec.Status__c, 'Status should be In Progress');
        System.assertEquals(proc.Id, exec.Process__c, 'Should be linked to process');
        System.assertEquals(stage1.Id, exec.CurrentStage__c, 'Should set first stage');
        System.assertEquals(step1.Id, exec.CurrentStep__c, 'Should set first step');
    }

    @IsTest
    static void testStartExecution_withTargetRecord() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];
        // Use proc.Id as a placeholder target record Id (any valid Salesforce Id)
        String targetId = proc.Id;

        Test.startTest();
        Execution__c exec = ProcessRunnerController.startExecution(proc.Id, targetId);
        Test.stopTest();

        System.assertEquals(targetId, exec.TargetRecordId__c, 'TargetRecordId should be set');
    }

    @IsTest
    static void testStartExecution_blocksConcurrentSameRecord() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];
        Stage__c stage = [SELECT Id FROM Stage__c WHERE Name = 'Stage 1' LIMIT 1];
        Step__c step = [SELECT Id FROM Step__c WHERE Name = 'Step 1' LIMIT 1];

        String targetId = proc.Id;
        createExecution(proc.Id, stage.Id, step.Id, null);
        // Manually set TargetRecordId on the execution
        Execution__c exec = [SELECT Id FROM Execution__c WHERE Process__c = :proc.Id LIMIT 1];
        exec.TargetRecordId__c = targetId;
        update exec;

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            ProcessRunnerController.startExecution(proc.Id, targetId);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Should throw when concurrent execution exists for same record');
    }

    @IsTest
    static void testStartExecution_blocksConcurrentNoRecord() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];
        Stage__c stage = [SELECT Id FROM Stage__c WHERE Name = 'Stage 1' LIMIT 1];
        Step__c step = [SELECT Id FROM Step__c WHERE Name = 'Step 1' LIMIT 1];

        // Create an open execution with null targetRecordId
        Execution__c exec = new Execution__c(
            Process__c       = proc.Id,
            User__c          = UserInfo.getUserId(),
            StartedAt__c     = System.now(),
            Status__c        = 'In Progress',
            CurrentStage__c  = stage.Id,
            CurrentStep__c   = step.Id,
            ExecutionData__c = '{}'
        );
        insert exec;

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            ProcessRunnerController.startExecution(proc.Id, null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Should throw when concurrent execution without record exists');
    }

    // ─── getProcessSteps ──────────────────────────────────────────────────────

    @IsTest
    static void testGetProcessSteps_returnsOrderedStagesAndSteps() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];

        Test.startTest();
        List<ProcessRunnerController.StageWithSteps> result = ProcessRunnerController.getProcessSteps(proc.Id);
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Should return 2 stages');
        System.assertEquals('Stage 1', result[0].stage.Name, 'First stage should be Stage 1');
        System.assertEquals('Stage 2', result[1].stage.Name, 'Second stage should be Stage 2');
        System.assertEquals(1, result[0].steps.size(), 'Stage 1 should have 1 step');
        System.assertEquals(1, result[1].steps.size(), 'Stage 2 should have 1 step');
    }

    @IsTest
    static void testGetProcessSteps_emptyStageHasNoSteps() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];
        Stage__c emptyStage = new Stage__c(Name = 'Empty Stage', Sequence__c = 3, Process__c = proc.Id);
        insert emptyStage;

        Test.startTest();
        List<ProcessRunnerController.StageWithSteps> result = ProcessRunnerController.getProcessSteps(proc.Id);
        Test.stopTest();

        // Find the empty stage entry
        ProcessRunnerController.StageWithSteps emptyEntry = null;
        for (ProcessRunnerController.StageWithSteps sws : result) {
            if (sws.stage.Name == 'Empty Stage') {
                emptyEntry = sws;
            }
        }
        System.assertNotEquals(null, emptyEntry, 'Empty stage should be in result');
        System.assertEquals(0, emptyEntry.steps.size(), 'Empty stage should have 0 steps');
    }

    // ─── getNextStage ─────────────────────────────────────────────────────────

    @IsTest
    static void testGetNextStage_advancesToNextPassingStage() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];
        Stage__c stage1 = [SELECT Id FROM Stage__c WHERE Name = 'Stage 1' LIMIT 1];
        Stage__c stage2 = [SELECT Id FROM Stage__c WHERE Name = 'Stage 2' LIMIT 1];
        Step__c step1 = [SELECT Id FROM Step__c WHERE Name = 'Step 1' LIMIT 1];

        // Stage 2 has condition: Status == Active. Provide matching execData.
        Execution__c exec = new Execution__c(
            Process__c       = proc.Id,
            User__c          = UserInfo.getUserId(),
            StartedAt__c     = System.now(),
            Status__c        = 'In Progress',
            CurrentStage__c  = stage1.Id,
            CurrentStep__c   = step1.Id,
            ExecutionData__c = '{"fieldValues":{"Status":"Active"}}'
        );
        insert exec;

        Test.startTest();
        ProcessRunnerController.NextStageResult result = ProcessRunnerController.getNextStage(exec.Id, stage1.Id);
        Test.stopTest();

        System.assertEquals(false, result.processComplete, 'Process should not be complete yet');
        System.assertEquals(stage2.Id, result.stage.Id, 'Should advance to Stage 2');
        System.assertEquals(1, result.steps.size(), 'Stage 2 should have 1 step');
    }

    @IsTest
    static void testGetNextStage_completesWhenNoStagesPasses() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];
        Stage__c stage1 = [SELECT Id FROM Stage__c WHERE Name = 'Stage 1' LIMIT 1];
        Step__c step1 = [SELECT Id FROM Step__c WHERE Name = 'Step 1' LIMIT 1];

        // Stage 2 requires Status=Active — use different value so it won't pass
        Execution__c exec = new Execution__c(
            Process__c       = proc.Id,
            User__c          = UserInfo.getUserId(),
            StartedAt__c     = System.now(),
            Status__c        = 'In Progress',
            CurrentStage__c  = stage1.Id,
            CurrentStep__c   = step1.Id,
            ExecutionData__c = '{"fieldValues":{"Status":"Inactive"}}'
        );
        insert exec;

        Test.startTest();
        ProcessRunnerController.NextStageResult result = ProcessRunnerController.getNextStage(exec.Id, stage1.Id);
        Test.stopTest();

        System.assertEquals(true, result.processComplete, 'Process should be complete when no stages pass');

        // Verify execution is marked completed
        Execution__c updated = [SELECT FinalStatus__c FROM Execution__c WHERE Id = :exec.Id];
        System.assertEquals('Completed', updated.FinalStatus__c);
    }

    @IsTest
    static void testGetNextStage_completesFromLastStage() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];
        Stage__c stage2 = [SELECT Id FROM Stage__c WHERE Name = 'Stage 2' LIMIT 1];
        Step__c step2 = [SELECT Id FROM Step__c WHERE Name = 'Step 2' LIMIT 1];

        Execution__c exec = new Execution__c(
            Process__c       = proc.Id,
            User__c          = UserInfo.getUserId(),
            StartedAt__c     = System.now(),
            Status__c        = 'In Progress',
            CurrentStage__c  = stage2.Id,
            CurrentStep__c   = step2.Id,
            ExecutionData__c = '{}'
        );
        insert exec;

        Test.startTest();
        ProcessRunnerController.NextStageResult result = ProcessRunnerController.getNextStage(exec.Id, stage2.Id);
        Test.stopTest();

        System.assertEquals(true, result.processComplete, 'Should complete when called from last stage');
    }

    // ─── checkSkipConditions ──────────────────────────────────────────────────

    @IsTest
    static void testCheckSkipConditions_returnsFalseWhenNoConditions() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];
        Stage__c stage1 = [SELECT Id FROM Stage__c WHERE Name = 'Stage 1' LIMIT 1];
        Step__c step1 = [SELECT Id FROM Step__c WHERE Name = 'Step 1' LIMIT 1];
        // step1 has no SkipConditionsConfig__c

        Execution__c exec = createExecution(proc.Id, stage1.Id, step1.Id, null);

        Test.startTest();
        Boolean result = ProcessRunnerController.checkSkipConditions(step1.Id, exec.Id);
        Test.stopTest();

        System.assertEquals(false, result, 'Should return false when no skip conditions are defined');
    }

    @IsTest
    static void testCheckSkipConditions_returnsTrueWhenConditionsMet() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];
        Stage__c stage1 = [SELECT Id FROM Stage__c WHERE Name = 'Stage 1' LIMIT 1];

        // Create step with skip condition
        Step__c stepWithSkip = new Step__c(
            Name = 'Skippable Step',
            Sequence__c = 2,
            Stage__c = stage1.Id,
            Type__c = 'Notification',
            FieldsConfig__c = '{"messageTemplate":"Skip test"}',
            SkipConditionLogic__c = 'AND',
            SkipConditionsConfig__c = '[{"source":"fieldValue","field":"Skip","operator":"equals","value":"Yes"}]'
        );
        insert stepWithSkip;

        Execution__c exec = new Execution__c(
            Process__c       = proc.Id,
            User__c          = UserInfo.getUserId(),
            StartedAt__c     = System.now(),
            Status__c        = 'In Progress',
            CurrentStage__c  = stage1.Id,
            CurrentStep__c   = stepWithSkip.Id,
            ExecutionData__c = '{"fieldValues":{"Skip":"Yes"}}'
        );
        insert exec;

        Test.startTest();
        Boolean result = ProcessRunnerController.checkSkipConditions(stepWithSkip.Id, exec.Id);
        Test.stopTest();

        System.assertEquals(true, result, 'Should return true when skip conditions are met');
    }

    @IsTest
    static void testCheckSkipConditions_returnsFalseWhenConditionsNotMet() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];
        Stage__c stage1 = [SELECT Id FROM Stage__c WHERE Name = 'Stage 1' LIMIT 1];

        Step__c stepWithSkip = new Step__c(
            Name = 'Skippable Step 2',
            Sequence__c = 3,
            Stage__c = stage1.Id,
            Type__c = 'Notification',
            FieldsConfig__c = '{"messageTemplate":"Skip test 2"}',
            SkipConditionLogic__c = 'AND',
            SkipConditionsConfig__c = '[{"source":"fieldValue","field":"Skip","operator":"equals","value":"Yes"}]'
        );
        insert stepWithSkip;

        // execData has Skip=No — condition not met
        Execution__c exec = new Execution__c(
            Process__c       = proc.Id,
            User__c          = UserInfo.getUserId(),
            StartedAt__c     = System.now(),
            Status__c        = 'In Progress',
            CurrentStage__c  = stage1.Id,
            CurrentStep__c   = stepWithSkip.Id,
            ExecutionData__c = '{"fieldValues":{"Skip":"No"}}'
        );
        insert exec;

        Test.startTest();
        Boolean result = ProcessRunnerController.checkSkipConditions(stepWithSkip.Id, exec.Id);
        Test.stopTest();

        System.assertEquals(false, result, 'Should return false when skip conditions are not met');
    }

    // ─── getExecutionHistory ──────────────────────────────────────────────────

    @IsTest
    static void testGetExecutionHistory_returnsCompletedOnly() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];
        Stage__c stage1 = [SELECT Id FROM Stage__c WHERE Name = 'Stage 1' LIMIT 1];
        Step__c step1 = [SELECT Id FROM Step__c WHERE Name = 'Step 1' LIMIT 1];

        // Create one completed, one in-progress
        createExecution(proc.Id, stage1.Id, step1.Id, 'Completed');
        createExecution(proc.Id, stage1.Id, step1.Id, null); // in-progress

        Test.startTest();
        List<Execution__c> history = ProcessRunnerController.getExecutionHistory(proc.Id);
        Test.stopTest();

        System.assertEquals(1, history.size(), 'Should only return completed executions');
        System.assertEquals('Completed', history[0].FinalStatus__c);
    }

    @IsTest
    static void testGetExecutionHistory_returnsCancelledExecutions() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];
        Stage__c stage1 = [SELECT Id FROM Stage__c WHERE Name = 'Stage 1' LIMIT 1];
        Step__c step1 = [SELECT Id FROM Step__c WHERE Name = 'Step 1' LIMIT 1];

        createExecution(proc.Id, stage1.Id, step1.Id, 'Cancelled');

        Test.startTest();
        List<Execution__c> history = ProcessRunnerController.getExecutionHistory(proc.Id);
        Test.stopTest();

        System.assertEquals(1, history.size(), 'Should include cancelled executions');
    }

    @IsTest
    static void testGetExecutionHistory_emptyWhenNone() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];

        Test.startTest();
        List<Execution__c> history = ProcessRunnerController.getExecutionHistory(proc.Id);
        Test.stopTest();

        System.assertEquals(0, history.size(), 'Should return empty when no completed executions');
    }

    // ─── getLogsForExecution ──────────────────────────────────────────────────

    @IsTest
    static void testGetLogsForExecution_returnsLogsForExecution() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];
        Stage__c stage1 = [SELECT Id FROM Stage__c WHERE Name = 'Stage 1' LIMIT 1];
        Step__c step1 = [SELECT Id FROM Step__c WHERE Name = 'Step 1' LIMIT 1];

        Execution__c exec = createExecution(proc.Id, stage1.Id, step1.Id, null);

        // Insert two logs for this execution
        insert new List<ExecutionLog__c>{
            new ExecutionLog__c(
                Execution__c  = exec.Id,
                Step__c       = step1.Id,
                Status__c     = 'Success',
                InputData__c  = '{}',
                ExecutedAt__c = System.now()
            ),
            new ExecutionLog__c(
                Execution__c  = exec.Id,
                Step__c       = step1.Id,
                Status__c     = 'Success',
                InputData__c  = '{}',
                ExecutedAt__c = System.now().addSeconds(1)
            )
        };

        Test.startTest();
        List<ExecutionLog__c> logs = ProcessRunnerController.getLogsForExecution(exec.Id);
        Test.stopTest();

        System.assertEquals(2, logs.size(), 'Should return all logs for the execution');
    }

    @IsTest
    static void testGetLogsForExecution_emptyWhenNone() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];
        Stage__c stage1 = [SELECT Id FROM Stage__c WHERE Name = 'Stage 1' LIMIT 1];
        Step__c step1 = [SELECT Id FROM Step__c WHERE Name = 'Step 1' LIMIT 1];

        Execution__c exec = createExecution(proc.Id, stage1.Id, step1.Id, null);

        Test.startTest();
        List<ExecutionLog__c> logs = ProcessRunnerController.getLogsForExecution(exec.Id);
        Test.stopTest();

        System.assertEquals(0, logs.size(), 'Should return empty list when no logs');
    }

    // ─── cancelExecution ──────────────────────────────────────────────────────

    @IsTest
    static void testCancelExecution_setsFinalStatusCancelled() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];
        Stage__c stage1 = [SELECT Id FROM Stage__c WHERE Name = 'Stage 1' LIMIT 1];
        Step__c step1 = [SELECT Id FROM Step__c WHERE Name = 'Step 1' LIMIT 1];

        Execution__c exec = createExecution(proc.Id, stage1.Id, step1.Id, null);

        Test.startTest();
        ProcessRunnerController.cancelExecution(exec.Id);
        Test.stopTest();

        Execution__c updated = [SELECT FinalStatus__c, CompletedAt__c FROM Execution__c WHERE Id = :exec.Id];
        System.assertEquals('Cancelled', updated.FinalStatus__c, 'FinalStatus should be Cancelled');
        System.assertNotEquals(null, updated.CompletedAt__c, 'CompletedAt should be set');
    }

    // ─── executeStep ─────────────────────────────────────────────────────────

    @IsTest
    static void testExecuteStep_callsEngineAndWritesLog() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];
        Stage__c stage1 = [SELECT Id FROM Stage__c WHERE Name = 'Stage 1' LIMIT 1];

        // Use email channel to avoid ConnectApi dependency in test context
        Step__c emailStep = new Step__c(
            Name = 'Email Step',
            Sequence__c = 10,
            Stage__c = stage1.Id,
            Type__c = 'Notification',
            FieldsConfig__c = '{"messageTemplate":"Hello","channel":"email","recipientEmail":"test@example.com"}'
        );
        insert emailStep;

        Execution__c exec = createExecution(proc.Id, stage1.Id, emailStep.Id, null);

        Test.startTest();
        ProcessExecutionEngine.StepResult result = ProcessRunnerController.executeStep(
            emailStep.Id,
            'Notification',
            null,
            '{"messageTemplate":"Hello","channel":"email","recipientEmail":"test@example.com"}',
            '{}',
            exec.Id,
            true  // isLastStep — will complete the execution
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');

        // Verify a success log was written
        List<ExecutionLog__c> logs = [SELECT Status__c FROM ExecutionLog__c WHERE Execution__c = :exec.Id];
        System.assertEquals(1, logs.size(), 'A log entry should have been written');
        System.assertEquals('Success', logs[0].Status__c, 'Log should record Success status');
    }

    @IsTest
    static void testExecuteStep_withBlankFieldsConfigAndInput() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Test' LIMIT 1];
        Stage__c stage1 = [SELECT Id FROM Stage__c WHERE Name = 'Stage 1' LIMIT 1];

        // Use email channel step so ConnectApi is not called
        Step__c emailStep2 = new Step__c(
            Name = 'Email Step 2',
            Sequence__c = 11,
            Stage__c = stage1.Id,
            Type__c = 'Notification',
            FieldsConfig__c = '{"messageTemplate":"Test","channel":"email","recipientEmail":"test@example.com"}'
        );
        insert emailStep2;

        Execution__c exec = createExecution(proc.Id, stage1.Id, emailStep2.Id, null);

        // fieldsConfig from DB (not null-blank test path); pass null inputDataJson to exercise null guard
        Test.startTest();
        ProcessExecutionEngine.StepResult result = ProcessRunnerController.executeStep(
            emailStep2.Id,
            'Notification',
            null,
            '{"messageTemplate":"Test","channel":"email","recipientEmail":"test@example.com"}',
            null,   // blank inputDataJson to exercise the null guard
            exec.Id,
            false
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should handle null inputDataJson');
    }
}
