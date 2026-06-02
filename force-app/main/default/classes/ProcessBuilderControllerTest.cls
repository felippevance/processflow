@IsTest
private class ProcessBuilderControllerTest {

    // ─────────────────────────────────────────
    //  Helpers
    // ─────────────────────────────────────────

    private static Map<String, Object> buildMinimalPayload(String name, String stepType) {
        Map<String, Object> step = new Map<String, Object>{
            'name'     => 'Step 1',
            'sequence' => 1,
            'type'     => stepType
        };
        if (stepType == 'Create Record' || stepType == 'Update Record') {
            step.put('targetObject', 'Case');
            step.put('fieldsConfig', '[{"apiName":"Subject","type":"STRING"}]');
        }
        if (stepType == 'HTTP Request') {
            step.put('fieldsConfig', '{"namedCredential":"My_NC","method":"GET","path":"/test"}');
        }
        if (stepType == 'Notification') {
            step.put('fieldsConfig', '{"messageTemplate":"Hello"}');
        }
        Map<String, Object> stage = new Map<String, Object>{
            'name'     => 'Stage 1',
            'sequence' => 1,
            'steps'    => new List<Object>{ step }
        };
        return new Map<String, Object>{
            'name'   => name,
            'stages' => new List<Object>{ stage }
        };
    }

    // ─────────────────────────────────────────
    //  Original tests
    // ─────────────────────────────────────────

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

    // ─────────────────────────────────────────
    //  getObjectFields
    // ─────────────────────────────────────────

    @IsTest
    static void testGetObjectFields_validObject() {
        Test.startTest();
        List<ProcessBuilderController.FieldInfo> fields =
            ProcessBuilderController.getObjectFields('Account');
        Test.stopTest();

        System.assertNotEquals(null, fields, 'Should return a list');
        System.assert(fields.size() > 0, 'Account should have accessible fields');
        // Verify structure of returned FieldInfo
        ProcessBuilderController.FieldInfo fi = fields[0];
        System.assertNotEquals(null, fi.apiName,  'apiName should not be null');
        System.assertNotEquals(null, fi.label,    'label should not be null');
        System.assertNotEquals(null, fi.type,     'type should not be null');
        System.assertNotEquals(null, fi.required, 'required should not be null');
        System.assertNotEquals(null, fi.picklistValues, 'picklistValues should not be null');
    }

    @IsTest
    static void testGetObjectFields_invalidObject() {
        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            ProcessBuilderController.getObjectFields('NonExistentObject__xyz');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown,
            'Should throw AuraHandledException for unknown object');
    }

    @IsTest
    static void testGetObjectFields_picklistFieldIncludesValues() {
        // Account.Type is a picklist — verify picklist values are populated
        Test.startTest();
        List<ProcessBuilderController.FieldInfo> fields =
            ProcessBuilderController.getObjectFields('Account');
        Test.stopTest();

        ProcessBuilderController.FieldInfo picklistField = null;
        for (ProcessBuilderController.FieldInfo fi : fields) {
            if (fi.type == 'PICKLIST') {
                picklistField = fi;
                break;
            }
        }
        if (picklistField != null) {
            System.assertNotEquals(null, picklistField.picklistValues,
                'Picklist field should have picklistValues list');
        }
    }

    // ─────────────────────────────────────────
    //  getRecordTypes
    // ─────────────────────────────────────────

    @IsTest
    static void testGetRecordTypes_validObject() {
        Test.startTest();
        List<Map<String, String>> result =
            ProcessBuilderController.getRecordTypes('Account');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return a list (may be empty if no record types)');
        // If record types exist, verify structure
        for (Map<String, String> rt : result) {
            System.assertNotEquals(null, rt.get('id'),    'id should not be null');
            System.assertNotEquals(null, rt.get('name'),  'name should not be null');
            System.assertNotEquals(null, rt.get('label'), 'label should not be null');
        }
    }

    @IsTest
    static void testGetRecordTypes_invalidObject_returnsEmpty() {
        Test.startTest();
        List<Map<String, String>> result =
            ProcessBuilderController.getRecordTypes('NotARealObject__zzz');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return empty list for unknown object');
        System.assertEquals(0, result.size(), 'Unknown object should return empty list');
    }

    // ─────────────────────────────────────────
    //  getNamedCredentials
    // ─────────────────────────────────────────

    @IsTest
    static void testGetNamedCredentials_returnsWithoutError() {
        Test.startTest();
        List<Map<String, String>> result = ProcessBuilderController.getNamedCredentials();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return a list (may be empty)');
        for (Map<String, String> nc : result) {
            System.assertNotEquals(null, nc.get('value'), 'value (DeveloperName) should not be null');
            System.assertNotEquals(null, nc.get('label'), 'label (MasterLabel) should not be null');
        }
    }

    // ─────────────────────────────────────────
    //  getApprovalProcesses
    // ─────────────────────────────────────────

    @IsTest
    static void testGetApprovalProcesses_returnsWithoutError() {
        Test.startTest();
        List<Map<String, String>> result = ProcessBuilderController.getApprovalProcesses();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return a list (may be empty)');
        for (Map<String, String> ap : result) {
            System.assertNotEquals(null, ap.get('value'), 'value should not be null');
            System.assertNotEquals(null, ap.get('label'), 'label should not be null');
        }
    }

    // ─────────────────────────────────────────
    //  cloneProcess
    // ─────────────────────────────────────────

    @IsTest
    static void testCloneProcess_clonesWithStagesAndSteps() {
        // Create original process
        Process__c original = new Process__c(
            Name               = 'Original Process',
            Description__c     = 'A test process',
            IsActive__c        = true,
            Version__c         = 1,
            IsCurrentVersion__c = true
        );
        insert original;

        Stage__c stage = new Stage__c(
            Name       = 'Stage A',
            Sequence__c = 1,
            Process__c  = original.Id,
            ConditionLogic__c = 'AND'
        );
        insert stage;

        List<Step__c> steps = new List<Step__c>{
            new Step__c(
                Name            = 'Step A1',
                Sequence__c     = 1,
                Stage__c        = stage.Id,
                Type__c         = 'Create Record',
                TargetObject__c = 'Case',
                FieldsConfig__c = '[{"apiName":"Subject","type":"STRING"}]',
                IsRequired__c   = true
            ),
            new Step__c(
                Name            = 'Step A2',
                Sequence__c     = 2,
                Stage__c        = stage.Id,
                Type__c         = 'Notification',
                FieldsConfig__c = '{"messageTemplate":"Done"}',
                IsRequired__c   = false
            )
        };
        insert steps;

        Test.startTest();
        Id clonedId = ProcessBuilderController.cloneProcess(original.Id);
        Test.stopTest();

        System.assertNotEquals(null, clonedId, 'Should return the new process Id');
        System.assertNotEquals(original.Id, clonedId, 'Clone must have a different Id');

        // Original should be marked as not current
        Process__c updatedOriginal = [
            SELECT IsCurrentVersion__c FROM Process__c WHERE Id = :original.Id
        ];
        System.assertEquals(false, updatedOriginal.IsCurrentVersion__c,
            'Original process should be marked as not current version');

        // Cloned process checks
        Process__c cloned = [
            SELECT Name, Version__c, IsCurrentVersion__c, IsActive__c
            FROM Process__c WHERE Id = :clonedId
        ];
        System.assertEquals('Original Process', cloned.Name, 'Clone should keep same name');
        System.assertEquals(2, cloned.Version__c, 'Clone should be version 2');
        System.assertEquals(true, cloned.IsCurrentVersion__c, 'Clone should be current version');
        System.assertEquals(true, cloned.IsActive__c, 'Clone should be active');

        // Stages should be cloned
        List<Stage__c> clonedStages = [
            SELECT Name FROM Stage__c WHERE Process__c = :clonedId
        ];
        System.assertEquals(1, clonedStages.size(), 'Clone should have 1 stage');
        System.assertEquals('Stage A', clonedStages[0].Name);

        // Steps should be cloned
        List<Step__c> clonedSteps = [
            SELECT Name FROM Step__c WHERE Stage__c = :clonedStages[0].Id
            ORDER BY Sequence__c ASC
        ];
        System.assertEquals(2, clonedSteps.size(), 'Clone should have 2 steps');
        System.assertEquals('Step A1', clonedSteps[0].Name);
        System.assertEquals('Step A2', clonedSteps[1].Name);
    }

    // ─────────────────────────────────────────
    //  validatePayload — via saveProcess
    // ─────────────────────────────────────────

    @IsTest
    static void testValidatePayload_emptyName() {
        Map<String, Object> payload = new Map<String, Object>{
            'name'   => '',
            'stages' => new List<Object>{ new Map<String, Object>{
                'name'     => 'S1',
                'sequence' => 1,
                'steps'    => new List<Object>{ new Map<String, Object>{
                    'name' => 'T1', 'sequence' => 1, 'type' => 'Notification',
                    'fieldsConfig' => '{"messageTemplate":"Hi"}'
                }}
            }}
        };
        Boolean thrown = false;
        Test.startTest();
        try { ProcessBuilderController.saveProcess(JSON.serialize(payload)); }
        catch (AuraHandledException e) { thrown = true; }
        Test.stopTest();
        System.assertEquals(true, thrown, 'Empty name should throw');
    }

    @IsTest
    static void testValidatePayload_missingStage() {
        Map<String, Object> payload = new Map<String, Object>{
            'name'   => 'Test Process',
            'stages' => new List<Object>()
        };
        Boolean thrown = false;
        Test.startTest();
        try { ProcessBuilderController.saveProcess(JSON.serialize(payload)); }
        catch (AuraHandledException e) { thrown = true; }
        Test.stopTest();
        System.assertEquals(true, thrown, 'Empty stages list should throw');
    }

    @IsTest
    static void testValidatePayload_stageWithNoSteps() {
        Map<String, Object> payload = new Map<String, Object>{
            'name'   => 'Test Process',
            'stages' => new List<Object>{ new Map<String, Object>{
                'name'     => 'Stage Without Steps',
                'sequence' => 1,
                'steps'    => new List<Object>()
            }}
        };
        Boolean thrown = false;
        Test.startTest();
        try { ProcessBuilderController.saveProcess(JSON.serialize(payload)); }
        catch (AuraHandledException e) { thrown = true; }
        Test.stopTest();
        System.assertEquals(true, thrown, 'Stage with no steps should throw');
    }

    @IsTest
    static void testValidatePayload_stepMissingName() {
        Map<String, Object> payload = new Map<String, Object>{
            'name'   => 'Test Process',
            'stages' => new List<Object>{ new Map<String, Object>{
                'name'     => 'S1',
                'sequence' => 1,
                'steps'    => new List<Object>{ new Map<String, Object>{
                    'name' => '', 'sequence' => 1, 'type' => 'Notification',
                    'fieldsConfig' => '{"messageTemplate":"Hi"}'
                }}
            }}
        };
        Boolean thrown = false;
        Test.startTest();
        try { ProcessBuilderController.saveProcess(JSON.serialize(payload)); }
        catch (AuraHandledException e) { thrown = true; }
        Test.stopTest();
        System.assertEquals(true, thrown, 'Step with empty name should throw');
    }

    @IsTest
    static void testValidatePayload_createRecordMissingTargetObject() {
        Map<String, Object> payload = new Map<String, Object>{
            'name'   => 'Test Process',
            'stages' => new List<Object>{ new Map<String, Object>{
                'name'     => 'S1',
                'sequence' => 1,
                'steps'    => new List<Object>{ new Map<String, Object>{
                    'name'         => 'Create Without Target',
                    'sequence'     => 1,
                    'type'         => 'Create Record',
                    'fieldsConfig' => '[{"apiName":"Subject","type":"STRING"}]'
                    // targetObject intentionally absent
                }}
            }}
        };
        Boolean thrown = false;
        Test.startTest();
        try { ProcessBuilderController.saveProcess(JSON.serialize(payload)); }
        catch (AuraHandledException e) { thrown = true; }
        Test.stopTest();
        System.assertEquals(true, thrown, 'Create Record without targetObject should throw');
    }

    @IsTest
    static void testValidatePayload_updateRecordMissingTargetObject() {
        Map<String, Object> payload = new Map<String, Object>{
            'name'   => 'Test Process',
            'stages' => new List<Object>{ new Map<String, Object>{
                'name'     => 'S1',
                'sequence' => 1,
                'steps'    => new List<Object>{ new Map<String, Object>{
                    'name'         => 'Update Without Target',
                    'sequence'     => 1,
                    'type'         => 'Update Record',
                    'fieldsConfig' => '[{"apiName":"Status","type":"STRING"}]'
                    // targetObject intentionally absent
                }}
            }}
        };
        Boolean thrown = false;
        Test.startTest();
        try { ProcessBuilderController.saveProcess(JSON.serialize(payload)); }
        catch (AuraHandledException e) { thrown = true; }
        Test.stopTest();
        System.assertEquals(true, thrown, 'Update Record without targetObject should throw');
    }

    @IsTest
    static void testValidatePayload_httpRequestMissingNamedCredential() {
        Map<String, Object> payload = new Map<String, Object>{
            'name'   => 'Test Process',
            'stages' => new List<Object>{ new Map<String, Object>{
                'name'     => 'S1',
                'sequence' => 1,
                'steps'    => new List<Object>{ new Map<String, Object>{
                    'name'         => 'HTTP Without NC',
                    'sequence'     => 1,
                    'type'         => 'HTTP Request',
                    'fieldsConfig' => '{"method":"GET","path":"/test"}'
                    // namedCredential intentionally absent
                }}
            }}
        };
        Boolean thrown = false;
        Test.startTest();
        try { ProcessBuilderController.saveProcess(JSON.serialize(payload)); }
        catch (AuraHandledException e) { thrown = true; }
        Test.stopTest();
        System.assertEquals(true, thrown, 'HTTP Request without Named Credential should throw');
    }

    @IsTest
    static void testValidatePayload_notificationMissingMessageTemplate() {
        Map<String, Object> payload = new Map<String, Object>{
            'name'   => 'Test Process',
            'stages' => new List<Object>{ new Map<String, Object>{
                'name'     => 'S1',
                'sequence' => 1,
                'steps'    => new List<Object>{ new Map<String, Object>{
                    'name'         => 'Notify Without Template',
                    'sequence'     => 1,
                    'type'         => 'Notification',
                    'fieldsConfig' => '{"channel":"email"}'
                    // messageTemplate intentionally absent
                }}
            }}
        };
        Boolean thrown = false;
        Test.startTest();
        try { ProcessBuilderController.saveProcess(JSON.serialize(payload)); }
        catch (AuraHandledException e) { thrown = true; }
        Test.stopTest();
        System.assertEquals(true, thrown, 'Notification without messageTemplate should throw');
    }

    @IsTest
    static void testValidatePayload_malformedFieldsConfigJson() {
        Map<String, Object> payload = new Map<String, Object>{
            'name'   => 'Test Process',
            'stages' => new List<Object>{ new Map<String, Object>{
                'name'     => 'S1',
                'sequence' => 1,
                'steps'    => new List<Object>{ new Map<String, Object>{
                    'name'         => 'Bad JSON Step',
                    'sequence'     => 1,
                    'type'         => 'Create Record',
                    'targetObject' => 'Case',
                    'fieldsConfig' => '{this is not valid json!!'
                }}
            }}
        };
        Boolean thrown = false;
        Test.startTest();
        try { ProcessBuilderController.saveProcess(JSON.serialize(payload)); }
        catch (AuraHandledException e) { thrown = true; }
        Test.stopTest();
        System.assertEquals(true, thrown, 'Malformed fieldsConfig JSON should throw');
    }

    @IsTest
    static void testValidatePayload_httpRequestNullFieldsConfig() {
        // HTTP step with null fieldsConfig (not parseable) should throw
        Map<String, Object> payload = new Map<String, Object>{
            'name'   => 'Test Process',
            'stages' => new List<Object>{ new Map<String, Object>{
                'name'     => 'S1',
                'sequence' => 1,
                'steps'    => new List<Object>{ new Map<String, Object>{
                    'name'         => 'HTTP Null Config',
                    'sequence'     => 1,
                    'type'         => 'HTTP Request'
                    // fieldsConfig null — no namedCredential
                }}
            }}
        };
        Boolean thrown = false;
        Test.startTest();
        try { ProcessBuilderController.saveProcess(JSON.serialize(payload)); }
        catch (AuraHandledException e) { thrown = true; }
        Test.stopTest();
        System.assertEquals(true, thrown, 'HTTP Request with null fieldsConfig should throw');
    }

    @IsTest
    static void testSaveProcess_notificationStep_succeeds() {
        Map<String, Object> payload = buildMinimalPayload('Notification Process', 'Notification');
        Test.startTest();
        Id processId = ProcessBuilderController.saveProcess(JSON.serialize(payload));
        Test.stopTest();
        System.assertNotEquals(null, processId, 'Notification process should save successfully');
    }

    @IsTest
    static void testSaveProcess_httpRequestStep_succeeds() {
        Map<String, Object> payload = buildMinimalPayload('HTTP Process', 'HTTP Request');
        Test.startTest();
        Id processId = ProcessBuilderController.saveProcess(JSON.serialize(payload));
        Test.stopTest();
        System.assertNotEquals(null, processId, 'HTTP Request process should save successfully');
    }

    @IsTest
    static void testSaveProcess_newFieldsConfigFormat_succeeds() {
        // New {recordTypeId, fields} format should pass validation
        Map<String, Object> step = new Map<String, Object>{
            'name'         => 'Create With New Format',
            'sequence'     => 1,
            'type'         => 'Create Record',
            'targetObject' => 'Case',
            'fieldsConfig' => '{"fields":[{"apiName":"Subject","type":"STRING"}]}'
        };
        Map<String, Object> payload = new Map<String, Object>{
            'name'   => 'New Format Process',
            'stages' => new List<Object>{ new Map<String, Object>{
                'name'     => 'S1',
                'sequence' => 1,
                'steps'    => new List<Object>{ step }
            }}
        };
        Test.startTest();
        Id processId = ProcessBuilderController.saveProcess(JSON.serialize(payload));
        Test.stopTest();
        System.assertNotEquals(null, processId, 'New fields config format should save successfully');
    }
}
