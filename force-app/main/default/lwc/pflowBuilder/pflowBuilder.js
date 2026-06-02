import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import saveProcess from '@salesforce/apex/ProcessBuilderController.saveProcess';
import getObjectFields from '@salesforce/apex/ProcessBuilderController.getObjectFields';
import getRecordTypes from '@salesforce/apex/ProcessBuilderController.getRecordTypes';
import getNamedCredentials from '@salesforce/apex/ProcessBuilderController.getNamedCredentials';

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
        { label: 'Notification',  value: 'Notification'  },
        { label: 'HTTP Request',  value: 'HTTP Request'  }
    ];

    httpMethodOptions = [
        { label: 'GET',    value: 'GET'    },
        { label: 'POST',   value: 'POST'   },
        { label: 'PUT',    value: 'PUT'    },
        { label: 'PATCH',  value: 'PATCH'  },
        { label: 'DELETE', value: 'DELETE' }
    ];

    httpOnFailureOptions = [
        { label: 'Stop process',          value: 'stop'     },
        { label: 'Continue to next step', value: 'continue' }
    ];

    @track namedCredentialOptions = [];

    conditionLogicOptions = [
        { label: 'AND — all conditions must match', value: 'AND' },
        { label: 'OR — any condition must match',   value: 'OR'  }
    ];

    conditionSourceOptions = [
        { label: 'Field value (entered by user)', value: 'fieldValue'    },
        { label: 'Created record field',          value: 'createdRecord' }
    ];

    conditionOperatorOptions = [
        { label: 'equals',        value: 'equals'       },
        { label: 'not equals',    value: 'not_equals'   },
        { label: 'is empty',      value: 'is_empty'     },
        { label: 'is not empty',  value: 'is_not_empty' }
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
        this.stages = [...this.stages, {
            id: Date.now(),
            name: '',
            sequence: this.stages.length + 1,
            steps: [],
            conditionLogic: 'AND',
            conditions: [],
            showConditions: false
        }];
    }
    removeStage(e) {
        const idx = parseInt(e.currentTarget.dataset.idx, 10);
        this.stages = this.stages.filter((_, i) => i !== idx).map((s, i) => ({ ...s, sequence: i + 1 }));
    }
    handleStageName(e) {
        const idx = parseInt(e.currentTarget.dataset.idx, 10);
        this.stages = this.stages.map((s, i) => i === idx ? { ...s, name: e.target.value } : s);
    }

    toggleConditions(e) {
        const idx = parseInt(e.currentTarget.dataset.idx, 10);
        this.stages = this.stages.map((s, i) => i !== idx ? s : { ...s, showConditions: !s.showConditions });
    }

    handleConditionLogic(e) {
        const idx = parseInt(e.currentTarget.dataset.idx, 10);
        this.stages = this.stages.map((s, i) => i !== idx ? s : { ...s, conditionLogic: e.detail.value });
    }

    addCondition(e) {
        const idx = parseInt(e.currentTarget.dataset.idx, 10);
        this.stages = this.stages.map((s, i) => i !== idx ? s : {
            ...s,
            conditions: [...s.conditions, {
                id: Date.now(),
                source: 'fieldValue',
                field: '',
                stepName: '',
                operator: 'equals',
                value: '',
                isCreatedRecord: false,
                isEmptyOperator: false
            }]
        });
    }

    removeCondition(e) {
        const idx     = parseInt(e.currentTarget.dataset.idx, 10);
        const condIdx = parseInt(e.currentTarget.dataset.condIdx, 10);
        this.stages = this.stages.map((s, i) => i !== idx ? s : {
            ...s, conditions: s.conditions.filter((_, ci) => ci !== condIdx)
        });
    }

    handleConditionSource(e) {
        const idx     = parseInt(e.currentTarget.dataset.idx, 10);
        const condIdx = parseInt(e.currentTarget.dataset.condIdx, 10);
        const src = e.detail.value;
        this.stages = this.stages.map((s, i) => i !== idx ? s : {
            ...s, conditions: s.conditions.map((c, ci) => ci !== condIdx ? c : {
                ...c, source: src, isCreatedRecord: src === 'createdRecord'
            })
        });
    }

    handleConditionField(e) {
        const idx     = parseInt(e.currentTarget.dataset.idx, 10);
        const condIdx = parseInt(e.currentTarget.dataset.condIdx, 10);
        this.stages = this.stages.map((s, i) => i !== idx ? s : {
            ...s, conditions: s.conditions.map((c, ci) => ci !== condIdx ? c : { ...c, field: e.target.value })
        });
    }

    handleConditionStepName(e) {
        const idx     = parseInt(e.currentTarget.dataset.idx, 10);
        const condIdx = parseInt(e.currentTarget.dataset.condIdx, 10);
        this.stages = this.stages.map((s, i) => i !== idx ? s : {
            ...s, conditions: s.conditions.map((c, ci) => ci !== condIdx ? c : { ...c, stepName: e.target.value })
        });
    }

    handleConditionOperator(e) {
        const idx     = parseInt(e.currentTarget.dataset.idx, 10);
        const condIdx = parseInt(e.currentTarget.dataset.condIdx, 10);
        const op = e.detail.value;
        this.stages = this.stages.map((s, i) => i !== idx ? s : {
            ...s, conditions: s.conditions.map((c, ci) => ci !== condIdx ? c : {
                ...c, operator: op, isEmptyOperator: op === 'is_empty' || op === 'is_not_empty'
            })
        });
    }

    handleConditionValue(e) {
        const idx     = parseInt(e.currentTarget.dataset.idx, 10);
        const condIdx = parseInt(e.currentTarget.dataset.condIdx, 10);
        this.stages = this.stages.map((s, i) => i !== idx ? s : {
            ...s, conditions: s.conditions.map((c, ci) => ci !== condIdx ? c : { ...c, value: e.target.value })
        });
    }

    addStep(e) {
        const stageIdx = parseInt(e.currentTarget.dataset.stageIdx, 10);
        this.stages = this.stages.map((s, i) => {
            if (i !== stageIdx) return s;
            return { ...s, steps: [...s.steps, { id: Date.now(), name: '', sequence: s.steps.length + 1, type: '', targetObject: '', fieldOptions: [], fieldMeta: {}, hasFieldOptions: false, selectedFields: [], messageTemplate: '', showObjectPicker: false, showNotificationConfig: false, showHttpConfig: false, recordTypeId: null, recordTypeOptions: [], hasRecordTypes: false, httpNamedCredential: '', httpMethod: 'POST', httpPath: '', httpHeaders: [], httpBodyMappings: [], httpResponseMappings: [], httpTimeout: 30, httpRetry: false, httpOnFailure: 'stop' }] };
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
                ...st,
                type,
                showObjectPicker:       (type === 'Create Record' || type === 'Update Record'),
                showNotificationConfig: type === 'Notification',
                showHttpConfig:         type === 'HTTP Request'
            })
        });
        if (type === 'HTTP Request' && this.namedCredentialOptions.length === 0) {
            this.loadNamedCredentials();
        }
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

    async loadNamedCredentials() {
        try {
            const creds = await getNamedCredentials();
            this.namedCredentialOptions = creds;
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: err.body?.message || 'Failed to load Named Credentials', variant: 'error' }));
        }
    }

    handleHttpField(e) {
        const si    = parseInt(e.currentTarget.dataset.stageIdx, 10);
        const pi    = parseInt(e.currentTarget.dataset.stepIdx, 10);
        const field = e.currentTarget.dataset.field;
        const value = e.detail?.value !== undefined ? e.detail.value : e.target.value;
        this.stages = this.stages.map((s, i) => i !== si ? s : {
            ...s, steps: s.steps.map((st, j) => j !== pi ? st : { ...st, [field]: value })
        });
    }

    handleHttpRetry(e) {
        const si = parseInt(e.currentTarget.dataset.stageIdx, 10);
        const pi = parseInt(e.currentTarget.dataset.stepIdx, 10);
        this.stages = this.stages.map((s, i) => i !== si ? s : {
            ...s, steps: s.steps.map((st, j) => j !== pi ? st : { ...st, httpRetry: e.target.checked })
        });
    }

    addHttpHeader(e) {
        const si = parseInt(e.currentTarget.dataset.stageIdx, 10);
        const pi = parseInt(e.currentTarget.dataset.stepIdx, 10);
        this.stages = this.stages.map((s, i) => i !== si ? s : {
            ...s, steps: s.steps.map((st, j) => j !== pi ? st : {
                ...st, httpHeaders: [...st.httpHeaders, { id: Date.now(), key: '', value: '' }]
            })
        });
    }

    removeHttpHeader(e) {
        const si  = parseInt(e.currentTarget.dataset.stageIdx, 10);
        const pi  = parseInt(e.currentTarget.dataset.stepIdx, 10);
        const idx = parseInt(e.currentTarget.dataset.idx, 10);
        this.stages = this.stages.map((s, i) => i !== si ? s : {
            ...s, steps: s.steps.map((st, j) => j !== pi ? st : {
                ...st, httpHeaders: st.httpHeaders.filter((_, hi) => hi !== idx)
            })
        });
    }

    handleHttpHeaderKey(e) {
        const si  = parseInt(e.currentTarget.dataset.stageIdx, 10);
        const pi  = parseInt(e.currentTarget.dataset.stepIdx, 10);
        const idx = parseInt(e.currentTarget.dataset.idx, 10);
        this.stages = this.stages.map((s, i) => i !== si ? s : {
            ...s, steps: s.steps.map((st, j) => j !== pi ? st : {
                ...st, httpHeaders: st.httpHeaders.map((h, hi) => hi !== idx ? h : { ...h, key: e.target.value })
            })
        });
    }

    handleHttpHeaderValue(e) {
        const si  = parseInt(e.currentTarget.dataset.stageIdx, 10);
        const pi  = parseInt(e.currentTarget.dataset.stepIdx, 10);
        const idx = parseInt(e.currentTarget.dataset.idx, 10);
        this.stages = this.stages.map((s, i) => i !== si ? s : {
            ...s, steps: s.steps.map((st, j) => j !== pi ? st : {
                ...st, httpHeaders: st.httpHeaders.map((h, hi) => hi !== idx ? h : { ...h, value: e.target.value })
            })
        });
    }

    addHttpBodyMapping(e) {
        const si = parseInt(e.currentTarget.dataset.stageIdx, 10);
        const pi = parseInt(e.currentTarget.dataset.stepIdx, 10);
        this.stages = this.stages.map((s, i) => i !== si ? s : {
            ...s, steps: s.steps.map((st, j) => j !== pi ? st : {
                ...st, httpBodyMappings: [...st.httpBodyMappings, { id: Date.now(), jsonKey: '', processField: '' }]
            })
        });
    }

    removeHttpBodyMapping(e) {
        const si  = parseInt(e.currentTarget.dataset.stageIdx, 10);
        const pi  = parseInt(e.currentTarget.dataset.stepIdx, 10);
        const idx = parseInt(e.currentTarget.dataset.idx, 10);
        this.stages = this.stages.map((s, i) => i !== si ? s : {
            ...s, steps: s.steps.map((st, j) => j !== pi ? st : {
                ...st, httpBodyMappings: st.httpBodyMappings.filter((_, bi) => bi !== idx)
            })
        });
    }

    handleHttpBodyMappingKey(e) {
        const si  = parseInt(e.currentTarget.dataset.stageIdx, 10);
        const pi  = parseInt(e.currentTarget.dataset.stepIdx, 10);
        const idx = parseInt(e.currentTarget.dataset.idx, 10);
        this.stages = this.stages.map((s, i) => i !== si ? s : {
            ...s, steps: s.steps.map((st, j) => j !== pi ? st : {
                ...st, httpBodyMappings: st.httpBodyMappings.map((m, mi) => mi !== idx ? m : { ...m, jsonKey: e.target.value })
            })
        });
    }

    handleHttpBodyMappingField(e) {
        const si  = parseInt(e.currentTarget.dataset.stageIdx, 10);
        const pi  = parseInt(e.currentTarget.dataset.stepIdx, 10);
        const idx = parseInt(e.currentTarget.dataset.idx, 10);
        this.stages = this.stages.map((s, i) => i !== si ? s : {
            ...s, steps: s.steps.map((st, j) => j !== pi ? st : {
                ...st, httpBodyMappings: st.httpBodyMappings.map((m, mi) => mi !== idx ? m : { ...m, processField: e.target.value })
            })
        });
    }

    addHttpResponseMapping(e) {
        const si = parseInt(e.currentTarget.dataset.stageIdx, 10);
        const pi = parseInt(e.currentTarget.dataset.stepIdx, 10);
        this.stages = this.stages.map((s, i) => i !== si ? s : {
            ...s, steps: s.steps.map((st, j) => j !== pi ? st : {
                ...st, httpResponseMappings: [...st.httpResponseMappings, { id: Date.now(), jsonPath: '', fieldValuesKey: '' }]
            })
        });
    }

    removeHttpResponseMapping(e) {
        const si  = parseInt(e.currentTarget.dataset.stageIdx, 10);
        const pi  = parseInt(e.currentTarget.dataset.stepIdx, 10);
        const idx = parseInt(e.currentTarget.dataset.idx, 10);
        this.stages = this.stages.map((s, i) => i !== si ? s : {
            ...s, steps: s.steps.map((st, j) => j !== pi ? st : {
                ...st, httpResponseMappings: st.httpResponseMappings.filter((_, ri) => ri !== idx)
            })
        });
    }

    handleHttpResponseMappingPath(e) {
        const si  = parseInt(e.currentTarget.dataset.stageIdx, 10);
        const pi  = parseInt(e.currentTarget.dataset.stepIdx, 10);
        const idx = parseInt(e.currentTarget.dataset.idx, 10);
        this.stages = this.stages.map((s, i) => i !== si ? s : {
            ...s, steps: s.steps.map((st, j) => j !== pi ? st : {
                ...st, httpResponseMappings: st.httpResponseMappings.map((m, ri) => ri !== idx ? m : { ...m, jsonPath: e.target.value })
            })
        });
    }

    handleHttpResponseMappingKey(e) {
        const si  = parseInt(e.currentTarget.dataset.stageIdx, 10);
        const pi  = parseInt(e.currentTarget.dataset.stepIdx, 10);
        const idx = parseInt(e.currentTarget.dataset.idx, 10);
        this.stages = this.stages.map((s, i) => i !== si ? s : {
            ...s, steps: s.steps.map((st, j) => j !== pi ? st : {
                ...st, httpResponseMappings: st.httpResponseMappings.map((m, ri) => ri !== idx ? m : { ...m, fieldValuesKey: e.target.value })
            })
        });
    }

    goNext() {
        if (this.currentScreen === 2) {
            // Validate stages have at least one step
            const emptyStage = this.stages.find(s => !s.steps || s.steps.length === 0);
            if (emptyStage) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Validation Error',
                    message: `Stage "${emptyStage.name || 'unnamed'}" must have at least one step.`,
                    variant: 'error'
                }));
                return;
            }
        }
        if (this.currentScreen === 3) {
            // Validate HTTP Request steps have Named Credential
            for (const stage of this.stages) {
                for (const step of stage.steps) {
                    if (step.type === 'HTTP Request' && !step.httpNamedCredential) {
                        this.dispatchEvent(new ShowToastEvent({
                            title: 'Validation Error',
                            message: `HTTP Request step "${step.name || 'unnamed'}" in stage "${stage.name}" requires a Named Credential.`,
                            variant: 'error'
                        }));
                        return;
                    }
                }
            }
        }
        if (this.currentScreen < 4) this.currentScreen++;
    }
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
                    conditionLogic: s.conditionLogic || 'AND',
                    conditionsConfig: s.conditions && s.conditions.length > 0
                        ? JSON.stringify(s.conditions.map(c => ({
                            source:   c.source,
                            field:    c.field   || '',
                            stepName: c.stepName || '',
                            operator: c.operator,
                            value:    c.value   || ''
                          })))
                        : null,
                    steps: s.steps.map(st => ({
                        name: st.name,
                        sequence: st.sequence,
                        type: st.type,
                        targetObject: st.targetObject || null,
                        fieldsConfig: st.type === 'Notification'
                            ? JSON.stringify({ messageTemplate: st.messageTemplate })
                            : st.type === 'HTTP Request'
                                ? JSON.stringify({
                                    namedCredential:  st.httpNamedCredential,
                                    method:           st.httpMethod || 'POST',
                                    path:             st.httpPath   || '/',
                                    headers:          st.httpHeaders.map(h => ({ key: h.key, value: h.value })),
                                    bodyMappings:     st.httpBodyMappings.map(m => ({ jsonKey: m.jsonKey, processField: m.processField })),
                                    responseMappings: st.httpResponseMappings.map(m => ({ jsonPath: m.jsonPath, fieldValuesKey: m.fieldValuesKey })),
                                    timeout:          st.httpTimeout  || 30,
                                    retry:            st.httpRetry    || false,
                                    onFailure:        st.httpOnFailure || 'stop'
                                })
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
