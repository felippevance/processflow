@IsTest
private class ProcessViewerControllerTest {

    @TestSetup
    static void setup() {
        Process__c proc = new Process__c(
            Name = 'Viewer Test Process',
            IsActive__c = true,
            Version__c = 2,
            IsCurrentVersion__c = true,
            Description__c = 'A viewer test process'
        );
        insert proc;
    }

    @IsTest
    static void testGetProcessDetails_returnsProcessWithVersionFields() {
        Process__c proc = [SELECT Id FROM Process__c WHERE Name = 'Viewer Test Process' LIMIT 1];

        Test.startTest();
        Process__c result = ProcessViewerController.getProcessDetails(proc.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return the process');
        System.assertEquals('Viewer Test Process', result.Name, 'Name should match');
        System.assertEquals('A viewer test process', result.Description__c, 'Description should match');
        System.assertEquals(true, result.IsActive__c, 'IsActive should be true');
        System.assertEquals(2, result.Version__c, 'Version should match');
        System.assertEquals(true, result.IsCurrentVersion__c, 'IsCurrentVersion should be true');
    }

    @IsTest
    static void testGetProcessDetails_inactiveProcess() {
        Process__c inactive = new Process__c(
            Name = 'Inactive Process',
            IsActive__c = false,
            Version__c = 1,
            IsCurrentVersion__c = false,
            Description__c = 'Old version'
        );
        insert inactive;

        Test.startTest();
        Process__c result = ProcessViewerController.getProcessDetails(inactive.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return inactive process too');
        System.assertEquals(false, result.IsActive__c, 'IsActive should be false');
        System.assertEquals(false, result.IsCurrentVersion__c, 'IsCurrentVersion should be false');
    }
}
