trigger ProcessFlowTrigger on Process__c (before insert, before update) {
    for (Process__c proc : Trigger.new) {
        if (String.isBlank(proc.ExternalId__c)) {
            String prefix = ExternalIdService.generatePrefix();
            proc.ExternalId__c = ExternalIdService.forProcess(
                prefix,
                proc.Name,
                proc.Version__c
            );
        }
    }
}
