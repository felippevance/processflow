@IsTest
private class ApprovalServiceTest {

    @TestSetup
    static void setup() {
        Process__c proc = new Process__c(Name='Approval Test', IsActive__c=true, Version__c=1, IsCurrentVersion__c=true);
        insert proc;
        Stage__c stage = new Stage__c(Name='Stage 1', Sequence__c=1, Process__c=proc.Id);
        insert stage;
        Step__c step = new Step__c(Name='Create Account', Sequence__c=1, Stage__c=stage.Id,
            Type__c='Create Record', TargetObject__c='Account',
            FieldsConfig__c='[]');
        insert step;
    }

    @IsTest
    static void testCheckStatus_noPendingApproval_returnsApproved() {
        Process__c proc = [SELECT Id FROM Process__c LIMIT 1];
        Stage__c stage  = [SELECT Id FROM Stage__c LIMIT 1];
        Step__c step    = [SELECT Id FROM Step__c LIMIT 1];

        Execution__c exec = new Execution__c(
            Process__c = proc.Id, User__c = UserInfo.getUserId(),
            StartedAt__c = System.now(), Status__c = 'In Progress',
            CurrentStage__c = stage.Id, CurrentStep__c = step.Id,
            ExecutionData__c = '{}',
            PendingApprovalId__c = null
        );
        insert exec;

        Test.startTest();
        ApprovalService.ApprovalResult result = ApprovalService.checkStatus(exec.Id);
        Test.stopTest();

        System.assertEquals('Approved', result.status, 'No pending approval should return Approved');
    }

    @IsTest
    static void testCheckStatus_withFakePendingId_returnsApproved() {
        Process__c proc = [SELECT Id FROM Process__c LIMIT 1];
        Stage__c stage  = [SELECT Id FROM Stage__c LIMIT 1];
        Step__c step    = [SELECT Id FROM Step__c LIMIT 1];

        Execution__c exec = new Execution__c(
            Process__c = proc.Id, User__c = UserInfo.getUserId(),
            StartedAt__c = System.now(), Status__c = 'In Progress',
            CurrentStage__c = stage.Id, CurrentStep__c = step.Id,
            ExecutionData__c = '{}',
            PendingApprovalId__c = '04ig000000000001AA'
        );
        insert exec;

        Test.startTest();
        ApprovalService.ApprovalResult result = ApprovalService.checkStatus(exec.Id);
        Test.stopTest();

        System.assertEquals('Approved', result.status, 'Missing ProcessInstance should gracefully return Approved');
    }

    @IsTest
    static void testClearPendingApproval_clearsBothFields() {
        Process__c proc = [SELECT Id FROM Process__c LIMIT 1];
        Stage__c stage  = [SELECT Id FROM Stage__c LIMIT 1];
        Step__c step    = [SELECT Id FROM Step__c LIMIT 1];

        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Execution__c exec = new Execution__c(
            Process__c = proc.Id, User__c = UserInfo.getUserId(),
            StartedAt__c = System.now(), Status__c = 'In Progress',
            CurrentStage__c = stage.Id, CurrentStep__c = step.Id,
            ExecutionData__c = '{}',
            PendingApprovalId__c = '04ig000000000001AA',
            PendingApprovalRecordId__c = acc.Id
        );
        insert exec;

        Test.startTest();
        ApprovalService.clearPendingApproval(exec.Id);
        Test.stopTest();

        Execution__c updated = [SELECT PendingApprovalId__c, PendingApprovalRecordId__c FROM Execution__c WHERE Id = :exec.Id];
        System.assertEquals(null, updated.PendingApprovalId__c, 'PendingApprovalId__c should be cleared');
        System.assertEquals(null, updated.PendingApprovalRecordId__c, 'PendingApprovalRecordId__c should be cleared');
    }

    // ── Expanded coverage: clearPendingApproval when already null ────────────
    @IsTest
    static void testClearPendingApproval_alreadyNull_isIdempotent() {
        Process__c proc = [SELECT Id FROM Process__c LIMIT 1];
        Stage__c stage  = [SELECT Id FROM Stage__c LIMIT 1];
        Step__c step    = [SELECT Id FROM Step__c LIMIT 1];

        // Execution starts with no pending approval
        Execution__c exec = new Execution__c(
            Process__c = proc.Id, User__c = UserInfo.getUserId(),
            StartedAt__c = System.now(), Status__c = 'In Progress',
            CurrentStage__c = stage.Id, CurrentStep__c = step.Id,
            ExecutionData__c = '{}',
            PendingApprovalId__c = null,
            PendingApprovalRecordId__c = null
        );
        insert exec;

        Test.startTest();
        Boolean threw = false;
        try {
            ApprovalService.clearPendingApproval(exec.Id);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(false, threw, 'clearPendingApproval should not throw when fields are already null');
        Execution__c updated = [SELECT PendingApprovalId__c, PendingApprovalRecordId__c FROM Execution__c WHERE Id = :exec.Id];
        System.assertEquals(null, updated.PendingApprovalId__c,       'PendingApprovalId__c should remain null');
        System.assertEquals(null, updated.PendingApprovalRecordId__c, 'PendingApprovalRecordId__c should remain null');
    }

    // ── checkStatus: ProcessInstance in Pending status (via fake ID path) ────
    @IsTest
    static void testCheckStatus_withFakePendingId_returnsInstanceStatus() {
        Process__c proc = [SELECT Id FROM Process__c LIMIT 1];
        Stage__c stage  = [SELECT Id FROM Stage__c LIMIT 1];
        Step__c step    = [SELECT Id FROM Step__c LIMIT 1];

        // Use a fake ProcessInstance Id — the SOQL query will return 0 rows,
        // so checkStatus gracefully falls back to 'Approved'.
        // This exercises the query path and the instances.isEmpty() branch.
        Execution__c exec = new Execution__c(
            Process__c = proc.Id, User__c = UserInfo.getUserId(),
            StartedAt__c = System.now(), Status__c = 'In Progress',
            CurrentStage__c = stage.Id, CurrentStep__c = step.Id,
            ExecutionData__c = '{}',
            PendingApprovalId__c = '04ig000000000002AA'
        );
        insert exec;

        Test.startTest();
        ApprovalService.ApprovalResult result = ApprovalService.checkStatus(exec.Id);
        Test.stopTest();

        // No real ProcessInstance exists → instances.isEmpty() → status = 'Approved'
        System.assertEquals('Approved', result.status,
            'Non-existent ProcessInstance should gracefully return Approved status');
        System.assertEquals('04ig000000000002AA', result.instanceId,
            'instanceId should be echoed back from the Execution record');
    }
}
