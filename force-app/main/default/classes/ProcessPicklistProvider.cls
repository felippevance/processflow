global class ProcessPicklistProvider extends VisualEditor.DynamicPickList {

    global override VisualEditor.DataRow getDefaultValue() {
        return new VisualEditor.DataRow('-- All Active Processes --', '');
    }

    global override VisualEditor.DynamicPickListRows getValues() {
        VisualEditor.DynamicPickListRows rows = new VisualEditor.DynamicPickListRows();
        rows.addRow(new VisualEditor.DataRow('-- All Active Processes --', ''));
        for (Process__c p : [
            SELECT Id, Name
            FROM Process__c
            WHERE IsActive__c = true AND IsCurrentVersion__c = true
            ORDER BY Name
            LIMIT 100
        ]) {
            rows.addRow(new VisualEditor.DataRow(p.Name, p.Id));
        }
        return rows;
    }
}
