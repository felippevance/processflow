import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import saveProcess from '@salesforce/apex/ProcessBuilderController.saveProcess';
import getObjectFields from '@salesforce/apex/ProcessBuilderController.getObjectFields';
import getRecordTypes from '@salesforce/apex/ProcessBuilderController.getRecordTypes';

export default class PflowBuilder extends LightningElement {
    @track currentScreen = 1;
    @track processName = '';
    @track processDescription = '';
    @track processIsActive = true;
    @track stages = [];
    @track isSaving = false;

    stepTypeOptions = [
        { label: 'Create Record', value: 'Create Record' },
        { label: 'Update Record', value: 'Update Record' },
        { label: 'Notification',  value: 'Notification'  }
    ];

    get isScreen1() { return this.currentScreen === 1; }
    get isScreen2() { return this.currentScreen === 2; }
    get isScreen3() { return this.currentScreen === 3; }
    get isScreen4() { return this.currentScreen === 4; }

    get stepClass1() { return this.currentScreen >= 1 ? 'slds-progress__item slds-is-active' : 'slds-progress__item'; }
    get stepClass2() { return this.currentScreen >= 2 ? 'slds-progress__item slds-is-active' : 'slds-progress__item'; }
    get stepClass3() { return this.currentScreen >= 3 ? 'slds-progress__item slds-is-active' : 'slds-progress__item'; }
    get stepClass4() { return this.currentScreen >= 4 ? 'slds-progress__item slds-is-active' : 'slds-progress__item'; }

    handleProcessName(e)        { this.processName = e.target.value; }
    handleProcessDescription(e) { this.processDescription = e.target.value; }
    handleProcessActive(e)      { this.processIsActive = e.target.checked; }

    addStage() {
        this.stages = [...this.stages, { id: Date.now(), name: '', sequence: this.stages.length + 1, steps: [] }];
    }
    removeStage(e) {
        const idx = parseInt(e.currentTarget.dataset.idx, 10);
        this.stages = this.stages.filter((_, i) => i !== idx).map((s, i) => ({ ...s, sequence: i + 1 }));
    }
    handleStageName(e) {
        const idx = parseInt(e.currentTarget.dataset.idx, 10);
        this.stages = this.stages.map((s, i) => i === idx ? { ...s, name: e.target.value } : s);
    }

    addStep(e) {
        const stageIdx = parseInt(e.currentTarget.dataset.stageIdx, 10);
        this.stages = this.stages.map((s, i) => {
            if (i !== stageIdx) return s;
            return { ...s, steps: [...s.steps, { id: Date.now(), name: '', sequence: s.steps.length + 1, type: '', targetObject: '', fieldOptions: [], fieldMeta: {}, hasFieldOptions: false, selectedFields: [], messageTemplate: '', showObjectPicker: false, showNotificationConfig: false, recordTypeId: null, recordTypeOptions: [], hasRecordTypes: false }] };
        });
    }
    handleStepName(e) {
        const si = parseInt(e.currentTarget.dataset.stageIdx, 10);
        const pi = parseInt(e.currentTarget.dataset.stepIdx, 10);
        this.stages = this.stages.map((s, i) => i !== si ? s : { ...s, steps: s.steps.map((st, j) => j !== pi ? st : { ...st, name: e.target.value }) });
    }
    handleStepType(e) {
        const si = parseInt(e.currentTarget.dataset.stageIdx, 10);
        const pi = parseInt(e.currentTarget.dataset.stepIdx, 10);
        const type = e.detail.value;
        this.stages = this.stages.map((s, i) => i !== si ? s : {
            ...s, steps: s.steps.map((st, j) => j !== pi ? st : {
                ...st, type, showObjectPicker: (type === 'Create Record' || type === 'Update Record'), showNotificationConfig: type === 'Notification'
            })
        });
    }
    handleTargetObject(e) {
        const si = parseInt(e.currentTarget.dataset.stageIdx, 10);
        const pi = parseInt(e.currentTarget.dataset.stepIdx, 10);
        this.stages = this.stages.map((s, i) => i !== si ? s : { ...s, steps: s.steps.map((st, j) => j !== pi ? st : { ...st, targetObject: e.target.value }) });
    }
    async loadFields(e) {
        const si = parseInt(e.currentTarget.dataset.stageIdx, 10);
        const pi = parseInt(e.currentTarget.dataset.stepIdx, 10);
        const step = this.stages[si].steps[pi];
        if (!step.targetObject) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Warning', message: 'Enter the object API name first.', variant: 'warning' }));
            return;
        }
        try {
            const [fields, recordTypes] = await Promise.all([
                getObjectFields({ objectApiName: step.targetObject }),
                getRecordTypes({ objectApiName: step.targetObject })
            ]);
            const fieldMeta = {};
            fields.forEach(f => { fieldMeta[f.apiName] = f; });
            this.stages = this.stages.map((s, i) => i !== si ? s : {
                ...s, steps: s.steps.map((st, j) => j !== pi ? st : {
                    ...st,
                    fieldOptions: fields.map(f => ({
                        apiName:        f.apiName,
                        label:          `${f.label} (${f.apiName})`,
                        required:       f.required,
                        type:           f.type,
                        picklistValues: f.picklistValues || []
                    })),
                    fieldMeta,
                    hasFieldOptions:  fields.length > 0,
                    selectedFields:   fields.filter(f => f.required).map(f => f.apiName),
                    recordTypeOptions: recordTypes.map(rt => ({ label: rt.name, value: rt.id })),
                    hasRecordTypes:    recordTypes.length > 0,
                    recordTypeId:      null
                })
            });
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: err.body?.message || 'Failed to load fields', variant: 'error' }));
        }
    }
    handleFieldToggle(e) {
        const si = parseInt(e.currentTarget.dataset.stageIdx, 10);
        const pi = parseInt(e.currentTarget.dataset.stepIdx, 10);
        const fieldApi = e.currentTarget.dataset.fieldApi;
        const checked = e.target.checked;
        this.stages = this.stages.map((s, i) => i !== si ? s : {
            ...s, steps: s.steps.map((st, j) => {
                if (j !== pi) return st;
                const selected = checked ? [...st.selectedFields, fieldApi] : st.selectedFields.filter(f => f !== fieldApi);
                return { ...st, selectedFields: selected };
            })
        });
    }
    handleRecordType(e) {
        const si = parseInt(e.currentTarget.dataset.stageIdx, 10);
        const pi = parseInt(e.currentTarget.dataset.stepIdx, 10);
        this.stages = this.stages.map((s, i) => i !== si ? s : {
            ...s, steps: s.steps.map((st, j) => j !== pi ? st : { ...st, recordTypeId: e.detail.value })
        });
    }
    handleMessageTemplate(e) {
        const si = parseInt(e.currentTarget.dataset.stageIdx, 10);
        const pi = parseInt(e.currentTarget.dataset.stepIdx, 10);
        this.stages = this.stages.map((s, i) => i !== si ? s : { ...s, steps: s.steps.map((st, j) => j !== pi ? st : { ...st, messageTemplate: e.target.value }) });
    }

    goNext() { if (this.currentScreen < 4) this.currentScreen++; }
    goBack() { if (this.currentScreen > 1) this.currentScreen--; }

    async saveProcess() {
        this.isSaving = true;
        try {
            const payload = {
                name: this.processName,
                description: this.processDescription,
                isActive: this.processIsActive,
                stages: this.stages.map(s => ({
                    name: s.name,
                    sequence: s.sequence,
                    steps: s.steps.map(st => ({
                        name: st.name,
                        sequence: st.sequence,
                        type: st.type,
                        targetObject: st.targetObject || null,
                        fieldsConfig: st.type === 'Notification'
                            ? JSON.stringify({ messageTemplate: st.messageTemplate })
                            : JSON.stringify({
                                recordTypeId: st.recordTypeId || null,
                                fields: st.selectedFields.map(f => {
                                    const meta = st.fieldMeta?.[f] || {};
                                    return {
                                        apiName:        f,
                                        label:          meta.label || f,
                                        type:           meta.type  || 'STRING',
                                        required:       meta.required || false,
                                        defaultValue:   null,
                                        picklistValues: meta.picklistValues || []
                                    };
                                })
                            }),
                        isRequired: false
                    }))
                }))
            };
            await saveProcess({ payloadJson: JSON.stringify(payload) });
            this.dispatchEvent(new ShowToastEvent({ title: 'Success', message: 'Process saved successfully!', variant: 'success' }));
            this.currentScreen = 1;
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: error.body?.message || 'Save failed', variant: 'error' }));
        } finally {
            this.isSaving = false;
        }
    }
}
