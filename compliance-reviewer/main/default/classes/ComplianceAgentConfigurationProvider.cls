/**
 * @description Provides the runtime Compliance Agent configuration.
 *              The default implementation reads Custom Metadata and Field Sets.
 *              Tests can replace the singleton with an in-memory stub.
 */
public virtual inherited sharing class ComplianceAgentConfigurationProvider {

    @TestVisible
    private static ComplianceAgentConfigurationProvider instance =
        new ComplianceAgentConfigurationProvider();

    public static ComplianceAgentConfigurationProvider getInstance() {
        return instance;
    }

    @TestVisible
    private static void resetInstance() {
        instance = new ComplianceAgentConfigurationProvider();
    }

    public class SettingConfig {
        public Id metadataRecordId;
        public String developerName;
        public String masterLabel;
        public String sourceObjectApiName;
        public String sourceRelationshipFieldApiName;
        public String targetObjectApiName;
        public String targetRelationshipFieldApiName;
    }

    public class ContextConfig {
        public String developerName;
        public String contextObjectApiName;
        public String fieldSetApiName;
        public String relationshipFieldApiName;
        public String filterCriteria;
        public String parentContextObjectApiName;
        public List<String> fieldNames;
    }

    public virtual List<SettingConfig> getActiveSettings(String sourceObjectApiName) {
        List<Compliance_Agent_Setting__mdt> records = [
            SELECT Id, DeveloperName, MasterLabel,
                   Source_Object__r.QualifiedApiName,
                   Source_Relationship_Field__r.QualifiedApiName,
                   Target_Object__r.QualifiedApiName,
                   Target_Relationship_Field__r.QualifiedApiName
            FROM Compliance_Agent_Setting__mdt
            WHERE Source_Object__r.QualifiedApiName = :sourceObjectApiName
            AND Active__c = true
            WITH USER_MODE
        ];

        List<SettingConfig> configs = new List<SettingConfig>();
        for (Compliance_Agent_Setting__mdt record : records) {
            SettingConfig config = new SettingConfig();
            config.metadataRecordId = record.Id;
            config.developerName = record.DeveloperName;
            config.masterLabel = record.MasterLabel;
            config.sourceObjectApiName = record.Source_Object__r.QualifiedApiName;
            config.sourceRelationshipFieldApiName = record.Source_Relationship_Field__r == null
                ? null
                : record.Source_Relationship_Field__r.QualifiedApiName;
            config.targetObjectApiName = record.Target_Object__r.QualifiedApiName;
            config.targetRelationshipFieldApiName = record.Target_Relationship_Field__r == null
                ? null
                : record.Target_Relationship_Field__r.QualifiedApiName;
            configs.add(config);
        }
        return configs;
    }

    public virtual List<ContextConfig> getContexts(Id settingMetadataRecordId) {
        List<Compliance_Agent_Context__mdt> records = [
            SELECT DeveloperName,
                   Context_Object__r.QualifiedApiName,
                   Field_Set__c,
                   Relationship_Field__c,
                   Filter_Criteria__c,
                   Parent_Context_Object__r.QualifiedApiName
            FROM Compliance_Agent_Context__mdt
            WHERE Compliance_Agent_Setting__c = :settingMetadataRecordId
            WITH USER_MODE
        ];

        List<ContextConfig> configs = new List<ContextConfig>();
        for (Compliance_Agent_Context__mdt record : records) {
            if (record.Context_Object__r == null) {
                throw new ComplianceAgentException(
                    'Context "' + record.DeveloperName + '" has no Context Object configured.'
                );
            }
            if (String.isBlank(record.Field_Set__c)) {
                throw new ComplianceAgentException(
                    'Context "' + record.DeveloperName + '" has no Field Set configured.'
                );
            }

            ContextConfig config = new ContextConfig();
            config.developerName = record.DeveloperName;
            config.contextObjectApiName = record.Context_Object__r.QualifiedApiName;
            config.fieldSetApiName = record.Field_Set__c;
            config.relationshipFieldApiName = record.Relationship_Field__c;
            config.filterCriteria = record.Filter_Criteria__c;
            config.parentContextObjectApiName = record.Parent_Context_Object__r == null
                ? null
                : record.Parent_Context_Object__r.QualifiedApiName;
            config.fieldNames = getFieldSetMembers(
                config.contextObjectApiName,
                config.fieldSetApiName
            );
            configs.add(config);
        }
        return configs;
    }

    @TestVisible
    private static List<String> getFieldSetMembers(
        String objectApiName,
        String fieldSetApiName
    ) {
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null) {
            throw new ComplianceAgentException(
                'The context object "' + objectApiName + '" does not exist or is not accessible.'
            );
        }

        Schema.FieldSet fieldSet = objectType.getDescribe().fieldSets.getMap().get(fieldSetApiName);
        if (fieldSet == null) {
            throw new ComplianceAgentException(
                'Field Set "' + fieldSetApiName + '" was not found on object "' +
                objectApiName + '".'
            );
        }

        Set<String> fieldNameSet = new Set<String>{ 'Id' };
        for (Schema.FieldSetMember member : fieldSet.getFields()) {
            if (member.getSObjectField().getDescribe().isAccessible()) {
                fieldNameSet.add(member.getFieldPath());
            }
        }
        return new List<String>(fieldNameSet);
    }
}