@IsTest
private class ProcessExecutionEngineTest {

    @TestSetup
    static void setup() {
        Process__c process = new Process__c(
            Name = 'Test Process',
            IsActive__c = true
        );
        insert process;

        Stage__c stage = new Stage__c(
            Name = 'Stage 1',
            Sequence__c = 1,
            Process__c = process.Id
        );
        insert stage;
    }

    @IsTest
    static void testCreateRecord_createsCase() {
        Stage__c stage = [SELECT Id FROM Stage__c LIMIT 1];
        Step__c step = new Step__c(
            Name = 'Create Case',
            Sequence__c = 1,
            Stage__c = stage.Id,
            Type__c = 'Create Record',
            TargetObject__c = 'Case',
            FieldsConfig__c = '[{"apiName":"Subject","required":true,"defaultValue":null}]'
        );
        insert step;

        Process__c process = [SELECT Id FROM Process__c LIMIT 1];
        Execution__c exec = new Execution__c(
            Process__c = process.Id,
            User__c = UserInfo.getUserId(),
            StartedAt__c = System.now(),
            Status__c = 'In Progress',
            CurrentStage__c = stage.Id,
            CurrentStep__c = step.Id,
            ExecutionData__c = '{}'
        );
        insert exec;

        Map<String, Object> inputData = new Map<String, Object>{
            'Subject' => 'Test Case from ProcessFlow'
        };

        Test.startTest();
        ProcessExecutionEngine.execute(step.Id, inputData, exec.Id);
        Test.stopTest();

        List<Case> cases = [SELECT Subject FROM Case WHERE Subject = 'Test Case from ProcessFlow'];
        System.assertEquals(1, cases.size(), 'Should have created 1 Case');
        System.assertEquals('Test Case from ProcessFlow', cases[0].Subject);
    }

    @IsTest
    static void testUpdateRecord_updatesCase() {
        Case existingCase = new Case(Subject = 'Original Subject', Status = 'New');
        insert existingCase;

        Stage__c stage = [SELECT Id FROM Stage__c LIMIT 1];
        Step__c step = new Step__c(
            Name = 'Update Case',
            Sequence__c = 1,
            Stage__c = stage.Id,
            Type__c = 'Update Record',
            TargetObject__c = 'Case',
            FieldsConfig__c = '[{"apiName":"Status","required":false,"defaultValue":null}]'
        );
        insert step;

        Process__c process = [SELECT Id FROM Process__c LIMIT 1];
        Execution__c exec = new Execution__c(
            Process__c = process.Id,
            User__c = UserInfo.getUserId(),
            StartedAt__c = System.now(),
            Status__c = 'In Progress',
            CurrentStage__c = stage.Id,
            CurrentStep__c = step.Id,
            ExecutionData__c = '{}'
        );
        insert exec;

        Map<String, Object> inputData = new Map<String, Object>{
            'recordId' => existingCase.Id,
            'Status'   => 'Working'
        };

        Test.startTest();
        ProcessExecutionEngine.execute(step.Id, inputData, exec.Id);
        Test.stopTest();

        Case updated = [SELECT Status FROM Case WHERE Id = :existingCase.Id];
        System.assertEquals('Working', updated.Status, 'Status should have been updated to Working');
    }

    @IsTest
    static void testNotification_sendsWithoutException() {
        Stage__c stage = [SELECT Id FROM Stage__c LIMIT 1];
        Step__c step = new Step__c(
            Name = 'Notify User',
            Sequence__c = 1,
            Stage__c = stage.Id,
            Type__c = 'Notification',
            FieldsConfig__c = '{"messageTemplate":"Process completed successfully."}'
        );
        insert step;

        Process__c process = [SELECT Id FROM Process__c LIMIT 1];
        Execution__c exec = new Execution__c(
            Process__c = process.Id,
            User__c = UserInfo.getUserId(),
            StartedAt__c = System.now(),
            Status__c = 'In Progress',
            CurrentStage__c = stage.Id,
            CurrentStep__c = step.Id,
            ExecutionData__c = '{}'
        );
        insert exec;

        Map<String, Object> inputData = new Map<String, Object>{
            'recipientId' => UserInfo.getUserId()
        };

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            ProcessExecutionEngine.execute(step.Id, inputData, exec.Id);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(false, exceptionThrown, 'Notification step should not throw an exception');
    }

    @IsTest
    static void testLastStep_deletesExecution() {
        Stage__c stage = [SELECT Id FROM Stage__c LIMIT 1];
        Step__c step = new Step__c(
            Name = 'Final Step',
            Sequence__c = 1,
            Stage__c = stage.Id,
            Type__c = 'Notification',
            FieldsConfig__c = '{"messageTemplate":"Done."}'
        );
        insert step;

        Process__c process = [SELECT Id FROM Process__c LIMIT 1];
        Execution__c exec = new Execution__c(
            Process__c = process.Id,
            User__c = UserInfo.getUserId(),
            StartedAt__c = System.now(),
            Status__c = 'In Progress',
            CurrentStage__c = stage.Id,
            CurrentStep__c = step.Id,
            ExecutionData__c = '{}'
        );
        insert exec;
        Id execId = exec.Id;

        Map<String, Object> inputData = new Map<String, Object>{
            'recipientId' => UserInfo.getUserId(),
            'isLastStep'  => true
        };

        Test.startTest();
        ProcessExecutionEngine.execute(step.Id, inputData, execId);
        Test.stopTest();

        List<Execution__c> remaining = [SELECT Id FROM Execution__c WHERE Id = :execId];
        System.assertEquals(0, remaining.size(), 'Execution record should be deleted after last step');
    }
}
