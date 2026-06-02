trigger StepTrigger on Step__c (before insert) {
    Set<Id> stageIds = new Set<Id>();
    for (Step__c st : Trigger.new) {
        if (String.isBlank(st.ExternalId__c) && st.Stage__c != null) {
            stageIds.add(st.Stage__c);
        }
    }

    if (stageIds.isEmpty()) return;

    Map<Id, Stage__c> stageMap = new Map<Id, Stage__c>([
        SELECT Id, Sequence__c, ExternalId__c FROM Stage__c WHERE Id IN :stageIds
    ]);

    for (Step__c st : Trigger.new) {
        if (String.isBlank(st.ExternalId__c) && st.Stage__c != null) {
            Stage__c parent = stageMap.get(st.Stage__c);
            String prefix = parent?.ExternalId__c != null
                ? parent.ExternalId__c.substring(0, 8)
                : ExternalIdService.generatePrefix();
            Decimal stageSeq = parent?.Sequence__c;
            st.ExternalId__c = ExternalIdService.forStep(prefix, st.Name, stageSeq, st.Sequence__c);
        }
    }
}
