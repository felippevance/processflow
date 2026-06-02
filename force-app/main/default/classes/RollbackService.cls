public with sharing class RollbackService {

    public static void rollbackStage(Id executionId, Id stageId) {
        Execution__c exec = [
            SELECT Id, ExecutionData__c FROM Execution__c
            WHERE Id = :executionId WITH SECURITY_ENFORCED
        ];

        // Get stepIds belonging to this stage
        Set<String> stageStepIds = new Set<String>();
        for (Step__c st : [
            SELECT Id FROM Step__c WHERE Stage__c = :stageId WITH SECURITY_ENFORCED
        ]) {
            stageStepIds.add(String.valueOf(st.Id));
        }

        // Parse createdRecords from ExecutionData
        Map<String, Object> execData = String.isBlank(exec.ExecutionData__c)
            ? new Map<String, Object>()
            : (Map<String, Object>) JSON.deserializeUntyped(exec.ExecutionData__c);

        Map<String, Object> createdRecords = execData.containsKey('createdRecords')
            ? (Map<String, Object>) execData.get('createdRecords')
            : new Map<String, Object>();

        // Group record Ids to delete by SObject type
        Map<String, List<Id>> toDeleteByType = new Map<String, List<Id>>();
        for (String stepId : createdRecords.keySet()) {
            if (!stageStepIds.contains(stepId)) continue;
            Map<String, Object> rec = (Map<String, Object>) createdRecords.get(stepId);
            String objectType = (String) rec.get('__objectType');
            String recordId   = (String) rec.get('__id');
            if (String.isBlank(objectType) || String.isBlank(recordId)) continue;
            if (!toDeleteByType.containsKey(objectType)) {
                toDeleteByType.put(objectType, new List<Id>());
            }
            toDeleteByType.get(objectType).add((Id) recordId);
        }

        // Delete each group — ignore individual failures (record may already be gone)
        for (String objectType : toDeleteByType.keySet()) {
            List<Id> idsToDelete = toDeleteByType.get(objectType);
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectType);
            if (objType == null) continue;
            List<SObject> records = new List<SObject>();
            for (Id rid : idsToDelete) {
                records.add(objType.newSObject(rid));
            }
            try {
                Database.delete(records, false); // allOrNothing=false
            } catch (Exception e) {
                System.debug('Rollback delete error for ' + objectType + ': ' + e.getMessage());
            }
        }

        // Mark execution as Failed
        exec.FinalStatus__c = 'Failed';
        exec.CompletedAt__c = System.now();
        update exec;
    }
}
