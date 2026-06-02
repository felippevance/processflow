@IsTest
global class HttpCalloutMock implements HttpCalloutMock {
    private Integer statusCode;
    private String body;

    global HttpCalloutMock(Integer statusCode, String body) {
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