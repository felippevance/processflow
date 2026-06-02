/**
 * Utility class for JSON operations shared across ProcessFlow classes.
 *
 * FieldsConfig__c JSON Schema (Step__c):
 *
 * For Create Record / Update Record steps:
 * {
 *   "_v": 1,                          // schema version
 *   "recordTypeId": "012...",          // optional Record Type
 *   "requiresApproval": false,         // optional approval flag
 *   "approvalProcessName": "My_AP",    // required if requiresApproval=true
 *   "onRejection": "Stop",             // "Stop" | "Execute Stage"
 *   "rejectionStageId": "a2t...",      // required if onRejection="Execute Stage"
 *   "fields": [
 *     {
 *       "apiName": "Subject",
 *       "label": "Subject",
 *       "type": "STRING",              // Apex DisplayType name
 *       "required": true,
 *       "defaultValue": null,
 *       "picklistValues": []           // populated for PICKLIST/MULTIPICKLIST
 *     }
 *   ]
 * }
 *
 * For HTTP Request steps:
 * {
 *   "_v": 1,
 *   "namedCredential": "My_API",
 *   "method": "POST",
 *   "path": "/v1/resource",
 *   "headers": [{"key": "X-Custom", "value": "foo"}],
 *   "bodyMappings": [{"jsonKey": "name", "processField": "FirstName"}],
 *   "responseMappings": [{"jsonPath": "id", "fieldValuesKey": "externalId"}],
 *   "timeout": 30,
 *   "retry": false,
 *   "onFailure": "stop"
 * }
 *
 * For Notification steps:
 * {
 *   "_v": 1,
 *   "messageTemplate": "Your message here."
 * }
 *
 * ExecutionData__c JSON Schema (Execution__c):
 * {
 *   "_v": 1,
 *   "fieldValues": { "FieldApiName": "value", ... },
 *   "createdRecords": {
 *     "stepId": {
 *       "__id": "record Salesforce Id",
 *       "__objectType": "Case",
 *       "FieldApiName": "value"   // snapshot of input data
 *     }
 *   }
 * }
 */
public with sharing class ProcessFlowJsonUtil {

    /**
     * Safely deserialize a JSON string to Map. Returns empty map on failure.
     */
    public static Map<String, Object> toMap(String jsonStr) {
        if (String.isBlank(jsonStr)) {
            return new Map<String, Object>();
        }
        try {
            Object parsed = JSON.deserializeUntyped(jsonStr);
            if (parsed instanceof Map<String, Object>) {
                return (Map<String, Object>) parsed;
            }
            return new Map<String, Object>();
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'ProcessFlowJsonUtil.toMap failed: ' + ex.getMessage());
            return new Map<String, Object>();
        }
    }

    /**
     * Safely deserialize a JSON string to List. Returns empty list on failure.
     */
    public static List<Object> toList(String jsonStr) {
        if (String.isBlank(jsonStr)) {
            return new List<Object>();
        }
        try {
            Object parsed = JSON.deserializeUntyped(jsonStr);
            if (parsed instanceof List<Object>) {
                return (List<Object>) parsed;
            }
            return new List<Object>();
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'ProcessFlowJsonUtil.toList failed: ' + ex.getMessage());
            return new List<Object>();
        }
    }

    /**
     * Parse FieldsConfig__c and return the fields array, handling both old array format
     * and new {recordTypeId, fields} object format.
     */
    public static List<Object> getFieldDefs(String fieldsConfig) {
        if (String.isBlank(fieldsConfig)) {
            return new List<Object>();
        }
        try {
            Object parsed = JSON.deserializeUntyped(fieldsConfig);
            if (parsed instanceof List<Object>) {
                return (List<Object>) parsed;
            }
            if (parsed instanceof Map<String, Object>) {
                Map<String, Object> cfg = (Map<String, Object>) parsed;
                if (cfg.containsKey('fields')) {
                    return (List<Object>) cfg.get('fields');
                }
            }
            return new List<Object>();
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'ProcessFlowJsonUtil.getFieldDefs failed: ' + ex.getMessage());
            return new List<Object>();
        }
    }

    /**
     * Parse FieldsConfig__c and return the full config map.
     */
    public static Map<String, Object> getFieldsConfigMap(String fieldsConfig) {
        if (String.isBlank(fieldsConfig)) {
            return new Map<String, Object>();
        }
        try {
            Object parsed = JSON.deserializeUntyped(fieldsConfig);
            if (parsed instanceof Map<String, Object>) {
                return (Map<String, Object>) parsed;
            }
            return new Map<String, Object>();
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'ProcessFlowJsonUtil.getFieldsConfigMap failed: ' + ex.getMessage());
            return new Map<String, Object>();
        }
    }

    /**
     * Returns the schema version from a JSON map, or 0 if absent.
     * Use to guard against schema evolution mismatches.
     */
    public static Integer getSchemaVersion(Map<String, Object> data) {
        if (data == null || !data.containsKey('_v')) return 0;
        try {
            return Integer.valueOf(data.get('_v'));
        } catch (Exception e) {
            return 0;
        }
    }

    /**
     * Validates that a parsed JSON map has a minimum schema version.
     * Returns true if valid, false if stale/missing version.
     */
    public static Boolean isSchemaVersionValid(Map<String, Object> data, Integer minVersion) {
        return getSchemaVersion(data) >= minVersion;
    }
}
