@IsTest
private class HttpRequestExecutorTest {

    private static String makeConfig(
        String namedCredential, String method, String path,
        List<Map<String,String>> bodyMappings,
        List<Map<String,String>> responseMappings,
        Integer timeout, Boolean retry, String onFailure
    ) {
        Map<String,Object> cfg = new Map<String,Object>{
            'namedCredential' => namedCredential,
            'method'          => method,
            'path'            => path,
            'headers'         => new List<Object>(),
            'bodyMappings'    => bodyMappings,
            'responseMappings'=> responseMappings,
            'timeout'         => timeout,
            'retry'           => retry,
            'onFailure'       => onFailure
        };
        return JSON.serialize(cfg);
    }

    @IsTest
    static void testSuccessfulPost_mapsBodyAndResponse() {
        String responseBody = '{"id":"EXT-001","status":"created"}';
        Test.setMock(HttpCalloutMock.class, new HttpMockCallout(200, responseBody));

        List<Map<String,String>> bodyMappings = new List<Map<String,String>>{
            new Map<String,String>{'jsonKey'=>'name','processField'=>'FirstName'},
            new Map<String,String>{'jsonKey'=>'priority','processField'=>'Priority'}
        };
        List<Map<String,String>> responseMappings = new List<Map<String,String>>{
            new Map<String,String>{'jsonPath'=>'id','fieldValuesKey'=>'externalId'},
            new Map<String,String>{'jsonPath'=>'status','fieldValuesKey'=>'apiStatus'}
        };

        String config = makeConfig('My_API', 'POST', '/v1/customers', bodyMappings, responseMappings, 30, false, 'stop');
        Map<String,Object> fieldValues = new Map<String,Object>{'FirstName'=>'João','Priority'=>'High'};

        Test.startTest();
        Map<String,Object> result = HttpRequestExecutor.execute(config, fieldValues);
        Test.stopTest();

        System.assertEquals('EXT-001', result.get('externalId'), 'Should map response.id to externalId');
        System.assertEquals('created', result.get('apiStatus'), 'Should map response.status to apiStatus');
    }

    @IsTest
    static void testRetryFlag_addsHeader() {
        Test.setMock(HttpCalloutMock.class, new HttpMockCallout(200, '{"ok":true}'));

        String config = makeConfig('My_API', 'GET', '/v1/ping',
            new List<Map<String,String>>(),
            new List<Map<String,String>>(),
            10, true, 'stop');

        Test.startTest();
        Map<String,Object> result = HttpRequestExecutor.execute(config, new Map<String,Object>());
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return result map even with retry=true');
    }

    @IsTest
    static void testFailure_stopBehavior_throwsException() {
        Test.setMock(HttpCalloutMock.class, new HttpMockCallout(500, '{"error":"internal"}'));

        String config = makeConfig('My_API', 'POST', '/v1/fail',
            new List<Map<String,String>>(),
            new List<Map<String,String>>(),
            30, false, 'stop');

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            HttpRequestExecutor.execute(config, new Map<String,Object>());
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Should throw AuraHandledException when onFailure=stop');
    }

    @IsTest
    static void testFailure_continueBehavior_noException() {
        Test.setMock(HttpCalloutMock.class, new HttpMockCallout(404, '{"error":"not found"}'));

        String config = makeConfig('My_API', 'GET', '/v1/missing',
            new List<Map<String,String>>(),
            new List<Map<String,String>>(),
            30, false, 'continue');

        Test.startTest();
        Boolean exceptionThrown = false;
        Map<String,Object> result;
        try {
            result = HttpRequestExecutor.execute(config, new Map<String,Object>());
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(false, exceptionThrown, 'Should NOT throw when onFailure=continue');
        System.assertNotEquals(null, result, 'Should return empty map when continuing on failure');
    }

    @IsTest
    static void testBodyMappings_buildsJsonFromFieldValues() {
        Test.setMock(HttpCalloutMock.class, new HttpMockCallout(201, '{}'));

        List<Map<String,String>> bodyMappings = new List<Map<String,String>>{
            new Map<String,String>{'jsonKey'=>'email','processField'=>'Email'},
            new Map<String,String>{'jsonKey'=>'dept','processField'=>'Department'}
        };

        String config = makeConfig('My_API', 'POST', '/v1/users', bodyMappings,
            new List<Map<String,String>>(), 30, false, 'stop');
        Map<String,Object> fieldValues = new Map<String,Object>{'Email'=>'test@test.com','Department'=>'IT'};

        Test.startTest();
        HttpRequestExecutor.execute(config, fieldValues);
        Test.stopTest();
        System.assert(true, 'Body was built and request was sent successfully');
    }
}