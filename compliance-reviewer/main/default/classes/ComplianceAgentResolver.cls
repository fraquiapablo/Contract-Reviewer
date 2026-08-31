/**
 * @description       : Configuration and schema resolution utilities:
 *                      finds the active Setting, resolves the target record Id, lists files, and translates
 *                      metadata field names into SOQL-queryable field names.
**/
public inherited sharing class ComplianceAgentResolver {

    public static ComplianceAgentController.ReviewContextResult resolve(Id recordId, String objectApiName) {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            getActiveSetting(objectApiName);
        Id targetRecordId = resolveTargetRecordId(setting, recordId);

        ComplianceAgentController.ReviewContextResult result = new ComplianceAgentController.ReviewContextResult();
        result.settingDeveloperName = setting.developerName;
        result.targetObjectApiName = setting.targetObjectApiName;
        result.targetRecordId = targetRecordId;
        result.availableFiles = listAvailableFiles(targetRecordId);

        return result;
    }


    public static ComplianceAgentConfigurationProvider.SettingConfig getActiveSetting(
        String objectApiName
    ) {
        List<ComplianceAgentConfigurationProvider.SettingConfig> settings =
            ComplianceAgentConfigurationProvider.getInstance()
                .getActiveSettings(objectApiName);

        if (settings.isEmpty()) {
            throw new ComplianceAgentException(
                'No active Compliance Agent Setting was found for object "' + objectApiName + '". Contact your administrator.'
            );
        }
        if (settings.size() > 1) {
            List<String> names = new List<String>();
            for (ComplianceAgentConfigurationProvider.SettingConfig setting : settings) {
                names.add(setting.developerName);
            }
            throw new ComplianceAgentException(
                'Ambiguous configuration: more than one active Compliance Agent Setting was found for "' + objectApiName +
                '" (' + String.join(names, ', ') + '). Contact your administrator to deactivate one.'
            );
        }
        return settings[0];
    }

    public static Id resolveTargetRecordId(
        ComplianceAgentConfigurationProvider.SettingConfig setting,
        Id sourceRecordId
    ) {
        String sourceObj = setting.sourceObjectApiName;
        String targetObj = setting.targetObjectApiName;

        Boolean noRelationshipConfigured =
            String.isBlank(setting.targetRelationshipFieldApiName)
            && String.isBlank(setting.sourceRelationshipFieldApiName);
 
        if (targetObj == sourceObj && noRelationshipConfigured) {
            return sourceRecordId;
        }

        if (String.isNotBlank(setting.targetRelationshipFieldApiName)) {
            String fieldApiName = resolveQueryableFieldApiName(
                targetObj,
                setting.targetRelationshipFieldApiName
            );
            String query = 'SELECT Id FROM ' + targetObj + ' WHERE ' + fieldApiName + ' = :sourceRecordId LIMIT 1';
            List<SObject> results = Database.query(query, AccessLevel.USER_MODE);
            if (results.isEmpty()) {
                throw new ComplianceAgentException(
                    'No related record was found in "' + targetObj + '" for this ' + sourceObj + '.'
                );
            }
            return results[0].Id;
        }

        if (String.isNotBlank(setting.sourceRelationshipFieldApiName)) {
            String fieldApiName = resolveQueryableFieldApiName(
                sourceObj,
                setting.sourceRelationshipFieldApiName
            );
            String query = 'SELECT ' + fieldApiName + ' FROM ' + sourceObj + ' WHERE Id = :sourceRecordId LIMIT 1';
            List<SObject> results = Database.query(query, AccessLevel.USER_MODE);
            if (results.isEmpty() || results[0].get(fieldApiName) == null) {
                throw new ComplianceAgentException(
                    'The source record does not have a valid reference to object "' + targetObj + '".'
                );
            }
            return (Id) results[0].get(fieldApiName);
        }

        throw new ComplianceAgentException(
            'Incomplete configuration: missing relationship field between "' + sourceObj + '" and "' + targetObj + '".'
        );
    }

    public static List<ComplianceAgentController.AvailableFile> listAvailableFiles(Id targetRecordId) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension,
                ContentDocument.ContentModifiedDate, ContentDocument.IsArchived,
                ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :targetRecordId
            AND ContentDocument.FileExtension = 'pdf'
            WITH USER_MODE
            ORDER BY ContentDocument.IsArchived ASC, ContentDocument.ContentModifiedDate DESC
            LIMIT 25
        ];

        List<ComplianceAgentController.AvailableFile> files = new List<ComplianceAgentController.AvailableFile>();
        for (ContentDocumentLink link : links) {
            ComplianceAgentController.AvailableFile f = new ComplianceAgentController.AvailableFile();
            f.contentDocumentId = link.ContentDocumentId;
            f.contentVersionId = link.ContentDocument.LatestPublishedVersionId;
            f.title = link.ContentDocument.Title;
            f.fileExtension = link.ContentDocument.FileExtension;
            f.contentModifiedDate = link.ContentDocument.ContentModifiedDate;
            f.isArchived = link.ContentDocument.IsArchived;
            files.add(f);
        }
        return files;
    }

    public static String resolveQueryableFieldApiName(String objApiName, String qualifiedFieldApiName) {
        if (String.isBlank(qualifiedFieldApiName)) {
            return null;
        }

        List<String> parts = qualifiedFieldApiName.split('\\.');
        String rawFieldName = parts[parts.size() - 1];

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objApiName);
        if (objType == null) {
            throw new ComplianceAgentException('The configured object "' + objApiName + '" does not exist or is not accessible.');
        }

        Map<String, Schema.SObjectField> fieldsMap = objType.getDescribe().fields.getMap();

        Schema.SObjectField token = fieldsMap.get(rawFieldName.toLowerCase());

        if (token == null) {
            for (Schema.SObjectField candidate : fieldsMap.values()) {
                Schema.DescribeFieldResult dfr = candidate.getDescribe();
                if (dfr.getRelationshipName() != null && dfr.getRelationshipName().equalsIgnoreCase(rawFieldName)) {
                    token = candidate;
                    break;
                }
            }
        }

        if (token == null) {
            Id maybeFieldId = null;
            try {
                maybeFieldId = (Id) rawFieldName;
            } catch (Exception e) {
                maybeFieldId = null;
            }

            if (maybeFieldId != null) {
                String durableSuffix = String.valueOf(maybeFieldId).left(15);
                String likePattern = '%.' + durableSuffix;

                try {
                    FieldDefinition fd = [
                        SELECT QualifiedApiName
                        FROM FieldDefinition
                        WHERE EntityDefinition.QualifiedApiName = :objApiName
                        AND DurableId LIKE :likePattern
                        LIMIT 1
                    ];
                    token = fieldsMap.get(fd.QualifiedApiName.toLowerCase());
                } catch (QueryException e) {
                }
            }
        }

        if (token == null) {
            throw new ComplianceAgentException('The configured field "' + rawFieldName + '" on "' + objApiName + '" does not exist or is not accessible.');
        }
        if (!token.getDescribe().isAccessible()) {
            throw new ComplianceAgentException('The configured field "' + rawFieldName + '" on "' + objApiName + '" is not accessible.');
        }

        return token.getDescribe().getName();
    }
}