public with sharing class ProcessViewerController {

    @AuraEnabled(cacheable=true)
    public static Process__c getProcessDetails(Id processId) {
        return [
            SELECT Id, Name, Description__c, IsActive__c, Version__c, IsCurrentVersion__c
            FROM Process__c
            WHERE Id = :processId
            WITH SECURITY_ENFORCED
        ];
    }
}
