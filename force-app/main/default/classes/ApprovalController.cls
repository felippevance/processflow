public with sharing class ApprovalController {

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getApprovalProcesses() {
        List<Map<String, String>> result = new List<Map<String, String>>();
        try {
            for (ProcessDefinition pd : [
                SELECT Id, DeveloperName, Name
                FROM ProcessDefinition
                WHERE Type = 'Approval'
                ORDER BY Name
            ]) {
                result.add(new Map<String, String>{
                    'value' => pd.DeveloperName,
                    'label' => pd.Name
                });
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error loading approval processes: ' + e.getMessage());
        }
        return result;
    }

    @AuraEnabled
    public static ApprovalService.ApprovalResult checkApprovalStatus(Id executionId) {
        return ApprovalService.checkStatus(executionId);
    }

    @AuraEnabled
    public static void cancelApproval(Id executionId) {
        Execution__c exec = [
            SELECT Id, PendingApprovalId__c, CurrentStage__c
            FROM Execution__c WHERE Id = :executionId WITH SECURITY_ENFORCED
        ];

        if (String.isNotBlank(exec.PendingApprovalId__c)) {
            try {
                // Find the active workitem for this process instance
                List<ProcessInstanceWorkitem> workItems = [
                    SELECT Id FROM ProcessInstanceWorkitem
                    WHERE ProcessInstanceId = :exec.PendingApprovalId__c
                    LIMIT 1
                ];
                if (!workItems.isEmpty()) {
                    Approval.ProcessWorkitemRequest recallReq = new Approval.ProcessWorkitemRequest();
                    recallReq.setAction('Removed');
                    recallReq.setWorkitemId(workItems[0].Id);
                    Approval.process(recallReq);
                }
            } catch (Exception e) {
                System.debug('Could not recall approval: ' + e.getMessage());
            }
        }

        exec.FinalStatus__c             = 'Cancelled';
        exec.CompletedAt__c             = System.now();
        exec.PendingApprovalId__c       = null;
        exec.PendingApprovalRecordId__c = null;
        update exec;
    }
}
