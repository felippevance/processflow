/**
 * Scheduled job to archive old completed/failed/cancelled Execution__c records.
 * Deletes executions older than 90 days with a FinalStatus set.
 * Also deletes orphaned ExecutionLog__c records.
 *
 * Schedule via Setup > Apex Classes > Schedule, or:
 * System.schedule('ProcessFlow Execution Cleanup', '0 0 2 * * ?', new ExecutionCleanupJob());
 */
global class ExecutionCleanupJob implements Schedulable {

    global void execute(SchedulableContext ctx) {
        cleanOldExecutions(90);
    }

    public static void cleanOldExecutions(Integer daysOld) {
        DateTime cutoff = System.now().addDays(-daysOld);

        // Delete execution logs for old completed executions first (child records)
        List<Execution__c> oldExecs = [
            SELECT Id FROM Execution__c
            WHERE FinalStatus__c != null
              AND CompletedAt__c < :cutoff
            LIMIT 200
        ];

        if (oldExecs.isEmpty()) return;

        Set<Id> execIds = new Map<Id, Execution__c>(oldExecs).keySet();

        List<ExecutionLog__c> logsToDelete = [
            SELECT Id FROM ExecutionLog__c
            WHERE Execution__c IN :execIds
        ];
        if (!logsToDelete.isEmpty()) {
            Database.delete(logsToDelete, false);
        }

        Database.delete(oldExecs, false);
        System.debug('ExecutionCleanupJob: deleted ' + oldExecs.size() + ' old executions and their logs.');
    }
}
