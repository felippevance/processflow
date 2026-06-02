import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getExecutionHistory  from '@salesforce/apex/ProcessRunnerController.getExecutionHistory';
import getLogsForExecution  from '@salesforce/apex/ProcessRunnerController.getLogsForExecution';

export default class PflowHistory extends LightningElement {
    @api recordId;
    @track executions     = [];
    @track isLoading      = false;
    @track expandedExecId = null;
    @track stepLogs       = [];
    @track isLoadingLogs  = false;

    executionColumns = [
        { label: 'Status',        fieldName: 'FinalStatus__c',   type: 'text',
          cellAttributes: { class: { fieldName: 'statusClass' } } },
        { label: 'Started',       fieldName: 'StartedAt__c',     type: 'date',
          typeAttributes: { year: 'numeric', month: '2-digit', day: '2-digit',
                           hour: '2-digit', minute: '2-digit' } },
        { label: 'Completed',     fieldName: 'CompletedAt__c',   type: 'date',
          typeAttributes: { year: 'numeric', month: '2-digit', day: '2-digit',
                           hour: '2-digit', minute: '2-digit' } },
        { label: 'Target Record', fieldName: 'TargetRecordId__c', type: 'text' },
        { label: 'User',          fieldName: 'userName',          type: 'text' },
        { type: 'action', typeAttributes: { rowActions: [{ label: 'View Steps', name: 'view_steps' }] } }
    ];

    logColumns = [
        { label: 'Step',        fieldName: 'stepName',        type: 'text' },
        { label: 'Status',      fieldName: 'Status__c',       type: 'text',
          cellAttributes: { class: { fieldName: 'logStatusClass' } } },
        { label: 'Executed At', fieldName: 'ExecutedAt__c',   type: 'date',
          typeAttributes: { year: 'numeric', month: '2-digit', day: '2-digit',
                           hour: '2-digit', minute: '2-digit' } },
        { label: 'Error',       fieldName: 'ErrorMessage__c', type: 'text',
          wrapText: true, initialWidth: 350 }
    ];

    get hasExecutions()   { return this.executions.length > 0; }
    get hasStepLogs()     { return this.stepLogs.length > 0; }
    get showStepLogs()    { return this.expandedExecId !== null; }

    connectedCallback() {
        if (this.recordId) this.loadHistory();
    }

    async loadHistory() {
        this.isLoading = true;
        try {
            const raw = await getExecutionHistory({ processId: this.recordId });
            this.executions = raw.map(e => ({
                ...e,
                userName:    e.User__r?.Name || '—',
                statusClass: e.FinalStatus__c === 'Failed'    ? 'slds-text-color_error'
                           : e.FinalStatus__c === 'Completed' ? 'slds-text-color_success'
                           : 'slds-text-color_weak'
            }));
        } catch(e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: e.body?.message || 'Failed to load history', variant: 'error' }));
        } finally {
            this.isLoading = false;
        }
    }

    async handleRowAction(e) {
        const execId = e.detail.row.Id;
        if (this.expandedExecId === execId) {
            this.expandedExecId = null;
            this.stepLogs = [];
            return;
        }
        this.expandedExecId = execId;
        this.isLoadingLogs  = true;
        try {
            const raw = await getLogsForExecution({ executionId: execId });
            this.stepLogs = raw.map(l => ({
                ...l,
                stepName:       l.Step__r?.Name || '—',
                logStatusClass: l.Status__c === 'Error' ? 'slds-text-color_error' : 'slds-text-color_success'
            }));
        } catch(e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: e.body?.message || 'Failed to load step logs', variant: 'error' }));
        } finally {
            this.isLoadingLogs = false;
        }
    }

    closeStepLogs() {
        this.expandedExecId = null;
        this.stepLogs = [];
    }
}
