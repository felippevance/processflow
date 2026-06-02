@RestResource(urlMapping='/processflow/v1/*')
global with sharing class ProcessFlowRestApiV1 {

    // Standard response wrapper — always HTTP 200
    global class ApiResponse {
        public String status;       // success | failed | pending_approval | completed | cancelled
        public Object data;
        public String error;
        public String executionId;

        public ApiResponse success(Object d) { this.status = 'success'; this.data = d; return this; }
        public ApiResponse completed(Object d) { this.status = 'completed'; this.data = d; return this; }
        public ApiResponse failed(String msg) { this.status = 'failed'; this.error = msg; return this; }
        public ApiResponse pendingApproval(String execId) { this.status = 'pending_approval'; this.executionId = execId; return this; }
    }

    // ─── GET /processflow/v1/processes ──────────────────────────────────────
    // ─── GET /processflow/v1/executions/{id}/status ─────────────────────────
    @HttpGet
    global static void doGet() {
        RestRequest req   = RestContext.request;
        RestResponse res  = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            String path = req.requestURI;

            if (path.endsWith('/processes') || path.contains('/processes?')) {
                handleGetProcesses(res);
            } else if (path.contains('/executions/') && path.endsWith('/status')) {
                String execId = extractSegment(path, '/executions/', '/status');
                handleGetStatus(res, execId);
            } else {
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ApiResponse().failed('Unknown endpoint: ' + path)
                ));
            }
        } catch (Exception e) {
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ApiResponse().failed('Internal error: ' + e.getMessage())
            ));
        }
    }

    // ─── POST /processflow/v1/processes/{externalId}/execute ────────────────
    // ─── POST /processflow/v1/executions/{id}/step ──────────────────────────
    @HttpPost
    global static void doPost() {
        RestRequest req  = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            String path = req.requestURI;
            String body = req.requestBody != null ? req.requestBody.toString() : '{}';

            if (path.contains('/processes/') && path.endsWith('/execute')) {
                String externalId = extractSegment(path, '/processes/', '/execute');
                handleExecute(res, externalId, body);
            } else if (path.contains('/executions/') && path.endsWith('/step')) {
                String execId = extractSegment(path, '/executions/', '/step');
                handleStep(res, execId, body);
            } else {
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new ApiResponse().failed('Unknown endpoint: ' + path)
                ));
            }
        } catch (Exception e) {
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ApiResponse().failed('Internal error: ' + e.getMessage())
            ));
        }
    }

    // ─── DELETE /processflow/v1/executions/{id} ─────────────────────────────
    @HttpDelete
    global static void doDelete() {
        RestRequest req  = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            String path   = req.requestURI;
            String execId = extractLastSegment(path);
            handleCancel(res, execId);
        } catch (Exception e) {
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ApiResponse().failed('Internal error: ' + e.getMessage())
            ));
        }
    }

    // ─── Handlers ────────────────────────────────────────────────────────────

    private static void handleGetProcesses(RestResponse res) {
        List<Process__c> processes = [
            SELECT Id, Name, ExternalId__c, Description__c, Version__c
            FROM Process__c
            WHERE IsActive__c = true AND IsCurrentVersion__c = true
            WITH SECURITY_ENFORCED
            ORDER BY Name
        ];
        List<Map<String,Object>> result = new List<Map<String,Object>>();
        for (Process__c p : processes) {
            result.add(new Map<String,Object>{
                'id'          => p.Id,
                'externalId'  => p.ExternalId__c,
                'name'        => p.Name,
                'description' => p.Description__c,
                'version'     => p.Version__c
            });
        }
        res.responseBody = Blob.valueOf(JSON.serialize(
            new ApiResponse().success(result)
        ));
    }

    private static void handleGetStatus(RestResponse res, String execId) {
        List<Execution__c> execs = [
            SELECT Id, Status__c, FinalStatus__c, StartedAt__c, CompletedAt__c,
                   Process__r.Name, Process__r.ExternalId__c,
                   CurrentStage__r.Name, CurrentStep__r.Name,
                   PendingApprovalId__c, TargetRecordId__c
            FROM Execution__c
            WHERE Id = :execId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (execs.isEmpty()) {
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ApiResponse().failed('Execution not found: ' + execId)
            ));
            return;
        }
        Execution__c exec = execs[0];
        String status = exec.FinalStatus__c != null ? exec.FinalStatus__c.toLowerCase()
                      : String.isNotBlank(exec.PendingApprovalId__c) ? 'pending_approval'
                      : 'in_progress';

        Map<String,Object> data = new Map<String,Object>{
            'executionId'    => exec.Id,
            'status'         => status,
            'processName'    => exec.Process__r?.Name,
            'processExtId'   => exec.Process__r?.ExternalId__c,
            'currentStage'   => exec.CurrentStage__r?.Name,
            'currentStep'    => exec.CurrentStep__r?.Name,
            'startedAt'      => exec.StartedAt__c,
            'completedAt'    => exec.CompletedAt__c,
            'targetRecordId' => exec.TargetRecordId__c
        };
        res.responseBody = Blob.valueOf(JSON.serialize(
            new ApiResponse().success(data)
        ));
    }

    private static void handleExecute(RestResponse res, String externalId, String body) {
        // Find process by ExternalId__c
        List<Process__c> procs = [
            SELECT Id, Name, ExternalId__c
            FROM Process__c
            WHERE ExternalId__c = :externalId AND IsActive__c = true AND IsCurrentVersion__c = true
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (procs.isEmpty()) {
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ApiResponse().failed('Process not found with ExternalId: ' + externalId)
            ));
            return;
        }

        Map<String,Object> payload = ProcessFlowJsonUtil.toMap(body);
        String targetRecordId = (String) payload.get('targetRecordId');

        Execution__c exec = ProcessRunnerController.startExecution(procs[0].Id, targetRecordId);

        Map<String,Object> data = new Map<String,Object>{
            'executionId' => exec.Id,
            'processId'   => procs[0].Id,
            'processName' => procs[0].Name,
            'status'      => 'in_progress'
        };
        res.responseBody = Blob.valueOf(JSON.serialize(
            new ApiResponse().success(data)
        ));
    }

    private static void handleStep(RestResponse res, String execId, String body) {
        // Load execution and current step
        List<Execution__c> execs = [
            SELECT Id, CurrentStep__c, FinalStatus__c, CurrentStage__c, Process__c
            FROM Execution__c
            WHERE Id = :execId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (execs.isEmpty()) {
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ApiResponse().failed('Execution not found: ' + execId)
            ));
            return;
        }
        Execution__c exec = execs[0];
        if (exec.FinalStatus__c != null) {
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ApiResponse().failed('Execution already completed with status: ' + exec.FinalStatus__c)
            ));
            return;
        }

        // Load current step
        List<Step__c> steps = [
            SELECT Id, Name, Type__c, TargetObject__c, FieldsConfig__c,
                   IsRequired__c, RequiresApproval__c, ApprovalProcessName__c,
                   SkipConditionsConfig__c, SkipConditionLogic__c
            FROM Step__c
            WHERE Id = :exec.CurrentStep__c
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (steps.isEmpty()) {
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ApiResponse().failed('Current step not found on execution')
            ));
            return;
        }
        Step__c step = steps[0];

        // Merge caller field values with defaultValues from FieldsConfig
        Map<String,Object> callerValues = ProcessFlowJsonUtil.toMap(body);
        Map<String,Object> payload = new Map<String,Object>();

        // Apply defaults first
        List<Object> fieldDefs = ProcessFlowJsonUtil.getFieldDefs(step.FieldsConfig__c);
        for (Object fd : fieldDefs) {
            Map<String,Object> f = (Map<String,Object>) fd;
            String apiName = (String) f.get('apiName');
            Object defVal  = f.get('defaultValue');
            if (apiName != null && defVal != null) payload.put(apiName, defVal);
        }
        // Caller values override defaults
        payload.putAll(callerValues);

        // Determine if last step — check getNextStage
        ProcessExecutionEngine.StepResult result = ProcessRunnerController.executeStep(
            step.Id, step.Type__c, step.TargetObject__c,
            step.FieldsConfig__c, JSON.serialize(payload), execId, false
        );

        if (result.isWaitingApproval == true) {
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ApiResponse().pendingApproval(execId)
            ));
            return;
        }

        // Check next stage
        ProcessRunnerController.NextStageResult next = ProcessRunnerController.getNextStage(execId, exec.CurrentStage__c);

        Map<String,Object> data = new Map<String,Object>{
            'executionId'     => execId,
            'stepName'        => step.Name,
            'createdRecordId' => result.createdRecordId,
            'processComplete' => next.processComplete
        };
        if (!next.processComplete && next.stage != null) {
            data.put('nextStage', next.stage.Name);
            data.put('nextStep',  next.steps.isEmpty() ? null : next.steps[0].Name);
        }

        res.responseBody = Blob.valueOf(JSON.serialize(
            next.processComplete
                ? new ApiResponse().completed(data)
                : new ApiResponse().success(data)
        ));
    }

    private static void handleCancel(RestResponse res, String execId) {
        List<Execution__c> execs = [
            SELECT Id, FinalStatus__c FROM Execution__c WHERE Id = :execId WITH SECURITY_ENFORCED LIMIT 1
        ];
        if (execs.isEmpty()) {
            res.responseBody = Blob.valueOf(JSON.serialize(
                new ApiResponse().failed('Execution not found: ' + execId)
            ));
            return;
        }
        ProcessRunnerController.cancelExecution(execId);
        res.responseBody = Blob.valueOf(JSON.serialize(
            new ApiResponse().success(new Map<String,Object>{'executionId'=>execId,'status'=>'cancelled'})
        ));
    }

    // ─── URL Helpers ─────────────────────────────────────────────────────────

    private static String extractSegment(String path, String prefix, String suffix) {
        Integer startIdx = path.indexOf(prefix);
        if (startIdx == -1) return '';
        startIdx += prefix.length();
        Integer endIdx = path.indexOf(suffix, startIdx);
        return endIdx == -1 ? path.substring(startIdx) : path.substring(startIdx, endIdx);
    }

    private static String extractLastSegment(String path) {
        List<String> parts = path.split('/');
        return parts.isEmpty() ? '' : parts[parts.size() - 1];
    }
}
