@IsTest
private class RollbackServiceTest {

    @TestSetup
    static void setup() {
        Process__c proc = new Process__c(Name='Rollback Test', IsActive__c=true, Version__c=1, IsCurrentVersion__c=true);
        insert proc;
        Stage__c stage = new Stage__c(Name='Stage 1', Sequence__c=1, Process__c=proc.Id);
        insert stage;
        Step__c step = new Step__c(Name='Create Account', Sequence__c=1, Stage__c=stage.Id,
            Type__c='Create Record', TargetObject__c='Account',
            FieldsConfig__c='[{"apiName":"Name","required":true,"type":"STRING","label":"Name","defaultValue":null,"picklistValues":[]}]');
        insert step;
    }

    @IsTest
    static void testRollback_deletesCreatedAccountsInStage() {
        Process__c proc = [SELECT Id FROM Process__c LIMIT 1];
        Stage__c stage  = [SELECT Id FROM Stage__c LIMIT 1];
        Step__c step    = [SELECT Id FROM Step__c LIMIT 1];

        Account a = new Account(Name = 'Rollback Test Account');
        insert a;

        Execution__c exec = new Execution__c(
            Process__c = proc.Id, User__c = UserInfo.getUserId(),
            StartedAt__c = System.now(), Status__c = 'In Progress',
            CurrentStage__c = stage.Id, CurrentStep__c = step.Id,
            ExecutionData__c = JSON.serialize(new Map<String,Object>{
                'fieldValues'   => new Map<String,Object>{'Name'=>'Rollback Test Account'},
                'createdRecords'=> new Map<String,Object>{
                    String.valueOf(step.Id) => new Map<String,Object>{
                        '__id'          => a.Id,
                        '__objectType'  => 'Account',
                        'Name'          => 'Rollback Test Account'
                    }
                }
            })
        );
        insert exec;

        Test.startTest();
        RollbackService.rollbackStage(exec.Id, stage.Id);
        Test.stopTest();

        List<Account> remaining = [SELECT Id FROM Account WHERE Id = :a.Id];
        System.assertEquals(0, remaining.size(), 'Account should be deleted by rollback');

        Execution__c updated = [SELECT FinalStatus__c, CompletedAt__c FROM Execution__c WHERE Id = :exec.Id];
        System.assertEquals('Failed', updated.FinalStatus__c);
        System.assertNotEquals(null, updated.CompletedAt__c);
    }

    @IsTest
    static void testRollback_ignoresRecordsFromOtherStages() {
        Process__c proc = [SELECT Id FROM Process__c LIMIT 1];
        Stage__c stage  = [SELECT Id FROM Stage__c LIMIT 1];
        Step__c step    = [SELECT Id FROM Step__c LIMIT 1];

        Account aOtherStage = new Account(Name = 'Other Stage Account');
        insert aOtherStage;

        Stage__c otherStage = new Stage__c(Name='Stage 2', Sequence__c=2, Process__c=proc.Id);
        insert otherStage;
        Step__c otherStep = new Step__c(Name='Other Step', Sequence__c=1, Stage__c=otherStage.Id,
            Type__c='Notification', FieldsConfig__c='{"messageTemplate":"test"}');
        insert otherStep;

        Execution__c exec = new Execution__c(
            Process__c = proc.Id, User__c = UserInfo.getUserId(),
            StartedAt__c = System.now(), Status__c = 'In Progress',
            CurrentStage__c = stage.Id, CurrentStep__c = step.Id,
            ExecutionData__c = JSON.serialize(new Map<String,Object>{
                'fieldValues'   => new Map<String,Object>(),
                'createdRecords'=> new Map<String,Object>{
                    String.valueOf(otherStep.Id) => new Map<String,Object>{
                        '__id'         => aOtherStage.Id,
                        '__objectType' => 'Account'
                    }
                }
            })
        );
        insert exec;

        Test.startTest();
        RollbackService.rollbackStage(exec.Id, stage.Id);
        Test.stopTest();

        List<Account> remaining = [SELECT Id FROM Account WHERE Id = :aOtherStage.Id];
        System.assertEquals(1, remaining.size(), 'Account from other stage should be preserved');
    }

    @IsTest
    static void testRollback_toleratesAlreadyDeletedRecord() {
        Process__c proc = [SELECT Id FROM Process__c LIMIT 1];
        Stage__c stage  = [SELECT Id FROM Stage__c LIMIT 1];
        Step__c step    = [SELECT Id FROM Step__c LIMIT 1];

        Id fakeId = '001000000000001AAA';

        Execution__c exec = new Execution__c(
            Process__c = proc.Id, User__c = UserInfo.getUserId(),
            StartedAt__c = System.now(), Status__c = 'In Progress',
            CurrentStage__c = stage.Id, CurrentStep__c = step.Id,
            ExecutionData__c = JSON.serialize(new Map<String,Object>{
                'fieldValues'   => new Map<String,Object>(),
                'createdRecords'=> new Map<String,Object>{
                    String.valueOf(step.Id) => new Map<String,Object>{
                        '__id'         => fakeId,
                        '__objectType' => 'Account'
                    }
                }
            })
        );
        insert exec;

        Test.startTest();
        Boolean threw = false;
        try {
            RollbackService.rollbackStage(exec.Id, stage.Id);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(false, threw, 'Should not throw when record already deleted');
    }
}
