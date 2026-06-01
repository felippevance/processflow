import { LightningElement, api, track } from 'lwc';
import getExecutionLogs from '@salesforce/apex/ProcessRunnerController.getExecutionLogs';

export default class PflowHistory extends LightningElement {
    @api recordId;
    @track logs = [];
    @track isLoading = false;

    columns = [
        { label: 'Step', fieldName: 'stepName', type: 'text' },
        { label: 'Status', fieldName: 'Status__c', type: 'text',
          cellAttributes: { class: { fieldName: 'statusClass' } } },
        { label: 'Executed At', fieldName: 'ExecutedAt__c', type: 'date',
          typeAttributes: { year: 'numeric', month: '2-digit', day: '2-digit',
                           hour: '2-digit', minute: '2-digit' } },
        { label: 'User', fieldName: 'userName', type: 'text' },
        { label: 'Error', fieldName: 'ErrorMessage__c', type: 'text',
          wrapText: true, initialWidth: 300 }
    ];

    get hasLogs() { return this.logs.length > 0; }

    connectedCallback() {
        if (this.recordId) this.loadLogs();
    }

    async loadLogs() {
        this.isLoading = true;
        try {
            const raw = await getExecutionLogs({ processId: this.recordId });
            this.logs = raw.map(r => ({
                ...r,
                stepName:    r.Step__r?.Name || '—',
                userName:    r.Execution__r?.User__r?.Name || '—',
                statusClass: r.Status__c === 'Error' ? 'slds-text-color_error' : 'slds-text-color_success'
            }));
        } catch(e) {
            console.error('Failed to load history:', e);
        } finally {
            this.isLoading = false;
        }
    }
}
