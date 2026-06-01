@IsTest
private class ProcessBuilderControllerTest {

    @IsTest
    static void testSaveProcess_createsAllRecords() {
        Map<String, Object> payload = new Map<String, Object>{
            'name'        => 'New Hire Onboarding',
            'description' => 'Onboarding flow for new employees',
            'isActive'    => true,
            'stages'      => new List<Object>{
                new Map<String, Object>{
                    'name'     => 'Documentation',
                    'sequence' => 1,
                    'steps'    => new List<Object>{
                        new Map<String, Object>{
                            'name'         => 'Create Ticket',
                            'sequence'     => 1,
                            'type'         => 'Create Record',
                            'targetObject' => 'Case',
                            'fieldsConfig' => '[{"apiName":"Subject","required":true,"defaultValue":null}]',
                            'isRequired'   => true
                        }
                    }
                }
            }
        };

        Test.startTest();
        Id processId = ProcessBuilderController.saveProcess(JSON.serialize(payload));
        Test.stopTest();

        System.assertNotEquals(null, processId, 'Should return a process Id');

        Process__c process = [SELECT Name, IsActive__c FROM Process__c WHERE Id = :processId];
        System.assertEquals('New Hire Onboarding', process.Name);
        System.assertEquals(true, process.IsActive__c);

        List<Stage__c> stages = [SELECT Name FROM Stage__c WHERE Process__c = :processId];
        System.assertEquals(1, stages.size(), 'Should have created 1 stage');

        List<Step__c> steps = [SELECT Name, Type__c FROM Step__c WHERE Stage__c = :stages[0].Id];
        System.assertEquals(1, steps.size(), 'Should have created 1 step');
        System.assertEquals('Create Record', steps[0].Type__c);
    }

    @IsTest
    static void testSaveProcess_rollsBackOnError() {
        Map<String, Object> payload = new Map<String, Object>{
            'name'   => '',
            'stages' => new List<Object>()
        };

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            ProcessBuilderController.saveProcess(JSON.serialize(payload));
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Should throw AuraHandledException on invalid payload');
        List<Process__c> processes = [SELECT Id FROM Process__c];
        System.assertEquals(0, processes.size(), 'Rollback: no partial records should exist');
    }
}
