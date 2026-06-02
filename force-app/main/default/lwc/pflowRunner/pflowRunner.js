import { LightningElement, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getActiveProcesses         from '@salesforce/apex/ProcessRunnerController.getActiveProcesses';
import getOpenExecution           from '@salesforce/apex/ProcessRunnerController.getOpenExecution';
import getOpenExecutionForProcess from '@salesforce/apex/ProcessRunnerController.getOpenExecutionForProcess';
import startExecution             from '@salesforce/apex/ProcessRunnerController.startExecution';
import getProcessSteps            from '@salesforce/apex/ProcessRunnerController.getProcessSteps';
import executeStep                from '@salesforce/apex/ProcessRunnerController.executeStep';
import cancelExecution            from '@salesforce/apex/ProcessRunnerController.cancelExecution';
import getNextStage               from '@salesforce/apex/ProcessRunnerController.getNextStage';
import checkApprovalStatus from '@salesforce/apex/ApprovalController.checkApprovalStatus';
import cancelApproval      from '@salesforce/apex/ApprovalController.cancelApproval';
import checkSkipConditions from '@salesforce/apex/ProcessRunnerController.checkSkipConditions';

export default class PflowRunner extends NavigationMixin(LightningElement) {

    _processId;
    @api
    get processId() { return this._processId; }
    set processId(value) {
        this._processId = value;
        if (value) this.init();
    }

    @api recordId;      // injected automatically on Record Pages
    @api useRecordId;   // checkbox set by admin in App Builder

    @track processName    = 'Run a Process';
    @track activeProcesses = [];
    @track showProcessList = false;
    @track showExecution   = false;
    @track showSuccess     = false;
    @track stagesWithSteps   = [];
    @track currentStageIndex = 0;
    @track currentStepIndex  = 0;
    @track executionId       = null;
    @track fieldValues       = {};
    @track createdRecords    = [];
    @track isExecuting       = false;
    @track stepError         = null;
    @track showResumePrompt  = false;
    @track resumeExecution   = null;
    @track updateRecordId = '';
    @track isWaitingApproval         = false;
    @track approvalOnRejection       = 'Stop';
    @track approvalRejectionStageId  = null;
    _approvalPollTimer               = null;

    _initialized = false;

    connectedCallback() {
        if (!this._processId) this.init();
    }

    disconnectedCallback() {
        this.stopApprovalPolling();
    }

    async init() {
        if (this._initialized) return;
        this._initialized = true;
        try {
            // Check for in-progress execution for this specific process
            const openExec = this._processId
                ? await getOpenExecutionForProcess({ processId: this._processId })
                : await getOpenExecution();

            if (openExec) {
                // Show inline resume prompt instead of auto-cancelling
                this.resumeExecution  = openExec;
                this.showResumePrompt = true;
                return;
            }

            if (this._processId) {
                await this.startFresh(this._processId);
                return;
            }

            const processes = await getActiveProcesses();
            this.activeProcesses = processes;
            this.showProcessList = true;
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Failed to load', 'error');
        }
    }

    async startFresh(processId) {
        try {
            const targetRecordId = (this.useRecordId && this.recordId) ? this.recordId : null;
            const exec = await startExecution({ processId, targetRecordId });
            this.executionId = exec.Id;

            // If admin enabled "Use current record ID", seed it as recordId in fieldValues
            if (this.useRecordId && this.recordId) {
                this.fieldValues = { recordId: this.recordId };
            }

            await this.loadStepsAndContinue(processId, null);
        } catch (err) {
            this.showToast('Error', err.body?.message || 'Failed to start process', 'error');
        }
    }

    async handleResume() {
        this.showResumePrompt = false;
        const exec = this.resumeExecution;
        this.executionId = exec.Id;

        // Restore fieldValues from ExecutionData__c
        try {
            const execData = JSON.parse(exec.ExecutionData__c || '{}');
            this.fieldValues = execData.fieldValues || {};
        } catch(e) {
            this.fieldValues = {};
        }

        // If useRecordId, also seed recordId
        if (this.useRecordId && this.recordId) {
            this.fieldValues = { ...this.fieldValues, recordId: this.recordId };
        }

        await this.loadStepsAndContinue(exec.Process__c, exec.CurrentStep__c);
        this.resumeExecution = null;
    }

    async handleStartNew() {
        this.showResumePrompt = false;
        const oldExecId = this.resumeExecution?.Id;
        this.resumeExecution = null;
        if (oldExecId) {
            try { await cancelExecution({ executionId: oldExecId }); } catch(e) {}
        }
        if (this._processId) {
            await this.startFresh(this._processId);
        } else {
            const processes = await getActiveProcesses();
            this.activeProcesses = processes;
            this.showProcessList = true;
        }
    }

    async selectProcess(e) {
        const processId = e.currentTarget.dataset.processId;
        try {
            const exec = await startExecution({ processId, targetRecordId: null });
            this.executionId = exec.Id;
            await this.loadStepsAndContinue(processId, null);
        } catch (err) {
            this.showToast('Error', err.body?.message || 'Failed to start', 'error');
        }
    }

    async loadStepsAndContinue(processId, currentStepId) {
        const result = await getProcessSteps({ processId });
        this.stagesWithSteps = result;
        if (result.length > 0 && result[0].stage?.Process__r?.Name) {
            this.processName = result[0].stage.Process__r.Name;
        }
        this.currentStageIndex = 0;
        this.currentStepIndex  = 0;
        this.showProcessList   = false;
        this.showExecution     = true;
    }

    positionAtStep(stepId) {
        for (let si = 0; si < this.stagesWithSteps.length; si++) {
            const steps = this.stagesWithSteps[si].steps;
            for (let pi = 0; pi < steps.length; pi++) {
                if (steps[pi].Id === stepId) {
                    this.currentStageIndex = si;
                    this.currentStepIndex  = pi;
                    return;
                }
            }
        }
    }

    get currentStage()     { return this.stagesWithSteps[this.currentStageIndex]; }
    get currentStageName() { return this.currentStage?.stage?.Name || ''; }
    get totalStages()      { return this.stagesWithSteps.length; }
    get currentSteps()     { return this.currentStage?.steps || []; }
    get currentStep()      { return this.currentSteps[this.currentStepIndex]; }
    get currentStepName()  { return this.currentStep?.Name || ''; }
    get currentStepType()  { return this.currentStep?.Type__c || ''; }
    get totalSteps()       { return this.currentSteps.length; }

    get isFirstStep() { return this.currentStageIndex === 0 && this.currentStepIndex === 0; }
    get isLastStep() {
        return this.currentStepIndex === this.currentSteps.length - 1;
    }
    get isNotificationStep()  { return this.currentStepType === 'Notification'; }
    get isHttpStep()          { return this.currentStepType === 'HTTP Request'; }
    get isUpdateRecordStep()  { return this.currentStepType === 'Update Record'; }
    get hasRecordId()         { return !!this.fieldValues.recordId; }
    get executingLabel()     { return this.isHttpStep ? 'Calling external API...' : 'Processing...'; }
    get hasCreatedRecords()  { return this.createdRecords.length > 0; }

    get currentNotificationMessage() {
        if (!this.currentStep?.FieldsConfig__c) return '';
        try {
            const cfg = JSON.parse(this.currentStep.FieldsConfig__c);
            return cfg.messageTemplate || '';
        } catch { return ''; }
    }

    get currentFields() {
        if (!this.currentStep?.FieldsConfig__c || this.isNotificationStep || this.isHttpStep) return [];
        try {
            const raw = JSON.parse(this.currentStep.FieldsConfig__c);
            const fields = Array.isArray(raw) ? raw : (raw.fields || []);
            return fields.map(f => {
                const t = (f.type || 'STRING').toUpperCase();
                const isPicklist = t === 'PICKLIST' || t === 'MULTIPICKLIST';
                const isDate     = t === 'DATE';
                const isDateTime = t === 'DATETIME';
                const isCheckbox = t === 'BOOLEAN';
                const isNumber   = ['DOUBLE','INTEGER','LONG','CURRENCY','PERCENT'].includes(t);
                const isTextarea = ['TEXTAREA','LONGTEXTAREA','ENCRYPTEDSTRING'].includes(t);
                const isText     = !isPicklist && !isDate && !isDateTime && !isCheckbox && !isNumber && !isTextarea;
                const inputTypeMap = { EMAIL: 'email', PHONE: 'tel', URL: 'url' };
                return {
                    apiName:        f.apiName,
                    label:          f.label || f.apiName,
                    required:       f.required || false,
                    value:          this.fieldValues[f.apiName] !== undefined
                                        ? this.fieldValues[f.apiName]
                                        : (f.defaultValue || (isCheckbox ? false : '')),
                    isPicklist, isDate, isDateTime, isCheckbox, isNumber, isTextarea, isText,
                    inputType:       inputTypeMap[t] || 'text',
                    picklistOptions: (f.picklistValues || []).map(v => ({ label: v, value: v }))
                };
            });
        } catch { return []; }
    }

    get progressBarStyle() {
        const total = this.stagesWithSteps.reduce((acc, s) => acc + s.steps.length, 0);
        if (!total) return 'width: 0%';
        let done = 0;
        for (let si = 0; si < this.currentStageIndex; si++) done += this.stagesWithSteps[si].steps.length;
        done += this.currentStepIndex;
        return `width: ${Math.round((done / total) * 100)}%`;
    }

    handleFieldChange(e) {
        // lightning-combobox fires e.detail.value; lightning-input fires e.target.value
        const value = e.detail?.value !== undefined ? e.detail.value : e.target.value;
        this.fieldValues = { ...this.fieldValues, [e.currentTarget.dataset.fieldApi]: value };
    }

    handleCheckboxChange(e) {
        this.fieldValues = { ...this.fieldValues, [e.currentTarget.dataset.fieldApi]: e.target.checked };
    }

    handleRecordIdChange(e) {
        this.updateRecordId = e.target.value;
        this.fieldValues = { ...this.fieldValues, recordId: e.target.value };
    }

    async goNextStep() {
        this.isExecuting = true;
        this.stepError   = null;
        try {
            await this.executeCurrentStep(false);

            const isLastStepInStage = this.currentStepIndex === this.currentSteps.length - 1;

            if (!isLastStepInStage) {
                // Still in same stage — just advance step index
                this.currentStepIndex++;
                this.fieldValues = {};
            } else {
                // Last step in this stage — ask server for next stage (evaluates conditions)
                const result = await getNextStage({
                    executionId:    this.executionId,
                    currentStageId: this.currentStage.stage.Id
                });

                if (result.processComplete) {
                    this.showExecution = false;
                    this.showSuccess   = true;
                } else {
                    const newSws = { stage: result.stage, steps: result.steps };
                    this.stagesWithSteps = [
                        ...this.stagesWithSteps.slice(0, this.currentStageIndex + 1),
                        newSws
                    ];
                    this.currentStageIndex++;
                    this.currentStepIndex = 0;
                    this.fieldValues = {};
                }
            }
        } catch(e) {
            // error already set in executeCurrentStep
        } finally {
            this.isExecuting = false;
        }
    }

    goBackStep() {
        this.stepError = null;
        if (this.currentStepIndex > 0) {
            this.currentStepIndex--;
        } else if (this.currentStageIndex > 0) {
            this.currentStageIndex--;
            this.currentStepIndex = this.stagesWithSteps[this.currentStageIndex].steps.length - 1;
        }
        this.fieldValues = {};
    }

    async finishProcess() {
        this.isExecuting = true;
        this.stepError   = null;
        try {
            await this.executeCurrentStep(false); // don't delete yet — getNextStage handles completion

            const result = await getNextStage({
                executionId:    this.executionId,
                currentStageId: this.currentStage.stage.Id
            });

            if (result.processComplete) {
                // execution already deleted by getNextStage
                this.showExecution = false;
                this.showSuccess   = true;
            } else {
                // More stages exist — continue
                const newSws = { stage: result.stage, steps: result.steps };
                this.stagesWithSteps = [
                    ...this.stagesWithSteps.slice(0, this.currentStageIndex + 1),
                    newSws
                ];
                this.currentStageIndex++;
                this.currentStepIndex = 0;
                this.fieldValues = {};
            }
        } catch(e) {
            // error already displayed by executeCurrentStep
        } finally {
            this.isExecuting = false;
        }
    }

    clearError() {
        this.stepError = null;
    }

    async executeCurrentStep(isLast) {
        if (!this.executionId) {
            this.showToast('Error', 'No active execution found. Please refresh and try again.', 'error');
            throw new Error('No executionId');
        }

        // Check if this step should be skipped based on skip conditions
        const step = this.currentStep;
        if (step?.SkipConditionsConfig__c) {
            try {
                const skipResult = await checkSkipConditions({
                    stepId: step.Id,
                    executionId: this.executionId
                });
                if (skipResult === true) {
                    // Skip this step — don't execute, just return
                    return;
                }
            } catch(e) {
                // If condition check fails, proceed with execution
                console.warn('Skip condition check failed:', e);
            }
        }

        try {
            // Merge defaultValues for fields the user didn't touch
            const payload = {};
            try {
                const raw = JSON.parse(step.FieldsConfig__c || '[]');
                const fieldDefs = Array.isArray(raw) ? raw : (raw.fields || []);
                fieldDefs.forEach(f => {
                    if (f.defaultValue !== null && f.defaultValue !== undefined && f.defaultValue !== '') {
                        payload[f.apiName] = f.defaultValue;
                    }
                });
            } catch(e) {}
            // User-entered values override defaults
            Object.assign(payload, this.fieldValues);

            const result = await executeStep({
                stepId:        step.Id,
                stepType:      step.Type__c,
                targetObject:  step.TargetObject__c || '',
                fieldsConfig:  step.FieldsConfig__c || '[]',
                inputDataJson: JSON.stringify(payload),
                executionId:   this.executionId,
                isLastStep:    isLast
            });
            if (result?.isWaitingApproval) {
                this.isWaitingApproval        = true;
                this.approvalOnRejection      = result.onRejection      || 'Stop';
                this.approvalRejectionStageId = result.rejectionStageId || null;
                this.startApprovalPolling();
                return; // do not advance — polling handles next step
            }
            if (result?.createdRecordId) {
                this.createdRecords = [...this.createdRecords, {
                    id:         result.createdRecordId,
                    objectType: result.createdObjectType,
                    stepName:   step.Name,
                    label:      `${result.createdObjectType}: ${step.Name}`
                }];
            }
        } catch (err) {
            const msg = this.extractError(err);
            this.stepError = msg;
            console.error('executeStep error on [' + this.currentStep?.Name + ']:', msg, err);
            throw err;
        }
    }

    navigateToRecord(e) {
        const recordId = e.currentTarget.dataset.recordId;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: 'view' }
        });
    }

    startApprovalPolling() {
        this._approvalPollTimer = setInterval(() => this.pollApprovalStatus(), 5000);
    }

    stopApprovalPolling() {
        if (this._approvalPollTimer) {
            clearInterval(this._approvalPollTimer);
            this._approvalPollTimer = null;
        }
    }

    async pollApprovalStatus() {
        try {
            const result = await checkApprovalStatus({ executionId: this.executionId });

            if (result.status === 'Approved') {
                this.stopApprovalPolling();
                this.isWaitingApproval = false;

                const isLastStepInStage = this.currentStepIndex === this.currentSteps.length - 1;
                if (!isLastStepInStage) {
                    this.currentStepIndex++;
                    this.fieldValues = {};
                } else {
                    const nextResult = await getNextStage({
                        executionId:    this.executionId,
                        currentStageId: this.currentStage.stage.Id
                    });
                    if (nextResult.processComplete) {
                        this.showExecution = false;
                        this.showSuccess   = true;
                    } else {
                        const newSws = { stage: nextResult.stage, steps: nextResult.steps };
                        this.stagesWithSteps = [...this.stagesWithSteps.slice(0, this.currentStageIndex + 1), newSws];
                        this.currentStageIndex++;
                        this.currentStepIndex = 0;
                        this.fieldValues = {};
                    }
                }
            } else if (result.status === 'Rejected') {
                this.stopApprovalPolling();
                this.isWaitingApproval = false;

                if (this.approvalOnRejection === 'Execute Stage' && this.approvalRejectionStageId) {
                    const processId = this.stagesWithSteps[0]?.stage?.Process__c ||
                                      this.stagesWithSteps[0]?.stage?.Process__r?.Id;
                    const allStages = await getProcessSteps({ processId });
                    const rejStage = allStages.find(s => String(s.stage.Id) === String(this.approvalRejectionStageId));
                    if (rejStage) {
                        this.stagesWithSteps = [...this.stagesWithSteps.slice(0, this.currentStageIndex + 1), rejStage];
                        this.currentStageIndex++;
                        this.currentStepIndex = 0;
                        this.fieldValues = {};
                    }
                } else {
                    this.showExecution = false;
                    this.stepError = 'Approval was rejected. The process has been stopped.';
                }
            }
            // else still Pending — keep polling
        } catch(e) {
            this.stopApprovalPolling();
            this.stepError = e.body?.message || 'Failed to check approval status';
        }
    }

    async handleCancelApproval() {
        this.stopApprovalPolling();
        try {
            await cancelApproval({ executionId: this.executionId });
        } catch(e) { /* ignore */ }
        this.isWaitingApproval = false;
        this.resetRunner();
    }

    resetRunner() {
        this.stopApprovalPolling();
        this._initialized    = false;
        this.showSuccess     = false;
        this.updateRecordId  = '';
        this.showExecution   = false;
        this.showProcessList = false;
        this.showResumePrompt  = false;
        this.resumeExecution   = null;
        this.stagesWithSteps = [];
        this.executionId     = null;
        this.fieldValues     = {};
        this.createdRecords  = [];
        this.currentStageIndex = 0;
        this.currentStepIndex  = 0;
        this.isWaitingApproval = false;
        this.approvalOnRejection = 'Stop';
        this.approvalRejectionStageId = null;
        if (!this._processId) this.processName = 'Run a Process';
        this.init();
    }

    extractError(err) {
        try {
            if (!err) return 'Unknown error';
            // Apex AuraHandledException — most common
            if (err.body?.message) return err.body.message;
            // DML errors with field details
            if (err.body?.output?.errors?.length) {
                return err.body.output.errors.map(e => e.message || e.errorCode).join('; ');
            }
            // Nested fieldErrors (e.g. required field missing per field)
            if (err.body?.output?.fieldErrors) {
                const fe = err.body.output.fieldErrors;
                return Object.keys(fe).map(f => fe[f].map(e => `${f}: ${e.message}`).join(', ')).join('; ');
            }
            if (err.message) return err.message;
            try { return JSON.stringify(err); } catch(e) { return 'Step failed'; }
        } catch(e) {
            return 'An unexpected error occurred';
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
