@IsTest
private class ProcessPicklistProviderTest {

    @TestSetup
    static void setup() {
        Process__c proc = new Process__c(
            Name = 'Picklist Test Process',
            IsActive__c = true,
            IsCurrentVersion__c = true
        );
        insert proc;

        // Insert an inactive process — should not appear in picklist
        Process__c inactive = new Process__c(
            Name = 'Inactive Picklist Process',
            IsActive__c = false,
            IsCurrentVersion__c = true
        );
        insert inactive;
    }

    @IsTest
    static void testGetDefaultValue_returnsRowWithEmptyStringValue() {
        ProcessPicklistProvider provider = new ProcessPicklistProvider();

        Test.startTest();
        VisualEditor.DataRow row = provider.getDefaultValue();
        Test.stopTest();

        System.assertNotEquals(null, row, 'Default value row should not be null');
        System.assertEquals('', row.getValue(), 'Default row value should be empty string');
        System.assertEquals('-- All Active Processes --', row.getLabel(), 'Default row label should match');
    }

    @IsTest
    static void testGetValues_includesDefaultRow() {
        ProcessPicklistProvider provider = new ProcessPicklistProvider();

        Test.startTest();
        VisualEditor.DynamicPickListRows rows = provider.getValues();
        Test.stopTest();

        System.assertNotEquals(null, rows, 'Rows should not be null');
        // The default row (empty value) plus one active process = at least 2 rows
        List<VisualEditor.DataRow> rowList = rows.getDataRows();
        System.assert(rowList.size() >= 2, 'Should have at least 2 rows (default + active process)');

        // Verify the default row with empty value is present
        Boolean hasDefaultRow = false;
        for (VisualEditor.DataRow row : rowList) {
            if (row.getValue() == '') {
                hasDefaultRow = true;
                break;
            }
        }
        System.assertEquals(true, hasDefaultRow, 'Should include a row with empty string value');
    }

    @IsTest
    static void testGetValues_includesActiveProcesses() {
        ProcessPicklistProvider provider = new ProcessPicklistProvider();

        Test.startTest();
        VisualEditor.DynamicPickListRows rows = provider.getValues();
        Test.stopTest();

        List<VisualEditor.DataRow> rowList = rows.getDataRows();

        // Verify the active process is in the picklist
        Boolean hasActiveProcess = false;
        for (VisualEditor.DataRow row : rowList) {
            if (row.getLabel() == 'Picklist Test Process') {
                hasActiveProcess = true;
            }
        }
        System.assertEquals(true, hasActiveProcess, 'Active process should be in picklist');

        // Verify the inactive process is NOT in the picklist
        Boolean hasInactiveProcess = false;
        for (VisualEditor.DataRow row : rowList) {
            if (row.getLabel() == 'Inactive Picklist Process') {
                hasInactiveProcess = true;
            }
        }
        System.assertEquals(false, hasInactiveProcess, 'Inactive process should not be in picklist');
    }

    @IsTest
    static void testGetValues_emptyWhenNoActiveProcesses() {
        // Delete all active processes
        delete [SELECT Id FROM Process__c WHERE IsActive__c = true];

        ProcessPicklistProvider provider = new ProcessPicklistProvider();

        Test.startTest();
        VisualEditor.DynamicPickListRows rows = provider.getValues();
        Test.stopTest();

        List<VisualEditor.DataRow> rowList = rows.getDataRows();
        // Should only have the default row
        System.assertEquals(1, rowList.size(), 'Should only have the default row when no active processes');
        System.assertEquals('', rowList[0].getValue(), 'Only row should be the default empty row');
    }
}
