public with sharing class ProcessBuilderController {

    public class FieldInfo {
        @AuraEnabled public String apiName          { get; set; }
        @AuraEnabled public String label            { get; set; }
        @AuraEnabled public String type             { get; set; }
        @AuraEnabled public Boolean required        { get; set; }
        @AuraEnabled public List<String> picklistValues { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldInfo> getObjectFields(String objectApiName) {
        List<FieldInfo> fields = new List<FieldInfo>();
        try {
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
            if (objType == null) throw new AuraHandledException('Object not found: ' + objectApiName);

            Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult f = fieldMap.get(fieldName).getDescribe();
                if (!f.isAccessible()) continue;
                // Skip system/audit fields: only show fields the user can actually fill in
                if (!f.isCreateable() && !f.isUpdateable()) continue;

                FieldInfo fi = new FieldInfo();
                fi.apiName  = f.getName();
                fi.label    = f.getLabel();
                fi.type     = String.valueOf(f.getType());
                fi.required = !f.isNillable() && f.isCreateable();
                fi.picklistValues = new List<String>();
                if (f.getType() == Schema.DisplayType.PICKLIST || f.getType() == Schema.DisplayType.MULTIPICKLIST) {
                    for (Schema.PicklistEntry pe : f.getPicklistValues()) {
                        if (pe.isActive()) fi.picklistValues.add(pe.getLabel());
                    }
                }
                fields.add(fi);
            }
            Map<String, FieldInfo> sorted = new Map<String, FieldInfo>();
            for (FieldInfo fi : fields) { sorted.put(fi.label + fi.apiName, fi); }
            List<String> keys = new List<String>(sorted.keySet());
            keys.sort();
            fields.clear();
            for (String k : keys) { fields.add(sorted.get(k)); }
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error loading fields: ' + e.getMessage());
        }
        return fields;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getRecordTypes(String objectApiName) {
        List<Map<String, String>> result = new List<Map<String, String>>();
        try {
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
            if (objType == null) return result;
            for (Schema.RecordTypeInfo rt : objType.getDescribe().getRecordTypeInfos()) {
                if (!rt.isAvailable() || rt.isMaster()) continue;
                Map<String, String> entry = new Map<String, String>{
                    'id'    => rt.getRecordTypeId(),
                    'name'  => rt.getName(),
                    'label' => rt.getName()
                };
                result.add(entry);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error loading record types: ' + e.getMessage());
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getNamedCredentials() {
        List<Map<String, String>> result = new List<Map<String, String>>();
        try {
            List<NamedCredential> creds = [
                SELECT Id, DeveloperName, MasterLabel
                FROM NamedCredential
                ORDER BY MasterLabel
            ];
            for (NamedCredential nc : creds) {
                result.add(new Map<String, String>{
                    'value' => nc.DeveloperName,
                    'label' => nc.MasterLabel
                });
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error loading Named Credentials: ' + e.getMessage());
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getApprovalProcesses() {
        return ApprovalController.getApprovalProcesses();
    }

    private static void validatePayload(Map<String, Object> payload) {
        String name = (String) payload.get('name');
        if (String.isBlank(name)) throw new AuraHandledException('Process name is required.');

        List<Object> stages = (List<Object>) payload.get('stages');
        if (stages == null || stages.isEmpty()) throw new AuraHandledException('At least one stage is required.');

        Integer stageIdx = 0;
        for (Object stageObj : stages) {
            stageIdx++;
            Map<String, Object> stage = (Map<String, Object>) stageObj;
            if (String.isBlank((String) stage.get('name'))) {
                throw new AuraHandledException('Stage ' + stageIdx + ' is missing a name.');
            }
            List<Object> steps = (List<Object>) stage.get('steps');
            if (steps == null || steps.isEmpty()) {
                throw new AuraHandledException('Stage "' + stage.get('name') + '" must have at least one step.');
            }
            Integer stepIdx = 0;
            for (Object stepObj : steps) {
                stepIdx++;
                Map<String, Object> step = (Map<String, Object>) stepObj;
                if (String.isBlank((String) step.get('name'))) {
                    throw new AuraHandledException('Step ' + stepIdx + ' in stage "' + stage.get('name') + '" is missing a name.');
                }
                if (String.isBlank((String) step.get('type'))) {
                    throw new AuraHandledException('Step "' + step.get('name') + '" is missing a type.');
                }
                String stepType = (String) step.get('type');
                if ((stepType == 'Create Record' || stepType == 'Update Record') && String.isBlank((String) step.get('targetObject'))) {
                    throw new AuraHandledException('Step "' + step.get('name') + '" requires a target object.');
                }
                if (stepType == 'HTTP Request') {
                    Map<String,Object> httpCfg = null;
                    try {
                        httpCfg = (Map<String,Object>) JSON.deserializeUntyped((String) step.get('fieldsConfig'));
                    } catch(Exception e) {}
                    if (httpCfg == null || String.isBlank((String) httpCfg.get('namedCredential'))) {
                        throw new AuraHandledException('HTTP Request step "' + step.get('name') + '" requires a Named Credential.');
                    }
                }

                // Validate FieldsConfig JSON integrity for Create/Update Record steps
                if (stepType == 'Create Record' || stepType == 'Update Record') {
                    String fieldsConfigStr = (String) step.get('fieldsConfig');
                    if (String.isNotBlank(fieldsConfigStr)) {
                        try {
                            Object parsed = JSON.deserializeUntyped(fieldsConfigStr);
                            // Accept both old array format and new {fields:[]} format
                            if (!(parsed instanceof List<Object>) && !(parsed instanceof Map<String,Object>)) {
                                throw new AuraHandledException('Step "' + step.get('name') + '" has invalid fields configuration.');
                            }
                        } catch (JSONException e) {
                            throw new AuraHandledException('Step "' + step.get('name') + '" has invalid JSON in fields configuration: ' + e.getMessage());
                        }
                    }
                }

                // Validate Notification step has a non-empty message template
                if (stepType == 'Notification') {
                    Map<String,Object> notifCfg = null;
                    try {
                        notifCfg = (Map<String,Object>) JSON.deserializeUntyped((String) step.get('fieldsConfig'));
                    } catch(Exception e) {}
                    if (notifCfg == null || String.isBlank((String) notifCfg.get('messageTemplate'))) {
                        throw new AuraHandledException('Notification step "' + step.get('name') + '" requires a message template.');
                    }
                }
            }
        }
    }

    @AuraEnabled
    public static Id saveProcess(String payloadJson) {
        try {
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
            validatePayload(payload);

            Savepoint sp = Database.setSavepoint();
            try {
                Process__c process = new Process__c(
                    Name                  = (String) payload.get('name'),
                    Description__c = (String) payload.get('description'),
                    IsActive__c    = payload.get('isActive') == null ? true : (Boolean) payload.get('isActive')
                );
                insert process;

                List<Object> stagesData = (List<Object>) payload.get('stages');
                if (stagesData != null) {
                    for (Object stageObj : stagesData) {
                        Map<String, Object> stageData = (Map<String, Object>) stageObj;

                        Stage__c stage = new Stage__c(
                            Name                = (String) stageData.get('name'),
                            Sequence__c         = (Decimal) stageData.get('sequence'),
                            Process__c          = process.Id,
                            ConditionLogic__c   = String.isBlank((String) stageData.get('conditionLogic')) ? 'AND' : (String) stageData.get('conditionLogic'),
                            ConditionsConfig__c = (String) stageData.get('conditionsConfig')
                        );
                        insert stage;

                        List<Object> stepsData = (List<Object>) stageData.get('steps');
                        if (stepsData != null) {
                            List<Step__c> steps = new List<Step__c>();
                            for (Object stepObj : stepsData) {
                                Map<String, Object> stepData = (Map<String, Object>) stepObj;
                                steps.add(new Step__c(
                                    Name                    = (String) stepData.get('name'),
                                    Sequence__c      = (Decimal) stepData.get('sequence'),
                                    Stage__c         = stage.Id,
                                    Type__c          = (String) stepData.get('type'),
                                    TargetObject__c  = (String) stepData.get('targetObject'),
                                    FieldsConfig__c  = (String) stepData.get('fieldsConfig'),
                                    IsRequired__c    = stepData.get('isRequired') == null ? false : (Boolean) stepData.get('isRequired')
                                ));
                            }
                            insert steps;
                        }
                    }
                }

                return process.Id;

            } catch (Exception e) {
                Database.rollback(sp);
                throw new AuraHandledException(e.getMessage());
            }
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Invalid payload: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Id cloneProcess(Id processId) {
        Process__c original = [
            SELECT Id, Name, Description__c, IsActive__c, Version__c
            FROM Process__c WHERE Id = :processId
            WITH SECURITY_ENFORCED
        ];

        List<Stage__c> stages = [
            SELECT Id, Name, Sequence__c, ConditionLogic__c, ConditionsConfig__c FROM Stage__c
            WHERE Process__c = :processId
            WITH SECURITY_ENFORCED
            ORDER BY Sequence__c ASC
        ];

        List<Id> stageIds = new List<Id>();
        for (Stage__c s : stages) stageIds.add(s.Id);

        List<Step__c> steps = [
            SELECT Id, Name, Sequence__c, Stage__c, Type__c,
                   TargetObject__c, FieldsConfig__c, IsRequired__c
            FROM Step__c
            WHERE Stage__c IN :stageIds
            WITH SECURITY_ENFORCED
            ORDER BY Sequence__c ASC
        ];

        Savepoint sp = Database.setSavepoint();
        try {
            // Mark old version as not current
            original.IsCurrentVersion__c = false;
            update original;

            // Create new version
            Process__c newProcess = new Process__c(
                Name               = original.Name,
                Description__c     = original.Description__c,
                IsActive__c        = true,
                Version__c         = (original.Version__c == null ? 1 : original.Version__c) + 1,
                IsCurrentVersion__c = true
            );
            insert newProcess;

            // Clone stages and steps
            Map<Id, Id> stageIdMap = new Map<Id, Id>();
            for (Stage__c s : stages) {
                Stage__c newStage = new Stage__c(
                    Name                = s.Name,
                    Sequence__c         = s.Sequence__c,
                    Process__c          = newProcess.Id,
                    ConditionLogic__c   = s.ConditionLogic__c,
                    ConditionsConfig__c = s.ConditionsConfig__c
                );
                insert newStage;
                stageIdMap.put(s.Id, newStage.Id);
            }

            List<Step__c> newSteps = new List<Step__c>();
            for (Step__c st : steps) {
                newSteps.add(new Step__c(
                    Name            = st.Name,
                    Sequence__c     = st.Sequence__c,
                    Stage__c        = stageIdMap.get(st.Stage__c),
                    Type__c         = st.Type__c,
                    TargetObject__c = st.TargetObject__c,
                    FieldsConfig__c = st.FieldsConfig__c,
                    IsRequired__c   = st.IsRequired__c
                ));
            }
            if (!newSteps.isEmpty()) insert newSteps;

            return newProcess.Id;

        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('Clone failed: ' + e.getMessage());
        }
    }
}
