public with sharing class ConditionEvaluator {

    public static Boolean evaluate(String conditionsJson, String logic, String executionDataJson) {
        if (String.isBlank(conditionsJson)) return true;

        List<Object> conditions;
        try {
            conditions = (List<Object>) JSON.deserializeUntyped(conditionsJson);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'ConditionEvaluator: malformed JSON, allowing stage: ' + e.getMessage());
            return true; // malformed JSON — don't block execution, but log it
        }
        if (conditions == null || conditions.isEmpty()) return true;

        Map<String, Object> execData = String.isBlank(executionDataJson)
            ? new Map<String, Object>()
            : (Map<String, Object>) JSON.deserializeUntyped(executionDataJson);

        Map<String, Object> fieldValues = execData.containsKey('fieldValues')
            ? (Map<String, Object>) execData.get('fieldValues')
            : new Map<String, Object>();

        Map<String, Object> createdRecords = execData.containsKey('createdRecords')
            ? (Map<String, Object>) execData.get('createdRecords')
            : new Map<String, Object>();

        Boolean isAnd = (logic == null || logic.toUpperCase() != 'OR');

        for (Object condObj : conditions) {
            Map<String, Object> cond = (Map<String, Object>) condObj;
            Boolean result = evaluateOne(cond, fieldValues, createdRecords);
            if (isAnd && !result) return false;
            if (!isAnd && result) return true;
        }

        return isAnd;
    }

    private static Boolean evaluateOne(
        Map<String, Object> cond,
        Map<String, Object> fieldValues,
        Map<String, Object> createdRecords
    ) {
        String source   = (String) cond.get('source');
        String operator = (String) cond.get('operator');
        Object rawValue = cond.get('value');
        String expected = rawValue == null ? '' : String.valueOf(rawValue);

        String actual = '';
        if (source == 'fieldValue') {
            String field = (String) cond.get('field');
            if (fieldValues.containsKey(field) && fieldValues.get(field) != null) {
                actual = String.valueOf(fieldValues.get(field));
            }
        } else if (source == 'createdRecord') {
            String stepName = (String) cond.get('stepName');
            String field    = (String) cond.get('field');
            if (createdRecords.containsKey(stepName)) {
                Map<String, Object> recFields = (Map<String, Object>) createdRecords.get(stepName);
                if (recFields.containsKey(field) && recFields.get(field) != null) {
                    actual = String.valueOf(recFields.get(field));
                }
            }
        } else {
            return true;
        }

        switch on operator {
            when 'equals'       { return actual.equalsIgnoreCase(expected); }
            when 'not_equals'   { return !actual.equalsIgnoreCase(expected); }
            when 'is_empty'     { return String.isBlank(actual); }
            when 'is_not_empty' { return String.isNotBlank(actual); }
            when else           { return true; }
        }
    }
}
