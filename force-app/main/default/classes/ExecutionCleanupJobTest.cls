@IsTest
private class ExecutionCleanupJobTest {

    // ── Shared setup helpers ─────────────────────────────────────────────────

    private static Process__c insertProcess() {
        Process__c proc = new Process__c(
            Name = 'Cleanup Test Process', IsActive__c = true,
            Version__c = 1, IsCurrentVersion__c = true
        );
        insert proc;
        return proc;
    }

    private static Stage__c insertStage(Id procId) {
        Stage__c stage = new Stage__c(Name = 'Stage 1', Sequence__c = 1, Process__c = procId);
        insert stage;
        return stage;
    }

    private static Step__c insertStep(Id stageId) {
        Step__c step = new Step__c(
            Name = 'Notify', Sequence__c = 1, Stage__c = stageId,
            Type__c = 'Notification', FieldsConfig__c = '{"messageTemplate":"Hi"}'
        );
        insert step;
        return step;
    }

    /**
     * Creates an Execution__c with CompletedAt__c in the past and a FinalStatus set,
     * plus one child ExecutionLog__c.
     */
    private static Execution__c insertOldExecution(Id procId, Id stageId, Id stepId, Integer daysAgo) {
        Execution__c exec = new Execution__c(
            Process__c       = procId,
            User__c          = UserInfo.getUserId(),
            StartedAt__c     = System.now().addDays(-daysAgo),
            CompletedAt__c   = System.now().addDays(-daysAgo),
            Status__c        = 'Completed',
            FinalStatus__c   = 'Completed',
            CurrentStage__c  = stageId,
            CurrentStep__c   = stepId,
            ExecutionData__c = '{}'
        );
        insert exec;
        return exec;
    }

    private static ExecutionLog__c insertLog(Id execId) {
        ExecutionLog__c log = new ExecutionLog__c(
            Execution__c = execId,
            ExecutedAt__c = System.now(),
            Status__c    = 'Success'
        );
        insert log;
        return log;
    }

    // ── 1. cleanOldExecutions: deletes executions + logs older than N days ───
    @IsTest
    static void testCleanOldExecutions_deletesOldExecutionsAndLogs() {
        Process__c proc  = insertProcess();
        Stage__c   stage = insertStage(proc.Id);
        Step__c    step  = insertStep(stage.Id);

        // Create one OLD execution (91 days ago) with a child log
        Execution__c oldExec = insertOldExecution(proc.Id, stage.Id, step.Id, 91);
        ExecutionLog__c oldLog = insertLog(oldExec.Id);

        // Create one RECENT execution (1 day ago) that should NOT be deleted
        Execution__c recentExec = new Execution__c(
            Process__c       = proc.Id,
            User__c          = UserInfo.getUserId(),
            StartedAt__c     = System.now().addDays(-1),
            CompletedAt__c   = System.now().addDays(-1),
            Status__c        = 'Completed',
            FinalStatus__c   = 'Completed',
            CurrentStage__c  = stage.Id,
            CurrentStep__c   = step.Id,
            ExecutionData__c = '{}'
        );
        insert recentExec;
        ExecutionLog__c recentLog = insertLog(recentExec.Id);

        Test.startTest();
        ExecutionCleanupJob.cleanOldExecutions(90);
        Test.stopTest();

        // Old execution and its log should be gone
        List<Execution__c>    remainingExecs = [SELECT Id FROM Execution__c WHERE Id = :oldExec.Id];
        List<ExecutionLog__c> remainingLogs  = [SELECT Id FROM ExecutionLog__c WHERE Id = :oldLog.Id];
        System.assertEquals(0, remainingExecs.size(), 'Old execution should be deleted');
        System.assertEquals(0, remainingLogs.size(),  'Child log of old execution should be deleted');

        // Recent execution and its log should survive
        List<Execution__c>    keptExecs = [SELECT Id FROM Execution__c WHERE Id = :recentExec.Id];
        List<ExecutionLog__c> keptLogs  = [SELECT Id FROM ExecutionLog__c WHERE Id = :recentLog.Id];
        System.assertEquals(1, keptExecs.size(), 'Recent execution should be preserved');
        System.assertEquals(1, keptLogs.size(),  'Log of recent execution should be preserved');
    }

    // ── 2. execute() via schedulable context ─────────────────────────────────
    @IsTest
    static void testExecute_schedulableContext_runsWithoutError() {
        Process__c proc  = insertProcess();
        Stage__c   stage = insertStage(proc.Id);
        Step__c    step  = insertStep(stage.Id);

        // Insert an execution old enough to be cleaned (95 days ago)
        Execution__c exec = insertOldExecution(proc.Id, stage.Id, step.Id, 95);
        insertLog(exec.Id);

        Test.startTest();
        // Schedule the job
        String cronExpr = '0 0 2 * * ?';
        String jobId = System.schedule('Test Cleanup Job', cronExpr, new ExecutionCleanupJob());
        Test.stopTest();

        // Verify the job was scheduled (no exception thrown)
        List<CronTrigger> triggers = [
            SELECT Id, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name = 'Test Cleanup Job'
        ];
        System.assertEquals(1, triggers.size(), 'Job should be scheduled');

        // Abort to clean up
        System.abortJob(jobId);
    }

    // ── 3. No executions to clean — runs without error ────────────────────────
    @IsTest
    static void testCleanOldExecutions_noExecutions_noError() {
        // No data inserted — should just complete without touching anything
        Test.startTest();
        Boolean threw = false;
        try {
            ExecutionCleanupJob.cleanOldExecutions(90);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(false, threw, 'cleanOldExecutions should not throw when there is nothing to delete');
    }

    // ── 4. Execution without FinalStatus__c is NOT deleted ────────────────────
    @IsTest
    static void testCleanOldExecutions_inProgressExecution_notDeleted() {
        Process__c proc  = insertProcess();
        Stage__c   stage = insertStage(proc.Id);
        Step__c    step  = insertStep(stage.Id);

        // In-Progress execution with old CompletedAt (FinalStatus is null)
        Execution__c exec = new Execution__c(
            Process__c       = proc.Id,
            User__c          = UserInfo.getUserId(),
            StartedAt__c     = System.now().addDays(-100),
            CompletedAt__c   = System.now().addDays(-100),
            Status__c        = 'In Progress',
            FinalStatus__c   = null,  // no FinalStatus → should NOT be deleted
            CurrentStage__c  = stage.Id,
            CurrentStep__c   = step.Id,
            ExecutionData__c = '{}'
        );
        insert exec;

        Test.startTest();
        ExecutionCleanupJob.cleanOldExecutions(90);
        Test.stopTest();

        List<Execution__c> remaining = [SELECT Id FROM Execution__c WHERE Id = :exec.Id];
        System.assertEquals(1, remaining.size(), 'In-Progress execution without FinalStatus should be preserved');
    }
}
