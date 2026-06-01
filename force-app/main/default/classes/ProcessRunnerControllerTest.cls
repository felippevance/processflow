@IsTest
private class ProcessRunnerControllerTest {

    @TestSetup
    static void setup() {
        Process__c process = new Process__c(
            Name = 'Active Process', IsActive__c = true
        );
        insert process;
        Stage__c stage = new Stage__c(
            Name = 'Stage 1', Sequence__c = 1, Process__c = process.Id
        );
        insert stage;
        Step__c step = new Step__c(
            Name = 'Step 1', Sequence__c = 1, Stage__c = stage.Id,
            Type__c = 'Notification',
            FieldsConfig__c = '{"messageTemplate":"Hello"}'
        );
        insert step;
    }

    @IsTest
    static void testGetActiveProcesses_returnsActiveOnly() {
        Process__c inactive = new Process__c(
            Name = 'Inactive', IsActive__c = false
        );
        insert inactive;

        Test.startTest();
        List<Process__c> results = ProcessRunnerController.getActiveProcesses();
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should only return active processes');
        System.assertEquals('Active Process', results[0].Name);
    }

    @IsTest
    static void testGetOpenExecution_returnsInProgress() {
        Process__c process = [SELECT Id FROM Process__c WHERE Name = 'Active Process' LIMIT 1];
        Stage__c stage = [SELECT Id FROM Stage__c LIMIT 1];
        Step__c step = [SELECT Id FROM Step__c LIMIT 1];

        Execution__c exec = new Execution__c(
            Process__c  = process.Id,
            User__c     = UserInfo.getUserId(),
            StartedAt__c = System.now(),
            Status__c   = 'In Progress',
            CurrentStage__c = stage.Id,
            CurrentStep__c  = step.Id,
            ExecutionData__c = '{}'
        );
        insert exec;

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
    static void testStartExecution_createsExecutionRecord() {
        Process__c process = [SELECT Id FROM Process__c WHERE Name = 'Active Process' LIMIT 1];

        Test.startTest();
        Execution__c exec = ProcessRunnerController.startExecution(process.Id);
        Test.stopTest();

        System.assertNotEquals(null, exec.Id);
        System.assertEquals('In Progress', exec.Status__c);
        System.assertEquals(process.Id, exec.Process__c);
    }

    @IsTest
    static void testGetProcessSteps_returnsOrderedSteps() {
        Process__c process = [SELECT Id FROM Process__c WHERE Name = 'Active Process' LIMIT 1];

        Test.startTest();
        List<ProcessRunnerController.StageWithSteps> result = ProcessRunnerController.getProcessSteps(process.Id);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Should return 1 stage');
        System.assertEquals(1, result[0].steps.size(), 'Stage should have 1 step');
    }
}
