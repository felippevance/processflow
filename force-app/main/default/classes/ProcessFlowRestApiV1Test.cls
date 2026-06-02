@IsTest
private class ProcessFlowRestApiV1Test {

    @TestSetup
    static void setup() {
        Process__c proc = new Process__c(
            Name='API Test Process', IsActive__c=true,
            Version__c=1, IsCurrentVersion__c=true,
            Description__c='Test via API'
        );
        insert proc;
        Stage__c stage = new Stage__c(Name='Stage 1', Sequence__c=1, Process__c=proc.Id);
        insert stage;
        Step__c step = new Step__c(
            Name='Notify', Sequence__c=1, Stage__c=stage.Id,
            Type__c='Notification',
            FieldsConfig__c='{"messageTemplate":"API Test Notification","channel":"chatter"}'
        );
        insert step;
    }

    private static RestRequest makeRequest(String method, String uri, String body) {
        RestRequest req = new RestRequest();
        req.httpMethod = method;
        req.requestURI = '/services/apexrest/processflow/v1' + uri;
        if (body != null) req.requestBody = Blob.valueOf(body);
        return req;
    }

    private static Map<String,Object> parseResponse() {
        return (Map<String,Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
    }

    @IsTest
    static void testGetProcesses_returnsActiveList() {
        RestContext.request  = makeRequest('GET', '/processes', null);
        RestContext.response = new RestResponse();

        Test.startTest();
        ProcessFlowRestApiV1.doGet();
        Test.stopTest();

        Map<String,Object> resp = parseResponse();
        System.assertEquals('success', resp.get('status'));
        List<Object> data = (List<Object>) resp.get('data');
        System.assertEquals(1, data.size());
    }

    @IsTest
    static void testGetStatus_unknownId_returnsFailed() {
        RestContext.request  = makeRequest('GET', '/executions/000000000000000AAA/status', null);
        RestContext.response = new RestResponse();

        Test.startTest();
        ProcessFlowRestApiV1.doGet();
        Test.stopTest();

        Map<String,Object> resp = parseResponse();
        System.assertEquals('failed', resp.get('status'));
    }

    @IsTest
    static void testExecute_validExternalId_createsExecution() {
        Process__c proc = [SELECT ExternalId__c FROM Process__c LIMIT 1];
        RestContext.request  = makeRequest('POST', '/processes/' + proc.ExternalId__c + '/execute', '{}');
        RestContext.response = new RestResponse();

        Test.startTest();
        ProcessFlowRestApiV1.doPost();
        Test.stopTest();

        Map<String,Object> resp = parseResponse();
        System.assertEquals('success', resp.get('status'));
        Map<String,Object> data = (Map<String,Object>) resp.get('data');
        System.assertNotEquals(null, data.get('executionId'));

        // Cleanup
        delete [SELECT Id FROM Execution__c WHERE Process__c = :proc.Id];
    }

    @IsTest
    static void testExecute_invalidExternalId_returnsFailed() {
        RestContext.request  = makeRequest('POST', '/processes/NONEXISTENT-123/execute', '{}');
        RestContext.response = new RestResponse();

        Test.startTest();
        ProcessFlowRestApiV1.doPost();
        Test.stopTest();

        Map<String,Object> resp = parseResponse();
        System.assertEquals('failed', resp.get('status'));
    }

    @IsTest
    static void testDelete_cancelsExecution() {
        Process__c proc = [SELECT Id FROM Process__c LIMIT 1];
        Stage__c stage  = [SELECT Id FROM Stage__c LIMIT 1];
        Step__c step    = [SELECT Id FROM Step__c LIMIT 1];

        Execution__c exec = new Execution__c(
            Process__c=proc.Id, User__c=UserInfo.getUserId(),
            StartedAt__c=System.now(), Status__c='In Progress',
            CurrentStage__c=stage.Id, CurrentStep__c=step.Id,
            ExecutionData__c='{}'
        );
        insert exec;

        RestContext.request  = makeRequest('DELETE', '/executions/' + exec.Id, null);
        RestContext.response = new RestResponse();

        Test.startTest();
        ProcessFlowRestApiV1.doDelete();
        Test.stopTest();

        Map<String,Object> resp = parseResponse();
        System.assertEquals('success', resp.get('status'));

        Execution__c updated = [SELECT FinalStatus__c FROM Execution__c WHERE Id = :exec.Id];
        System.assertEquals('Cancelled', updated.FinalStatus__c);
    }

    @IsTest
    static void testDelete_unknownId_returnsFailed() {
        RestContext.request  = makeRequest('DELETE', '/executions/000000000000000AAA', null);
        RestContext.response = new RestResponse();

        Test.startTest();
        ProcessFlowRestApiV1.doDelete();
        Test.stopTest();

        Map<String,Object> resp = parseResponse();
        System.assertEquals('failed', resp.get('status'));
    }

    @IsTest
    static void testUnknownEndpoint_returnsFailed() {
        RestContext.request  = makeRequest('GET', '/unknown/path', null);
        RestContext.response = new RestResponse();

        Test.startTest();
        ProcessFlowRestApiV1.doGet();
        Test.stopTest();

        Map<String,Object> resp = parseResponse();
        System.assertEquals('failed', resp.get('status'));
    }

    @IsTest
    static void testStep_completedExecution_returnsFailed() {
        Process__c proc = [SELECT Id FROM Process__c LIMIT 1];
        Stage__c stage  = [SELECT Id FROM Stage__c LIMIT 1];
        Step__c step    = [SELECT Id FROM Step__c LIMIT 1];

        Execution__c exec = new Execution__c(
            Process__c=proc.Id, User__c=UserInfo.getUserId(),
            StartedAt__c=System.now(), Status__c='In Progress',
            FinalStatus__c='Completed', CompletedAt__c=System.now(),
            CurrentStage__c=stage.Id, CurrentStep__c=step.Id,
            ExecutionData__c='{}'
        );
        insert exec;

        RestContext.request  = makeRequest('POST', '/executions/' + exec.Id + '/step', '{}');
        RestContext.response = new RestResponse();

        Test.startTest();
        ProcessFlowRestApiV1.doPost();
        Test.stopTest();

        Map<String,Object> resp = parseResponse();
        System.assertEquals('failed', resp.get('status'));
    }
}
