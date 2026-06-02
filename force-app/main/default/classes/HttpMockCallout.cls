@IsTest
global class HttpMockCallout implements System.HttpCalloutMock {
    private Integer statusCode;
    private String body;

    global HttpMockCallout(Integer statusCode, String body) {
        this.statusCode = statusCode;
        this.body = body;
    }

    global HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setBody(body);
        res.setHeader('Content-Type', 'application/json');
        return res;
    }
}
