import { LightningElement, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getActiveProcesses         from '@salesforce/apex/ProcessRunnerController.getActiveProcesses';
import getOpenExecution           from '@salesforce/apex/ProcessRunnerController.getOpenExecution';
import startExecution             from '@salesforce/apex/ProcessRunnerController.startExecution';
import getProcessSteps            from '@salesforce/apex/ProcessRunnerController.getProcessSteps';
import executeStep                from '@salesforce/apex/ProcessRunnerController.executeStep';
import cancelExecution            from '@salesforce/apex/ProcessRunnerController.cancelExecution';
import getNextStage               from '@salesforce/apex/ProcessRunnerController.getNextStage';

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

    _initialized = false;

    connectedCallback() {
        if (!this._processId) this.init();
    }

    async init() {
        if (this._initialized) return;
        this._initialized = true;
        try {
            // Always cancel any open execution before starting fresh
            const openExec = await getOpenExecution();
            if (openExec) {
                try { await cancelExecution({ executionId: openExec.Id }); } catch(e) {}
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
    get isNotificationStep() { return this.currentStepType === 'Notification'; }
    get isHttpStep()         { return this.currentStepType === 'HTTP Request'; }
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
        try {
            const step = this.currentStep;

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

    resetRunner() {
        this._initialized    = false;
        this.showSuccess     = false;
        this.showExecution   = false;
        this.showProcessList = false;
        this.stagesWithSteps = [];
        this.executionId     = null;
        this.fieldValues     = {};
        this.createdRecords  = [];
        this.currentStageIndex = 0;
        this.currentStepIndex  = 0;
        if (!this._processId) this.processName = 'Run a Process';
        this.init();
    }

    extractError(err) {
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
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
