/**
 * @description       : Builds the complete evidence packet: required file reference
 *                      and context blocks, resolving nested Context chains via Parent Context Object.
**/
public inherited sharing class ComplianceAgentEvidenceBuilder {

    public class EvidencePacket {
        public String settingDeveloperName;
        public TargetInfo target;
        public List<ContextBlock> context;
    }

    public class TargetInfo {
        public String objectApiName;
        public String recordId;
        public FileReference fileReference;
    }

    public class FileReference {
        public String contentDocumentId;
        public String contentVersionId;
        public String title;
    }

    public class ContextBlock {
        public String objectApiName;
        public String fieldSetApiName;
        public List<Map<String, Object>> records;
    }

    public static EvidencePacket buildPacket(
        Id recordId,
        String objectApiName,
        String selectedContentVersionId
    ) {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            ComplianceAgentResolver.getActiveSetting(objectApiName);

        Id targetRecordId =
            ComplianceAgentResolver.resolveTargetRecordId(setting, recordId);

        EvidencePacket packet = new EvidencePacket();
        packet.settingDeveloperName = setting.developerName;

        packet.target = new TargetInfo();
        packet.target.objectApiName = setting.targetObjectApiName;
        packet.target.recordId = targetRecordId;
        packet.target.fileReference = resolveFileReference(targetRecordId, selectedContentVersionId);
        packet.context = buildContextBlocks(setting, recordId, targetRecordId);

        return packet;
    }

    private static FileReference resolveFileReference(Id targetRecordId, String selectedContentVersionId) {
        if (String.isBlank(selectedContentVersionId)) {
            throw new ComplianceAgentException('You must select a file to analyze.');
        }

        List<ContentVersion> versions = [
            SELECT Id, Title, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :selectedContentVersionId
            WITH USER_MODE
            LIMIT 1
        ];
        if (versions.isEmpty()) {
            throw new ComplianceAgentException('The selected file does not exist or is not accessible.');
        }
        ContentVersion version = versions[0];

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :version.ContentDocumentId AND LinkedEntityId = :targetRecordId
            WITH USER_MODE
            LIMIT 1
        ];
        if (links.isEmpty()) {
            throw new ComplianceAgentException('The selected file is not linked to the expected record.');
        }

        FileReference ref = new FileReference();
        ref.contentDocumentId = version.ContentDocumentId;
        ref.contentVersionId = version.Id;
        ref.title = version.Title;
        return ref;
    }

    private static List<ContextBlock> buildContextBlocks(
        ComplianceAgentConfigurationProvider.SettingConfig setting,
        Id sourceRecordId,
        Id targetRecordId
    ) {
        List<ComplianceAgentConfigurationProvider.ContextConfig> contexts =
            ComplianceAgentConfigurationProvider.getInstance()
                .getContexts(setting.metadataRecordId);

        if (contexts.isEmpty()) {
            throw new ComplianceAgentException(
                'No Compliance Agent Context records are configured for Setting "' +
                setting.developerName + '".'
            );
        }

        Map<String, ComplianceAgentConfigurationProvider.ContextConfig> contextsByObject =
            new Map<String, ComplianceAgentConfigurationProvider.ContextConfig>();
        for (ComplianceAgentConfigurationProvider.ContextConfig context : contexts) {
            String key = context.contextObjectApiName;
            if (contextsByObject.containsKey(key)) {
                throw new ComplianceAgentException(
                    'Ambiguous configuration: more than one Compliance Agent Context is configured for object "' +
                    key + '" under this Setting.'
                );
            }
            contextsByObject.put(key, context);
        }

        Map<String, List<Id>> anchorCache = new Map<String, List<Id>>();
        Set<String> resolving = new Set<String>();

        List<ContextBlock> blocks = new List<ContextBlock>();
        for (ComplianceAgentConfigurationProvider.ContextConfig context : contexts) {
            blocks.add(buildSingleContextBlock(
                context,
                setting,
                sourceRecordId,
                targetRecordId,
                contextsByObject,
                anchorCache,
                resolving
            ));
        }
        return blocks;
    }

    private static ContextBlock buildSingleContextBlock(
        ComplianceAgentConfigurationProvider.ContextConfig context,
        ComplianceAgentConfigurationProvider.SettingConfig setting,
        Id sourceRecordId,
        Id targetRecordId,
        Map<String, ComplianceAgentConfigurationProvider.ContextConfig> contextsByObject,
        Map<String, List<Id>> anchorCache,
        Set<String> resolving
    ) {
        String contextObj = context.contextObjectApiName;
        String relationshipField = ComplianceAgentResolver.resolveQueryableFieldApiName(
            contextObj,
            context.relationshipFieldApiName
        );

        List<Id> anchorIds = resolveParentAnchorIds(
            contextObj, relationshipField, context.parentContextObjectApiName,
            setting, sourceRecordId, targetRecordId, contextsByObject, anchorCache, resolving
        );

        List<String> fieldNames = context.fieldNames;
        if (fieldNames == null || fieldNames.isEmpty()) {
            throw new ComplianceAgentException(
                'Context "' + context.developerName + '" has no queryable fields.'
            );
        }

        Id selfAnchorId = resolveSelfAnchorId(contextObj, setting, sourceRecordId, targetRecordId);

        String whereClause = (selfAnchorId != null)
            ? 'Id = :selfAnchorId'
            : relationshipField + ' IN :anchorIds';

        if (String.isNotBlank(context.filterCriteria)) {
            whereClause += ' AND (' + context.filterCriteria + ')';
        }

        String query = 'SELECT ' + String.join(fieldNames, ', ') +
            ' FROM ' + contextObj +
            ' WHERE ' + whereClause +
            ' LIMIT 200';

        List<SObject> records;
        try {
            records = Database.query(query, AccessLevel.USER_MODE);
        } catch (System.QueryException e) {
            throw new ComplianceAgentException(
                'Error querying Context "' + contextObj + '" — check its Field Set fields and Filter Criteria: ' + e.getMessage()
            );
        }

        records = (List<SObject>) Security.stripInaccessible(AccessType.READABLE, records).getRecords();

        if (!anchorCache.containsKey(contextObj)) {
            List<Id> ownIds = new List<Id>();
            for (SObject record : records) {
                ownIds.add(record.Id);
            }
            anchorCache.put(contextObj, ownIds);
        }

        ContextBlock block = new ContextBlock();
        block.objectApiName = contextObj;
        block.fieldSetApiName = context.fieldSetApiName;
        block.records = new List<Map<String, Object>>();
        for (SObject record : records) {
            block.records.add(record.getPopulatedFieldsAsMap());
        }
        return block;
    }


    private static Id resolveSelfAnchorId(
        String objApiName,
        ComplianceAgentConfigurationProvider.SettingConfig setting,
        Id sourceRecordId,
        Id targetRecordId
    ) {
        if (objApiName == setting.targetObjectApiName) {
            return targetRecordId;
        }
        if (objApiName == setting.sourceObjectApiName) {
            return sourceRecordId;
        }
        return null;
    }

    private static List<Id> resolveParentAnchorIds(
        String childObjApiName,
        String childRelationshipField,
        String parentContextObject,
        ComplianceAgentConfigurationProvider.SettingConfig setting,
        Id sourceRecordId,
        Id targetRecordId,
        Map<String, ComplianceAgentConfigurationProvider.ContextConfig> contextsByObject,
        Map<String, List<Id>> anchorCache,
        Set<String> resolving
    ) {
        if (String.isBlank(parentContextObject)) {
            Id selfAnchorId = resolveSelfAnchorId(childObjApiName, setting, sourceRecordId, targetRecordId);
            if (selfAnchorId != null) {
                return new List<Id>{ selfAnchorId };
            }

            if (String.isBlank(childRelationshipField)) {
                throw new ComplianceAgentException(
                    'Context "' + childObjApiName + '" no tiene Relationship_Field__c configurado y no coincide ' +
                    'con el Source ni el Target Object del Setting.'
                );
            }

            if (fieldReferencesObject(childObjApiName, childRelationshipField, setting.targetObjectApiName)) {
                return new List<Id>{ targetRecordId };
            }
            if (fieldReferencesObject(childObjApiName, childRelationshipField, setting.sourceObjectApiName)) {
                return new List<Id>{ sourceRecordId };
            }
            throw new ComplianceAgentException(
                'The relationship field "' + childRelationshipField + '" on "' + childObjApiName +
                '" does not point to either the configured Source or Target object.'
            );
        }

        return resolveContextRecordIds(parentContextObject, setting, sourceRecordId, targetRecordId, contextsByObject, anchorCache, resolving);
    }

    private static List<Id> resolveContextRecordIds(
        String contextObjectApiName,
        ComplianceAgentConfigurationProvider.SettingConfig setting,
        Id sourceRecordId,
        Id targetRecordId,
        Map<String, ComplianceAgentConfigurationProvider.ContextConfig> contextsByObject,
        Map<String, List<Id>> anchorCache,
        Set<String> resolving
    ) {
        if (anchorCache.containsKey(contextObjectApiName)) {
            return anchorCache.get(contextObjectApiName);
        }

        Id selfAnchorId = resolveSelfAnchorId(contextObjectApiName, setting, sourceRecordId, targetRecordId);
        if (selfAnchorId != null) {
            List<Id> ids = new List<Id>{ selfAnchorId };
            anchorCache.put(contextObjectApiName, ids);
            return ids;
        }

        if (resolving.contains(contextObjectApiName)) {
            throw new ComplianceAgentException(
                'Circular Parent Context Object reference detected involving "' + contextObjectApiName + '".'
            );
        }
        resolving.add(contextObjectApiName);

        ComplianceAgentConfigurationProvider.ContextConfig context =
            contextsByObject.get(contextObjectApiName);
        if (context == null) {
            throw new ComplianceAgentException(
                'No Compliance Agent Context is configured for object "' + contextObjectApiName +
                '", but it is referenced as a Parent Context Object.'
            );
        }

        String fieldApiName = ComplianceAgentResolver.resolveQueryableFieldApiName(
            contextObjectApiName,
            context.relationshipFieldApiName
        );
        List<Id> parentAnchorIds = resolveParentAnchorIds(
            contextObjectApiName, fieldApiName, context.parentContextObjectApiName,
            setting, sourceRecordId, targetRecordId, contextsByObject, anchorCache, resolving
        );

        String query = 'SELECT Id FROM ' + contextObjectApiName + ' WHERE ' + fieldApiName + ' IN :parentAnchorIds';
        List<SObject> records = Database.query(query, AccessLevel.USER_MODE);
        List<Id> ids = new List<Id>();
        for (SObject record : records) {
            ids.add(record.Id);
        }

        anchorCache.put(contextObjectApiName, ids);
        resolving.remove(contextObjectApiName);
        return ids;
    }

    private static Boolean fieldReferencesObject(String objApiName, String fieldApiName, String targetObjApiName) {
        if (String.isBlank(fieldApiName)) {
            return false;
        }
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objApiName);
        Schema.SObjectField fieldToken = objType.getDescribe().fields.getMap().get(fieldApiName.toLowerCase());
        if (fieldToken == null) {
            return false;
        }
        for (Schema.SObjectType refType : fieldToken.getDescribe().getReferenceTo()) {
            if (refType.getDescribe().getName() == targetObjApiName) {
                return true;
            }
        }
        return false;
    }

}