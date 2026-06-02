public with sharing class ProcessExecutionEngine {

    public class StepResult {
        @AuraEnabled public String  createdRecordId   { get; set; }
        @AuraEnabled public String  createdObjectType { get; set; }
        @AuraEnabled public Boolean isWaitingApproval { get; set; }
        @AuraEnabled public String  rejectionStageId  { get; set; }
        @AuraEnabled public String  onRejection       { get; set; }
    }

    // Called from test/anonymous Apex — queries step from DB
    public static StepResult execute(Id stepId, Map<String, Object> inputData, Id executionId) {
        Step__c step = [
            SELECT Id, Type__c, TargetObject__c, FieldsConfig__c
            FROM Step__c WHERE Id = :stepId WITH SECURITY_ENFORCED
        ];
        return executeWithData(stepId, step.Type__c, step.TargetObject__c, step.FieldsConfig__c, inputData, executionId);
    }

    // Called from LWC via controller — step data already in memory, no extra query
    public static StepResult executeWithData(
        Id stepId, String stepType, String targetObject, String fieldsConfig,
        Map<String, Object> inputData, Id executionId
    ) {
        StepResult result = new StepResult();

        switch on stepType {
            when 'Create Record' {
                Id createdId = createRecord(targetObject, fieldsConfig, inputData);
                result.createdRecordId   = createdId;
                result.createdObjectType = targetObject;

                // Check if this step requires approval
                Object parsed = JSON.deserializeUntyped(fieldsConfig);
                Map<String, Object> cfg = parsed instanceof Map<String, Object>
                    ? (Map<String, Object>) parsed
                    : new Map<String, Object>();
                Boolean requiresApproval = cfg.containsKey('requiresApproval') && (Boolean) cfg.get('requiresApproval');
                String approvalProcessName = (String) cfg.get('approvalProcessName');

                if (requiresApproval && String.isNotBlank(approvalProcessName) && createdId != null) {
                    ApprovalService.submit(createdId, approvalProcessName, executionId);
                    result.isWaitingApproval = true;
                    result.onRejection       = (String) cfg.get('onRejection');
                    result.rejectionStageId  = (String) cfg.get('rejectionStageId');
                }
            }
            when 'Update Record' {
                updateRecord(targetObject, fieldsConfig, inputData);
            }
            when 'Notification' {
                sendNotification(fieldsConfig, inputData);
            }
            when 'HTTP Request' {
                // Get current fieldValues from execution context for body mapping
                Map<String, Object> currentFieldValues = inputData.containsKey('fieldValues')
                    ? (Map<String, Object>) inputData.get('fieldValues')
                    : inputData;
                Map<String, Object> responseValues = HttpRequestExecutor.execute(fieldsConfig, currentFieldValues);
                // Merge response values into inputData so they flow into ExecutionData__c
                inputData.putAll(responseValues);
            }
        }

        Boolean isLastStep = inputData.containsKey('isLastStep') && (Boolean) inputData.get('isLastStep');

        // If waiting for approval, do not advance execution state — polling handles this
        if (result.isWaitingApproval == true) return result;

        if (isLastStep) {
            Execution__c completed = new Execution__c(
                Id             = executionId,
                FinalStatus__c = 'Completed',
                CompletedAt__c = System.now()
            );
            update completed;
        } else {
            Execution__c existing = [
                SELECT Id, ExecutionData__c FROM Execution__c WHERE Id = :executionId WITH SECURITY_ENFORCED
            ];
            Map<String, Object> execData = String.isBlank(existing.ExecutionData__c)
                ? new Map<String, Object>()
                : (Map<String, Object>) JSON.deserializeUntyped(existing.ExecutionData__c);

            // Merge fieldValues from current step input
            Map<String, Object> fieldValues = execData.containsKey('fieldValues')
                ? (Map<String, Object>) execData.get('fieldValues')
                : new Map<String, Object>();
            for (String k : inputData.keySet()) {
                if (k != 'isLastStep' && k != 'recordId') fieldValues.put(k, inputData.get(k));
            }
            execData.put('fieldValues', fieldValues);

            // If a record was created, snapshot input fields under stepId for condition evaluation
            if (result.createdRecordId != null) {
                Map<String, Object> createdRecords = execData.containsKey('createdRecords')
                    ? (Map<String, Object>) execData.get('createdRecords')
                    : new Map<String, Object>();
                Map<String, Object> snapshot = new Map<String, Object>();
                for (String k : inputData.keySet()) {
                    if (k != 'isLastStep' && k != 'recordId') snapshot.put(k, inputData.get(k));
                }
                snapshot.put('__id', result.createdRecordId);
                snapshot.put('__objectType', result.createdObjectType);
                createdRecords.put(String.valueOf(stepId), snapshot);
                execData.put('createdRecords', createdRecords);
            }

            execData.put('_v', 1);
            existing.CurrentStep__c = stepId;
            existing.ExecutionData__c = JSON.serialize(execData);
            update existing;
        }

        return result;
    }

    private static Schema.SObjectType resolveObjectType(String objectApiName) {
        if (String.isBlank(objectApiName)) throw new AuraHandledException('Target object not specified.');
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        if (objType == null) throw new AuraHandledException('Object not found: ' + objectApiName);
        Schema.DescribeSObjectResult describeResult = objType.getDescribe();
        if (!describeResult.isAccessible()) throw new AuraHandledException('Insufficient access to object: ' + objectApiName);
        return objType;
    }

    private static Id createRecord(String objectApiName, String fieldsConfig, Map<String, Object> inputData) {
        Schema.SObjectType objType = resolveObjectType(objectApiName);
        if (!objType.getDescribe().isCreateable()) throw new AuraHandledException('Cannot create records on: ' + objectApiName);

        SObject newRecord = objType.newSObject();

        // Parse fieldsConfig — support both old array format and new {recordTypeId, fields} format
        Object parsed = JSON.deserializeUntyped(fieldsConfig);
        List<Object> fieldDefs;
        String recordTypeId = null;

        if (parsed instanceof List<Object>) {
            // Old format: flat array
            fieldDefs = (List<Object>) parsed;
        } else {
            // New format: {recordTypeId, fields}
            Map<String, Object> cfg = (Map<String, Object>) parsed;
            recordTypeId = (String) cfg.get('recordTypeId');
            fieldDefs = cfg.get('fields') != null ? (List<Object>) cfg.get('fields') : new List<Object>();
        }

        if (String.isNotBlank(recordTypeId)) {
            newRecord.put('RecordTypeId', (Id) recordTypeId);
        }

        for (Object fc : fieldDefs) {
            Map<String, Object> fieldDef = (Map<String, Object>) fc;
            String apiName   = (String) fieldDef.get('apiName');
            String fieldType = (String) fieldDef.get('type');
            if (inputData.containsKey(apiName) && inputData.get(apiName) != null) {
                newRecord.put(apiName, coerceValue(inputData.get(apiName), fieldType));
            }
        }

        // Strip fields the running user cannot write
        SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, new List<SObject>{ newRecord });
        List<SObject> stripped = decision.getRecords();
        if (stripped.isEmpty()) throw new AuraHandledException('Cannot create record on ' + objectApiName + ': all fields were stripped by FLS.');
        insert stripped[0];
        return stripped[0].Id;
    }

    private static void updateRecord(String objectApiName, String fieldsConfig, Map<String, Object> inputData) {
        if (!inputData.containsKey('recordId')) return;

        Id recordId = (Id) inputData.get('recordId');
        Schema.SObjectType objType = resolveObjectType(objectApiName);
        if (!objType.getDescribe().isUpdateable()) throw new AuraHandledException('Cannot update records on: ' + objectApiName);

        SObject record = objType.newSObject(recordId);

        Object parsed = JSON.deserializeUntyped(fieldsConfig);
        List<Object> fieldDefs = parsed instanceof List<Object>
            ? (List<Object>) parsed
            : (List<Object>) ((Map<String, Object>) parsed).get('fields');
        if (fieldDefs == null) fieldDefs = new List<Object>();

        for (Object fc : fieldDefs) {
            Map<String, Object> fieldDef = (Map<String, Object>) fc;
            String apiName   = (String) fieldDef.get('apiName');
            String fieldType = (String) fieldDef.get('type');
            if (inputData.containsKey(apiName) && inputData.get(apiName) != null) {
                record.put(apiName, coerceValue(inputData.get(apiName), fieldType));
            }
        }

        // Strip fields the running user cannot update
        SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, new List<SObject>{ record });
        List<SObject> strippedUpdate = decision.getRecords();
        if (strippedUpdate.isEmpty()) throw new AuraHandledException('Cannot update record on ' + objectApiName + ': all fields were stripped by FLS.');
        update strippedUpdate[0];
    }

    private static void sendNotification(String fieldsConfig, Map<String, Object> inputData) {
        Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(fieldsConfig);
        String rawMessage = (String) config.get('messageTemplate');
        // Strip HTML tags and sanitize to prevent XSS in Chatter
        String message = sanitizeMessage(rawMessage);
        Id recipientId = inputData.containsKey('recipientId')
            ? (Id) inputData.get('recipientId')
            : UserInfo.getUserId();
        ConnectApi.ChatterFeeds.postFeedElement(null, recipientId, ConnectApi.FeedElementType.FeedItem, message);
    }

    private static String sanitizeMessage(String input) {
        if (String.isBlank(input)) return '';
        // Remove HTML tags
        String sanitized = input.replaceAll('<[^>]+>', '');
        // Decode common HTML entities to plain text
        sanitized = sanitized.replace('&amp;',  '&')
                             .replace('&lt;',   '<')
                             .replace('&gt;',   '>')
                             .replace('&quot;', '"')
                             .replace('&#39;',  '\'')
                             .replace('&nbsp;', ' ');
        // Trim and limit length to prevent overflow
        return sanitized.trim().left(1000);
    }

    private static Object coerceValue(Object value, String fieldType) {
        if (value == null) return null;
        String strVal = String.valueOf(value).trim();
        if (String.isBlank(strVal)) return null;
        String t = (fieldType == null ? 'STRING' : fieldType.toUpperCase());
        try {
            if (t == 'DATE')                                         return Date.valueOf(strVal);
            if (t == 'DATETIME')                                     return DateTime.valueOf(strVal.replace('T', ' '));
            if (t == 'BOOLEAN')                                      return Boolean.valueOf(strVal);
            if (t == 'INTEGER')                                      return Integer.valueOf(strVal);
            if (t == 'DOUBLE' || t == 'CURRENCY' || t == 'PERCENT') return Decimal.valueOf(strVal);
            if (t == 'LONG')                                         return Long.valueOf(strVal);
        } catch (Exception e) {
            return strVal;
        }
        return strVal;
    }
}
