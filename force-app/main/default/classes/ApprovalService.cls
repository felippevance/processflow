public with sharing class ApprovalService {

    public class ApprovalResult {
        @AuraEnabled public String status     { get; set; }
        @AuraEnabled public String instanceId { get; set; }
    }

    public static ApprovalResult submit(Id recordId, String approvalProcessName, Id executionId) {
        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
        req.setObjectId(recordId);
        req.setProcessDefinitionNameOrId(approvalProcessName);
        req.setSubmitterId(UserInfo.getUserId());

        Approval.ProcessResult result;
        try {
            result = Approval.process(req);
        } catch (Exception e) {
            throw new AuraHandledException('Failed to submit record for approval: ' + e.getMessage());
        }
        if (result != null && !result.isSuccess()) {
            List<String> errors = new List<String>();
            for (Database.Error err : result.getErrors()) {
                errors.add(err.getMessage());
            }
            throw new AuraHandledException('Approval submission failed: ' + String.join(errors, '; '));
        }

        Execution__c exec = new Execution__c(
            Id                         = executionId,
            PendingApprovalId__c       = result.getInstanceId(),
            PendingApprovalRecordId__c = recordId
        );
        update exec;

        ApprovalResult ar = new ApprovalResult();
        ar.status     = 'Pending';
        ar.instanceId = result.getInstanceId();
        return ar;
    }

    public static ApprovalResult checkStatus(Id executionId) {
        Execution__c exec = [
            SELECT PendingApprovalId__c, PendingApprovalRecordId__c
            FROM Execution__c WHERE Id = :executionId
            WITH SECURITY_ENFORCED
        ];

        ApprovalResult ar = new ApprovalResult();

        if (String.isBlank(exec.PendingApprovalId__c)) {
            ar.status = 'Approved';
            return ar;
        }

        List<ProcessInstance> instances = [
            SELECT Id, Status FROM ProcessInstance
            WHERE Id = :exec.PendingApprovalId__c
            LIMIT 1
        ];

        ar.instanceId = exec.PendingApprovalId__c;
        ar.status = instances.isEmpty() ? 'Approved' : instances[0].Status;
        return ar;
    }

    public static void clearPendingApproval(Id executionId) {
        Execution__c exec = new Execution__c(
            Id                         = executionId,
            PendingApprovalId__c       = null,
            PendingApprovalRecordId__c = null
        );
        update exec;
    }
}
