@IsTest
private class ConditionEvaluatorTest {

    private static String makeContext(Map<String,String> fieldValues, Map<String,Map<String,String>> createdRecords) {
        Map<String,Object> ctx = new Map<String,Object>{
            'fieldValues'    => fieldValues,
            'createdRecords' => createdRecords
        };
        return JSON.serialize(ctx);
    }

    @IsTest
    static void testEquals_match() {
        String conditionsJson = '[{"source":"fieldValue","field":"Priority","operator":"equals","value":"High"}]';
        String ctx = makeContext(new Map<String,String>{'Priority'=>'High'}, new Map<String,Map<String,String>>());
        System.assertEquals(true, ConditionEvaluator.evaluate(conditionsJson, 'AND', ctx));
    }

    @IsTest
    static void testEquals_noMatch() {
        String conditionsJson = '[{"source":"fieldValue","field":"Priority","operator":"equals","value":"High"}]';
        String ctx = makeContext(new Map<String,String>{'Priority'=>'Low'}, new Map<String,Map<String,String>>());
        System.assertEquals(false, ConditionEvaluator.evaluate(conditionsJson, 'AND', ctx));
    }

    @IsTest
    static void testNotEquals_match() {
        String conditionsJson = '[{"source":"fieldValue","field":"Status","operator":"not_equals","value":"Closed"}]';
        String ctx = makeContext(new Map<String,String>{'Status'=>'New'}, new Map<String,Map<String,String>>());
        System.assertEquals(true, ConditionEvaluator.evaluate(conditionsJson, 'AND', ctx));
    }

    @IsTest
    static void testIsEmpty_match() {
        String conditionsJson = '[{"source":"fieldValue","field":"Description","operator":"is_empty","value":""}]';
        String ctx = makeContext(new Map<String,String>{'Description'=>''}, new Map<String,Map<String,String>>());
        System.assertEquals(true, ConditionEvaluator.evaluate(conditionsJson, 'AND', ctx));
    }

    @IsTest
    static void testIsNotEmpty_match() {
        String conditionsJson = '[{"source":"fieldValue","field":"Subject","operator":"is_not_empty","value":""}]';
        String ctx = makeContext(new Map<String,String>{'Subject'=>'Test'}, new Map<String,Map<String,String>>());
        System.assertEquals(true, ConditionEvaluator.evaluate(conditionsJson, 'AND', ctx));
    }

    @IsTest
    static void testAND_allMatch() {
        String conditionsJson = '[{"source":"fieldValue","field":"Priority","operator":"equals","value":"High"},{"source":"fieldValue","field":"Status","operator":"equals","value":"New"}]';
        String ctx = makeContext(new Map<String,String>{'Priority'=>'High','Status'=>'New'}, new Map<String,Map<String,String>>());
        System.assertEquals(true, ConditionEvaluator.evaluate(conditionsJson, 'AND', ctx));
    }

    @IsTest
    static void testAND_oneNoMatch() {
        String conditionsJson = '[{"source":"fieldValue","field":"Priority","operator":"equals","value":"High"},{"source":"fieldValue","field":"Status","operator":"equals","value":"New"}]';
        String ctx = makeContext(new Map<String,String>{'Priority'=>'High','Status'=>'Closed'}, new Map<String,Map<String,String>>());
        System.assertEquals(false, ConditionEvaluator.evaluate(conditionsJson, 'AND', ctx));
    }

    @IsTest
    static void testOR_oneMatch() {
        String conditionsJson = '[{"source":"fieldValue","field":"Priority","operator":"equals","value":"High"},{"source":"fieldValue","field":"Status","operator":"equals","value":"New"}]';
        String ctx = makeContext(new Map<String,String>{'Priority'=>'Low','Status'=>'New'}, new Map<String,Map<String,String>>());
        System.assertEquals(true, ConditionEvaluator.evaluate(conditionsJson, 'OR', ctx));
    }

    @IsTest
    static void testOR_noneMatch() {
        String conditionsJson = '[{"source":"fieldValue","field":"Priority","operator":"equals","value":"High"},{"source":"fieldValue","field":"Status","operator":"equals","value":"New"}]';
        String ctx = makeContext(new Map<String,String>{'Priority'=>'Low','Status'=>'Closed'}, new Map<String,Map<String,String>>());
        System.assertEquals(false, ConditionEvaluator.evaluate(conditionsJson, 'OR', ctx));
    }

    @IsTest
    static void testEmptyConditions_alwaysTrue() {
        System.assertEquals(true, ConditionEvaluator.evaluate('[]', 'AND', '{}'));
        System.assertEquals(true, ConditionEvaluator.evaluate(null, 'AND', '{}'));
    }

    @IsTest
    static void testMalformedJson_returnsTrue() {
        // Malformed JSON should not block execution
        Boolean result = ConditionEvaluator.evaluate('not-valid-json', 'AND', '{}');
        System.assertEquals(true, result, 'Malformed JSON should return true (allow execution)');
    }

    @IsTest
    static void testUnknownSource_returnsTrue() {
        String conditionsJson = '[{"source":"unknownSource","field":"X","operator":"equals","value":"Y"}]';
        String ctx = makeContext(new Map<String,String>{'X'=>'Y'}, new Map<String,Map<String,String>>());
        System.assertEquals(true, ConditionEvaluator.evaluate(conditionsJson, 'AND', ctx));
    }

    @IsTest
    static void testUnknownOperator_returnsTrue() {
        String conditionsJson = '[{"source":"fieldValue","field":"X","operator":"contains","value":"Y"}]';
        String ctx = makeContext(new Map<String,String>{'X'=>'Y'}, new Map<String,Map<String,String>>());
        System.assertEquals(true, ConditionEvaluator.evaluate(conditionsJson, 'AND', ctx));
    }

    @IsTest
    static void testNullValue_handledGracefully() {
        String conditionsJson = '[{"source":"fieldValue","field":"Missing","operator":"is_empty","value":""}]';
        String ctx = makeContext(new Map<String,String>(), new Map<String,Map<String,String>>());
        System.assertEquals(true, ConditionEvaluator.evaluate(conditionsJson, 'AND', ctx));
    }

    @IsTest
    static void testBlankExecutionData_usesEmptyMaps() {
        // executionDataJson is blank — exercises the isBlank branch (line 16)
        String conditionsJson = '[{"source":"fieldValue","field":"X","operator":"is_empty","value":""}]';
        System.assertEquals(true, ConditionEvaluator.evaluate(conditionsJson, 'AND', ''));
    }

    @IsTest
    static void testMissingFieldValuesKey_usesEmptyMap() {
        // executionDataJson has no "fieldValues" key — exercises line 21 fallback
        String conditionsJson = '[{"source":"fieldValue","field":"X","operator":"is_empty","value":""}]';
        String ctx = '{"createdRecords":{}}';
        System.assertEquals(true, ConditionEvaluator.evaluate(conditionsJson, 'AND', ctx));
    }

    @IsTest
    static void testMissingCreatedRecordsKey_usesEmptyMap() {
        // executionDataJson has no "createdRecords" key — exercises line 25 fallback
        String conditionsJson = '[{"source":"createdRecord","stepName":"Step1","field":"X","operator":"is_empty","value":""}]';
        String ctx = '{"fieldValues":{}}';
        System.assertEquals(true, ConditionEvaluator.evaluate(conditionsJson, 'AND', ctx));
    }

    @IsTest
    static void testCreatedRecord_equals() {
        Map<String,Map<String,String>> cr = new Map<String,Map<String,String>>{
            'Criar Case' => new Map<String,String>{'Status'=>'New'}
        };
        String conditionsJson = '[{"source":"createdRecord","stepName":"Criar Case","field":"Status","operator":"equals","value":"New"}]';
        String ctx = makeContext(new Map<String,String>(), cr);
        System.assertEquals(true, ConditionEvaluator.evaluate(conditionsJson, 'AND', ctx));
    }
}
