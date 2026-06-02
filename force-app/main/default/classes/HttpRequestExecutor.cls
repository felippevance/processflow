public with sharing class HttpRequestExecutor {

    /**
     * Executes an HTTP callout based on the step's FieldsConfig__c JSON.
     *
     * Config format:
     * {
     *   "namedCredential": "My_API",
     *   "method": "POST",
     *   "path": "/v1/customers",
     *   "headers": [{"key": "X-Custom", "value": "foo"}],
     *   "bodyMappings": [{"jsonKey": "name", "processField": "FirstName"}],
     *   "responseMappings": [{"jsonPath": "id", "fieldValuesKey": "externalId"}],
     *   "timeout": 30,
     *   "retry": true,
     *   "onFailure": "stop"
     * }
     */
    public static Map<String, Object> execute(String configJson, Map<String, Object> fieldValues) {
        Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(configJson);

        String namedCredential = (String) config.get('namedCredential');
        String method          = ((String) config.get('method')).toUpperCase();
        String path            = (String) config.get('path');
        Integer timeoutMs      = config.containsKey('timeout')
            ? Integer.valueOf(config.get('timeout')) * 1000
            : 30000;
        Boolean retry          = config.containsKey('retry') && (Boolean) config.get('retry');
        String onFailure       = config.containsKey('onFailure') ? (String) config.get('onFailure') : 'stop';

        // Validate namedCredential is not blank and path starts with /
        if (String.isBlank(namedCredential)) {
            throw new AuraHandledException('HTTP Request step: Named Credential is required.');
        }
        if (String.isBlank(path)) path = '/';
        if (!path.startsWith('/')) path = '/' + path;
        // Remove any double slashes to prevent path traversal
        path = path.replaceAll('/+', '/');

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:' + namedCredential + path);
        req.setMethod(method);
        req.setTimeout(timeoutMs);

        List<Object> headers = config.containsKey('headers')
            ? (List<Object>) config.get('headers')
            : new List<Object>();
        for (Object h : headers) {
            Map<String, Object> header = (Map<String, Object>) h;
            req.setHeader((String) header.get('key'), (String) header.get('value'));
        }

        if (retry) {
            req.setHeader('X-Retry-Enabled', 'true');
        }

        List<Object> bodyMappings = config.containsKey('bodyMappings')
            ? (List<Object>) config.get('bodyMappings')
            : new List<Object>();
        if (!bodyMappings.isEmpty()) {
            Map<String, Object> bodyMap = new Map<String, Object>();
            for (Object bm : bodyMappings) {
                Map<String, Object> mapping = (Map<String, Object>) bm;
                String jsonKey      = (String) mapping.get('jsonKey');
                String processField = (String) mapping.get('processField');
                bodyMap.put(jsonKey, fieldValues.containsKey(processField) ? fieldValues.get(processField) : null);
            }
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(bodyMap));
        }

        Http http = new Http();
        Integer retryCount = (retry && config.containsKey('retryCount'))
            ? Integer.valueOf(config.get('retryCount'))
            : 0;
        Integer maxAttempts = 1 + retryCount; // 1 initial + N retries

        HttpResponse res = null;
        String lastError = null;

        for (Integer attempt = 1; attempt <= maxAttempts; attempt++) {
            try {
                res = http.send(req);
                Integer sc = res.getStatusCode();
                // Stop retrying on success or client error (4xx) — only retry on 5xx/network
                if (sc < 500) break;
                lastError = 'HTTP ' + sc + ': ' + res.getBody()?.left(200);
                if (attempt < maxAttempts) {
                    System.debug('HTTP retry ' + attempt + '/' + retryCount + ' after status ' + sc);
                }
            } catch (Exception e) {
                lastError = e.getMessage();
                res = null;
                if (attempt < maxAttempts) {
                    System.debug('HTTP retry ' + attempt + '/' + retryCount + ' after error: ' + lastError);
                }
            }
        }

        // Handle final failure
        if (res == null) {
            if (onFailure == 'continue') return new Map<String, Object>();
            throw new AuraHandledException('HTTP callout failed after ' + maxAttempts + ' attempt(s): ' + lastError);
        }

        Integer statusCode = res.getStatusCode();
        if (statusCode < 200 || statusCode >= 300) {
            String errorMsg = 'HTTP ' + statusCode + ': ' + res.getBody()?.left(200);
            if (onFailure == 'continue') {
                System.debug('HTTP step failed (continuing): ' + errorMsg);
                return new Map<String, Object>();
            }
            throw new AuraHandledException(errorMsg);
        }

        Map<String, Object> responseValues = new Map<String, Object>();
        List<Object> responseMappings = config.containsKey('responseMappings')
            ? (List<Object>) config.get('responseMappings')
            : new List<Object>();

        if (!responseMappings.isEmpty() && String.isNotBlank(res.getBody())) {
            try {
                Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                for (Object rm : responseMappings) {
                    Map<String, Object> mapping = (Map<String, Object>) rm;
                    String jsonPath       = (String) mapping.get('jsonPath');
                    String fieldValuesKey = (String) mapping.get('fieldValuesKey');
                    if (responseBody.containsKey(jsonPath)) {
                        responseValues.put(fieldValuesKey, responseBody.get(jsonPath));
                    }
                }
            } catch (Exception e) {
                System.debug('Could not parse response body: ' + e.getMessage());
            }
        }

        return responseValues;
    }
}
