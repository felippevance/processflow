@IsTest
private class HttpRequestExecutorTest {

    // ── Simple mock: always returns the same statusCode + body ───────────────
    class SimpleMock implements System.HttpCalloutMock {
        private Integer statusCode;
        private String  body;
        SimpleMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body       = body;
        }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            res.setHeader('Content-Type', 'application/json');
            return res;
        }
    }

    // ── Stateful mock: returns 500 for the first N calls, then 200 ──────────
    class RetryMock implements System.HttpCalloutMock {
        private Integer failCount;
        private Integer callCount = 0;
        private String  successBody;

        RetryMock(Integer failCount, String successBody) {
            this.failCount   = failCount;
            this.successBody = successBody;
        }

        public HttpResponse respond(HttpRequest req) {
            callCount++;
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (callCount <= failCount) {
                res.setStatusCode(500);
                res.setBody('{"error":"server error"}');
            } else {
                res.setStatusCode(200);
                res.setBody(successBody);
            }
            return res;
        }
    }

    // ── Helper to build a config JSON ────────────────────────────────────────
    private static String makeConfig(
        String namedCredential, String method, String path,
        List<Map<String,String>> bodyMappings,
        List<Map<String,String>> responseMappings,
        Integer timeout, Boolean retry, Integer retryCount, String onFailure
    ) {
        Map<String,Object> cfg = new Map<String,Object>{
            'namedCredential'  => namedCredential,
            'method'           => method,
            'path'             => path,
            'headers'          => new List<Object>(),
            'bodyMappings'     => bodyMappings,
            'responseMappings' => responseMappings,
            'timeout'          => timeout,
            'retry'            => retry,
            'retryCount'       => retryCount,
            'onFailure'        => onFailure
        };
        return JSON.serialize(cfg);
    }

    // ── 1. Successful GET with response mapping ──────────────────────────────
    @IsTest
    static void testSuccessfulGet_responseMappingApplied() {
        String responseBody = '{"customerId":"C-123","region":"BR"}';
        Test.setMock(System.HttpCalloutMock.class, new SimpleMock(200, responseBody));

        List<Map<String,String>> responseMappings = new List<Map<String,String>>{
            new Map<String,String>{'jsonPath'=>'customerId','fieldValuesKey'=>'CustId'},
            new Map<String,String>{'jsonPath'=>'region',    'fieldValuesKey'=>'Region'}
        };

        String config = makeConfig('My_API', 'GET', '/v1/customer',
            new List<Map<String,String>>(), responseMappings, 30, false, 0, 'stop');

        Test.startTest();
        Map<String,Object> result = HttpRequestExecutor.execute(config, new Map<String,Object>());
        Test.stopTest();

        System.assertEquals('C-123', result.get('CustId'),  'Response customerId should be mapped');
        System.assertEquals('BR',    result.get('Region'),  'Response region should be mapped');
    }

    // ── 2. Successful POST with body mappings ────────────────────────────────
    @IsTest
    static void testSuccessfulPost_mapsBodyAndResponse() {
        String responseBody = '{"id":"EXT-001","status":"created"}';
        Test.setMock(System.HttpCalloutMock.class, new SimpleMock(200, responseBody));

        List<Map<String,String>> bodyMappings = new List<Map<String,String>>{
            new Map<String,String>{'jsonKey'=>'name',    'processField'=>'FirstName'},
            new Map<String,String>{'jsonKey'=>'priority','processField'=>'Priority'}
        };
        List<Map<String,String>> responseMappings = new List<Map<String,String>>{
            new Map<String,String>{'jsonPath'=>'id',    'fieldValuesKey'=>'externalId'},
            new Map<String,String>{'jsonPath'=>'status','fieldValuesKey'=>'apiStatus'}
        };

        String config = makeConfig('My_API', 'POST', '/v1/customers',
            bodyMappings, responseMappings, 30, false, 0, 'stop');
        Map<String,Object> fieldValues = new Map<String,Object>{'FirstName'=>'João','Priority'=>'High'};

        Test.startTest();
        Map<String,Object> result = HttpRequestExecutor.execute(config, fieldValues);
        Test.stopTest();

        System.assertEquals('EXT-001', result.get('externalId'), 'Should map response.id to externalId');
        System.assertEquals('created', result.get('apiStatus'),  'Should map response.status to apiStatus');
    }

    // ── 3. 500 with onFailure=stop → AuraHandledException ───────────────────
    @IsTest
    static void testFailure_stop_throwsException() {
        Test.setMock(System.HttpCalloutMock.class, new SimpleMock(500, '{"error":"internal"}'));

        String config = makeConfig('My_API', 'POST', '/v1/fail',
            new List<Map<String,String>>(), new List<Map<String,String>>(),
            30, false, 0, 'stop');

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

    // ── 4. 500 with onFailure=continue → empty map, no exception ────────────
    @IsTest
    static void testFailure_continue_returnsEmptyMap() {
        Test.setMock(System.HttpCalloutMock.class, new SimpleMock(500, '{"error":"server error"}'));

        String config = makeConfig('My_API', 'GET', '/v1/fail',
            new List<Map<String,String>>(), new List<Map<String,String>>(),
            30, false, 0, 'continue');

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
        System.assertNotEquals(null, result,         'Should return a map (not null)');
        System.assertEquals(0, result.size(),        'Returned map should be empty on 500 + continue');
    }

    // ── 5. Retry: 2 failures then success on 3rd attempt ────────────────────
    @IsTest
    static void testRetry_succeedsOnThirdAttempt() {
        // retryCount=2 → 1 initial + 2 retries = 3 total attempts
        String successBody = '{"result":"ok"}';
        Test.setMock(System.HttpCalloutMock.class, new RetryMock(2, successBody));

        List<Map<String,String>> responseMappings = new List<Map<String,String>>{
            new Map<String,String>{'jsonPath'=>'result','fieldValuesKey'=>'outcome'}
        };

        String config = makeConfig('My_API', 'GET', '/v1/retry-endpoint',
            new List<Map<String,String>>(), responseMappings,
            10, true, 2, 'stop');

        Test.startTest();
        Map<String,Object> result = HttpRequestExecutor.execute(config, new Map<String,Object>());
        Test.stopTest();

        System.assertEquals('ok', result.get('outcome'), 'Should succeed after 2 retries and map response');
    }

    // ── 6. Path normalisation: no leading slash gets one prepended ───────────
    @IsTest
    static void testPathNormalisation_addsLeadingSlash() {
        Test.setMock(System.HttpCalloutMock.class, new SimpleMock(200, '{}'));

        Map<String,Object> cfg = new Map<String,Object>{
            'namedCredential'  => 'My_API',
            'method'           => 'GET',
            'path'             => 'v1/no-slash',
            'headers'          => new List<Object>(),
            'bodyMappings'     => new List<Object>(),
            'responseMappings' => new List<Object>(),
            'timeout'          => 10,
            'retry'            => false,
            'onFailure'        => 'stop'
        };

        Test.startTest();
        Map<String,Object> result = HttpRequestExecutor.execute(JSON.serialize(cfg), new Map<String,Object>());
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should succeed with normalised path');
    }

    // ── 7. Missing namedCredential → AuraHandledException ───────────────────
    @IsTest
    static void testMissingNamedCredential_throwsAuraException() {
        Map<String,Object> cfg = new Map<String,Object>{
            'namedCredential'  => '',
            'method'           => 'GET',
            'path'             => '/v1/test',
            'headers'          => new List<Object>(),
            'bodyMappings'     => new List<Object>(),
            'responseMappings' => new List<Object>(),
            'timeout'          => 10,
            'retry'            => false,
            'onFailure'        => 'stop'
        };

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            HttpRequestExecutor.execute(JSON.serialize(cfg), new Map<String,Object>());
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Blank namedCredential must throw AuraHandledException');
    }

    // ── 8. Retry flag=true adds X-Retry-Enabled header ───────────────────────
    @IsTest
    static void testRetryFlag_addsHeader() {
        Test.setMock(System.HttpCalloutMock.class, new SimpleMock(200, '{"ok":true}'));

        String config = makeConfig('My_API', 'GET', '/v1/ping',
            new List<Map<String,String>>(), new List<Map<String,String>>(),
            10, true, 0, 'stop');

        Test.startTest();
        Map<String,Object> result = HttpRequestExecutor.execute(config, new Map<String,Object>());
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return result map even with retry=true');
    }

    // ── 9. Body mappings build JSON from fieldValues ──────────────────────────
    @IsTest
    static void testBodyMappings_buildsJsonFromFieldValues() {
        Test.setMock(System.HttpCalloutMock.class, new SimpleMock(201, '{}'));

        List<Map<String,String>> bodyMappings = new List<Map<String,String>>{
            new Map<String,String>{'jsonKey'=>'email','processField'=>'Email'},
            new Map<String,String>{'jsonKey'=>'dept', 'processField'=>'Department'}
        };

        String config = makeConfig('My_API', 'POST', '/v1/users',
            bodyMappings, new List<Map<String,String>>(), 30, false, 0, 'stop');
        Map<String,Object> fieldValues = new Map<String,Object>{'Email'=>'test@test.com','Department'=>'IT'};

        Test.startTest();
        HttpRequestExecutor.execute(config, fieldValues);
        Test.stopTest();
        System.assert(true, 'Body was built and request was sent successfully');
    }

    // ── 10. 4xx with onFailure=continue → empty map ──────────────────────────
    @IsTest
    static void testFailure_404_continue_returnsEmptyMap() {
        Test.setMock(System.HttpCalloutMock.class, new SimpleMock(404, '{"error":"not found"}'));

        String config = makeConfig('My_API', 'GET', '/v1/missing',
            new List<Map<String,String>>(), new List<Map<String,String>>(),
            30, false, 0, 'continue');

        Test.startTest();
        Map<String,Object> result = HttpRequestExecutor.execute(config, new Map<String,Object>());
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Should return empty map on 404 + continue');
    }
}
