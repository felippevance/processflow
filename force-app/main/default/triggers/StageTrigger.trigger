trigger StageTrigger on Stage__c (before insert) {
    if (ExternalIdService.isTriggerExecuting()) return;
    ExternalIdService.setTriggerExecuting(true);
    try {
        // Gather parent Process IDs to fetch their ExternalId__c
        Set<Id> processIds = new Set<Id>();
        for (Stage__c s : Trigger.new) {
            if (String.isBlank(s.ExternalId__c) && s.Process__c != null) {
                processIds.add(s.Process__c);
            }
        }

        if (processIds.isEmpty()) return;

        Map<Id, Process__c> procMap = new Map<Id, Process__c>([
            SELECT Id, ExternalId__c FROM Process__c WHERE Id IN :processIds
        ]);

        for (Stage__c s : Trigger.new) {
            if (String.isBlank(s.ExternalId__c) && s.Process__c != null) {
                Process__c parent = procMap.get(s.Process__c);
                String prefix = (parent?.ExternalId__c != null && parent.ExternalId__c.length() >= 8)
                    ? parent.ExternalId__c.substring(0, 8)
                    : ExternalIdService.generatePrefix();
                s.ExternalId__c = ExternalIdService.forStage(prefix, s.Name, s.Sequence__c);
            }
        }
    } finally {
        ExternalIdService.setTriggerExecuting(false);
    }
}
