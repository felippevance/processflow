import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProcessSteps from '@salesforce/apex/ProcessRunnerController.getProcessSteps';
import getProcessDetails from '@salesforce/apex/ProcessViewerController.getProcessDetails';

const TYPE_ICONS = {
    'Create Record': 'utility:add',
    'Update Record': 'utility:edit',
    'Notification':  'utility:notification'
};
const TYPE_LABELS = {
    'Create Record': 'Creates a record',
    'Update Record': 'Updates a record',
    'Notification':  'Sends a notification'
};

export default class PflowViewer extends LightningElement {
    @api recordId;
    @api processId; // kept for metadata compatibility — recordId takes precedence

    @track processName = '';
    @track processDescription = '';
    @track processVersion = null;
    @track stagesWithSteps = [];
    @track isLoading = false;

    get showEmpty() { return !this.isLoading && !this.recordId; }
    get showContent() { return !this.isLoading && this.recordId && this.stagesWithSteps.length > 0; }
    get versionLabel() { return `v${this.processVersion}`; }

    connectedCallback() {
        if (this.recordId) this.loadProcess();
    }

    async loadProcess() {
        this.isLoading = true;
        try {
            const [details, stagesData] = await Promise.all([
                getProcessDetails({ processId: this.recordId }),
                getProcessSteps({ processId: this.recordId })
            ]);

            this.processName        = details.Name;
            this.processDescription = details.Description__c;
            this.processVersion     = details.Version__c;

            this.stagesWithSteps = stagesData.map(s => {
                let conditions = [];
                try {
                    if (s.stage.ConditionsConfig__c) {
                        conditions = JSON.parse(s.stage.ConditionsConfig__c);
                    }
                } catch(e) {}
                return {
                    stage: s.stage,
                    conditionLogic: s.stage.ConditionLogic__c || 'AND',
                    conditions,
                    hasConditions: conditions.length > 0,
                    steps: s.steps.map(st => {
                        let fieldCount = 0;
                        const targetObjectName = st.TargetObject__c || '';
                        try {
                            const cfg = JSON.parse(st.FieldsConfig__c || '[]');
                            fieldCount = Array.isArray(cfg) ? cfg.length : (cfg.fields ? cfg.fields.length : 0);
                        } catch(e) {}
                        return {
                            ...st,
                            typeIcon:        TYPE_ICONS[st.Type__c] || 'utility:flow',
                            typeLabel:       TYPE_LABELS[st.Type__c] || st.Type__c,
                            targetObjectName,
                            fieldCount:      fieldCount || null
                        };
                    })
                };
            });
        } catch (e) {
            this.showToast('Error', e.body?.message || 'Failed to load process', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
