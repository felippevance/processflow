trigger ProcessFlowTrigger on Process__c (before insert, before update) {
    if (ExternalIdService.isTriggerExecuting()) return;
    ExternalIdService.setTriggerExecuting(true);
    try {
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
    } finally {
        ExternalIdService.setTriggerExecuting(false);
    }
}
