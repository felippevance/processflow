@IsTest
private class ProcessFlowJsonUtilTest {

    // ══════════════════════════════════════════════════════════════
    // toMap()
    // ══════════════════════════════════════════════════════════════

    @IsTest
    static void testToMap_validJson_returnsMap() {
        String json = '{"key1":"value1","key2":42}';
        Test.startTest();
        Map<String,Object> result = ProcessFlowJsonUtil.toMap(json);
        Test.stopTest();

        System.assertEquals('value1', result.get('key1'), 'key1 should be value1');
        System.assertEquals(42,       result.get('key2'), 'key2 should be 42');
    }

    @IsTest
    static void testToMap_emptyString_returnsEmptyMap() {
        Test.startTest();
        Map<String,Object> result = ProcessFlowJsonUtil.toMap('');
        Test.stopTest();

        System.assertNotEquals(null, result,       'Should return non-null map');
        System.assertEquals(0,       result.size(), 'Empty string should yield empty map');
    }

    @IsTest
    static void testToMap_blankString_returnsEmptyMap() {
        Test.startTest();
        Map<String,Object> result = ProcessFlowJsonUtil.toMap('   ');
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Blank string should yield empty map');
    }

    @IsTest
    static void testToMap_malformedJson_returnsEmptyMap() {
        Test.startTest();
        Map<String,Object> result = ProcessFlowJsonUtil.toMap('{bad json!!}');
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Malformed JSON should yield empty map (no exception)');
    }

    @IsTest
    static void testToMap_jsonArray_returnsEmptyMap() {
        // When JSON root is an array, toMap should return empty (not a map)
        Test.startTest();
        Map<String,Object> result = ProcessFlowJsonUtil.toMap('[1,2,3]');
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Array JSON should yield empty map');
    }

    // ══════════════════════════════════════════════════════════════
    // toList()
    // ══════════════════════════════════════════════════════════════

    @IsTest
    static void testToList_validArray_returnsList() {
        String json = '[{"a":1},{"b":2}]';
        Test.startTest();
        List<Object> result = ProcessFlowJsonUtil.toList(json);
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Should return list with 2 elements');
    }

    @IsTest
    static void testToList_emptyString_returnsEmptyList() {
        Test.startTest();
        List<Object> result = ProcessFlowJsonUtil.toList('');
        Test.stopTest();

        System.assertNotEquals(null, result,       'Should return non-null list');
        System.assertEquals(0,       result.size(), 'Empty string should yield empty list');
    }

    @IsTest
    static void testToList_malformedJson_returnsEmptyList() {
        Test.startTest();
        List<Object> result = ProcessFlowJsonUtil.toList('[bad!]');
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Malformed JSON should yield empty list (no exception)');
    }

    @IsTest
    static void testToList_jsonObject_returnsEmptyList() {
        // Root is a map, not a list → should return empty list
        Test.startTest();
        List<Object> result = ProcessFlowJsonUtil.toList('{"key":"val"}');
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Object JSON should yield empty list');
    }

    // ══════════════════════════════════════════════════════════════
    // getFieldDefs()
    // ══════════════════════════════════════════════════════════════

    @IsTest
    static void testGetFieldDefs_oldArrayFormat_returnsList() {
        // Old format: root is a JSON array
        String json = '[{"apiName":"Name","type":"STRING"},{"apiName":"Status","type":"PICKLIST"}]';
        Test.startTest();
        List<Object> result = ProcessFlowJsonUtil.getFieldDefs(json);
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Old array format should return 2 field defs');
    }

    @IsTest
    static void testGetFieldDefs_newObjectFormat_returnsFieldsArray() {
        // New format: root is { "_v":1, "fields": [...] }
        String json = '{"_v":1,"recordTypeId":null,"fields":[{"apiName":"Subject","type":"STRING"},{"apiName":"Priority","type":"PICKLIST"}]}';
        Test.startTest();
        List<Object> result = ProcessFlowJsonUtil.getFieldDefs(json);
        Test.stopTest();

        System.assertEquals(2, result.size(), 'New object format should return fields array with 2 items');
    }

    @IsTest
    static void testGetFieldDefs_objectWithoutFields_returnsEmptyList() {
        // Object format without a 'fields' key
        String json = '{"_v":1,"namedCredential":"My_API"}';
        Test.startTest();
        List<Object> result = ProcessFlowJsonUtil.getFieldDefs(json);
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Object without fields key should return empty list');
    }

    @IsTest
    static void testGetFieldDefs_emptyString_returnsEmptyList() {
        Test.startTest();
        List<Object> result = ProcessFlowJsonUtil.getFieldDefs('');
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Empty string should yield empty list');
    }

    @IsTest
    static void testGetFieldDefs_malformedJson_returnsEmptyList() {
        Test.startTest();
        List<Object> result = ProcessFlowJsonUtil.getFieldDefs('{bad!}');
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Malformed JSON should yield empty list');
    }

    // ══════════════════════════════════════════════════════════════
    // getFieldsConfigMap()
    // ══════════════════════════════════════════════════════════════

    @IsTest
    static void testGetFieldsConfigMap_validMap_returnsMap() {
        String json = '{"_v":1,"namedCredential":"My_API","method":"POST"}';
        Test.startTest();
        Map<String,Object> result = ProcessFlowJsonUtil.getFieldsConfigMap(json);
        Test.stopTest();

        System.assertEquals('My_API', result.get('namedCredential'), 'Should return map with namedCredential');
        System.assertEquals('POST',   result.get('method'),          'Should return map with method');
    }

    @IsTest
    static void testGetFieldsConfigMap_arrayJson_returnsEmptyMap() {
        // Root is array → method must return empty map (not crash)
        String json = '[{"apiName":"Name"}]';
        Test.startTest();
        Map<String,Object> result = ProcessFlowJsonUtil.getFieldsConfigMap(json);
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Array JSON should yield empty map');
    }

    @IsTest
    static void testGetFieldsConfigMap_blank_returnsEmptyMap() {
        Test.startTest();
        Map<String,Object> result = ProcessFlowJsonUtil.getFieldsConfigMap('  ');
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Blank input should yield empty map');
    }

    // ══════════════════════════════════════════════════════════════
    // getSchemaVersion()
    // ══════════════════════════════════════════════════════════════

    @IsTest
    static void testGetSchemaVersion_present_returnsVersion() {
        Map<String,Object> data = new Map<String,Object>{'_v' => 1};
        Test.startTest();
        Integer v = ProcessFlowJsonUtil.getSchemaVersion(data);
        Test.stopTest();

        System.assertEquals(1, v, 'Should return version 1');
    }

    @IsTest
    static void testGetSchemaVersion_absent_returnsZero() {
        Map<String,Object> data = new Map<String,Object>{'someKey' => 'value'};
        Test.startTest();
        Integer v = ProcessFlowJsonUtil.getSchemaVersion(data);
        Test.stopTest();

        System.assertEquals(0, v, 'Missing _v key should return 0');
    }

    @IsTest
    static void testGetSchemaVersion_nullMap_returnsZero() {
        Test.startTest();
        Integer v = ProcessFlowJsonUtil.getSchemaVersion(null);
        Test.stopTest();

        System.assertEquals(0, v, 'Null map should return 0');
    }

    @IsTest
    static void testGetSchemaVersion_invalidType_returnsZero() {
        // _v is a non-numeric string → Integer.valueOf will throw → should return 0
        Map<String,Object> data = new Map<String,Object>{'_v' => 'not-a-number'};
        Test.startTest();
        Integer v = ProcessFlowJsonUtil.getSchemaVersion(data);
        Test.stopTest();

        System.assertEquals(0, v, 'Non-numeric _v should return 0');
    }

    // ══════════════════════════════════════════════════════════════
    // isSchemaVersionValid()
    // ══════════════════════════════════════════════════════════════

    @IsTest
    static void testIsSchemaVersionValid_version1_min1_returnsTrue() {
        Map<String,Object> data = new Map<String,Object>{'_v' => 1};
        Test.startTest();
        Boolean valid = ProcessFlowJsonUtil.isSchemaVersionValid(data, 1);
        Test.stopTest();

        System.assertEquals(true, valid, 'Version 1 with min 1 should be valid');
    }

    @IsTest
    static void testIsSchemaVersionValid_version0_min1_returnsFalse() {
        Map<String,Object> data = new Map<String,Object>{'someKey' => 'val'}; // _v absent → 0
        Test.startTest();
        Boolean valid = ProcessFlowJsonUtil.isSchemaVersionValid(data, 1);
        Test.stopTest();

        System.assertEquals(false, valid, 'Version 0 (absent) with min 1 should be invalid');
    }

    @IsTest
    static void testIsSchemaVersionValid_higherVersion_returnsTrue() {
        Map<String,Object> data = new Map<String,Object>{'_v' => 5};
        Test.startTest();
        Boolean valid = ProcessFlowJsonUtil.isSchemaVersionValid(data, 2);
        Test.stopTest();

        System.assertEquals(true, valid, 'Version 5 with min 2 should be valid');
    }
}
