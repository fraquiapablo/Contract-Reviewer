/**
 * @description       : Unit tests for evidence packet, file, Context, and Parent Context resolution.
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 08-21-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@IsTest
private class ComplianceAgentEvidenceBuilderTest {

    private static final String USER_PDF_TITLE = 'Evidence User Contract';
    private static final String FIXTURE_PDF_TITLE = 'Evidence Fixture Contract';

    @TestSetup
    static void setupData() {
        CGContrReviewer__Compliance_Test_Record__c fixture = new CGContrReviewer__Compliance_Test_Record__c();
        insert fixture;

        insert new List<ContentVersion>{
            createFile(USER_PDF_TITLE, 'evidence-user-contract.pdf', UserInfo.getUserId()),
            createFile(FIXTURE_PDF_TITLE, 'evidence-fixture-contract.pdf', fixture.Id)
        };
    }

    @IsTest
    static void buildPacketCreatesTargetFileAndSelfContext() {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting('User_Self_Evidence', 'User', 'User', null, null);
        ComplianceAgentConfigurationProvider.ContextConfig userContext = createContext(
            'User_Context',
            'User',
            'Evidence_User_Fields',
            null,
            null,
            null,
            new List<String>{ 'Id', 'Name', 'Username' }
        );
        useConfiguration(setting, new List<ComplianceAgentConfigurationProvider.ContextConfig>{
            userContext
        });
        ContentVersion selectedFile = getFile(USER_PDF_TITLE);

        Test.startTest();
        ComplianceAgentEvidenceBuilder.EvidencePacket packet =
            ComplianceAgentEvidenceBuilder.buildPacket(
                UserInfo.getUserId(),
                'User',
                String.valueOf(selectedFile.Id)
            );
        Test.stopTest();

        Assert.areEqual('User_Self_Evidence', packet.settingDeveloperName);
        Assert.areEqual('User', packet.target.objectApiName);
        Assert.areEqual(String.valueOf(UserInfo.getUserId()), packet.target.recordId);
        Assert.areEqual(String.valueOf(selectedFile.Id), packet.target.fileReference.contentVersionId);
        Assert.areEqual(
            String.valueOf(selectedFile.ContentDocumentId),
            packet.target.fileReference.contentDocumentId
        );
        Assert.areEqual(USER_PDF_TITLE, packet.target.fileReference.title);
        Assert.areEqual(1, packet.context.size());
        Assert.areEqual('User', packet.context[0].objectApiName);
        Assert.areEqual('Evidence_User_Fields', packet.context[0].fieldSetApiName);
        Assert.areEqual(1, packet.context[0].records.size());
        Assert.areEqual(UserInfo.getUserId(), packet.context[0].records[0].get('Id'));
    }

    @IsTest
    static void buildPacketQueriesContextRelatedToTarget() {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting('User_With_Fixture_Context', 'User', 'User', null, null);
        ComplianceAgentConfigurationProvider.ContextConfig fixtureContext = createContext(
            'Fixture_Context',
            'CGContrReviewer__Compliance_Test_Record__c',
            'Evidence_Fixture_Fields',
            'OwnerId',
            'Name != null',
            null,
            new List<String>{ 'Id', 'Name', 'OwnerId' }
        );
        useConfiguration(setting, new List<ComplianceAgentConfigurationProvider.ContextConfig>{
            fixtureContext
        });
        ContentVersion selectedFile = getFile(USER_PDF_TITLE);
        CGContrReviewer__Compliance_Test_Record__c fixture = getFixture();

        Test.startTest();
        ComplianceAgentEvidenceBuilder.EvidencePacket packet =
            ComplianceAgentEvidenceBuilder.buildPacket(
                UserInfo.getUserId(),
                'User',
                String.valueOf(selectedFile.Id)
            );
        Test.stopTest();

        Assert.areEqual(1, packet.context.size());
        Assert.areEqual('CGContrReviewer__Compliance_Test_Record__c', packet.context[0].objectApiName);
        Assert.areEqual(1, packet.context[0].records.size());
        Assert.areEqual(fixture.Id, packet.context[0].records[0].get('Id'));
        Assert.areEqual(UserInfo.getUserId(), packet.context[0].records[0].get('OwnerId'));
    }

    @IsTest
    static void buildPacketSupportsDistinctSourceAndTargetContexts() {
        ComplianceAgentConfigurationProvider.SettingConfig setting = createSetting(
            'User_To_Fixture_Evidence',
            'User',
            'CGContrReviewer__Compliance_Test_Record__c',
            null,
            'OwnerId'
        );
        ComplianceAgentConfigurationProvider.ContextConfig sourceContext = createContext(
            'User_Source_Context',
            'User',
            'Evidence_User_Fields',
            null,
            null,
            null,
            new List<String>{ 'Id', 'Name', 'Username' }
        );
        ComplianceAgentConfigurationProvider.ContextConfig sourceRelatedContext = createContext(
            'Content_Version_Source_Context',
            'ContentVersion',
            'Evidence_Content_Version_Fields',
            'CreatedById',
            null,
            null,
            new List<String>{ 'Id', 'Title', 'CreatedById' }
        );
        useConfiguration(setting, new List<ComplianceAgentConfigurationProvider.ContextConfig>{
            sourceContext,
            sourceRelatedContext
        });
        CGContrReviewer__Compliance_Test_Record__c fixture = getFixture();
        ContentVersion fixtureFile = getFile(FIXTURE_PDF_TITLE);

        Test.startTest();
        ComplianceAgentEvidenceBuilder.EvidencePacket packet =
            ComplianceAgentEvidenceBuilder.buildPacket(
                UserInfo.getUserId(),
                'User',
                String.valueOf(fixtureFile.Id)
            );
        Test.stopTest();

        Assert.areEqual('CGContrReviewer__Compliance_Test_Record__c', packet.target.objectApiName);
        Assert.areEqual(String.valueOf(fixture.Id), packet.target.recordId);

        ComplianceAgentEvidenceBuilder.ContextBlock userBlock =
            findBlock(packet.context, 'User');
        ComplianceAgentEvidenceBuilder.ContextBlock versionBlock =
            findBlock(packet.context, 'ContentVersion');

        Assert.isNotNull(userBlock);
        Assert.isNotNull(versionBlock);
        Assert.areEqual(1, userBlock.records.size());
        Assert.areEqual(UserInfo.getUserId(), userBlock.records[0].get('Id'));
        Assert.isTrue(
            containsRecordValue(versionBlock.records, 'Id', fixtureFile.Id),
            'Context anchored to Source should include files created by the source User.'
        );
    }

    @IsTest
    static void buildPacketResolvesNestedContextBeforeParentBlock() {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting('User_Nested_Context', 'User', 'User', null, null);

        ComplianceAgentConfigurationProvider.ContextConfig linkContext = createContext(
            'File_Link_Context',
            'ContentDocumentLink',
            'Evidence_Link_Fields',
            'LinkedEntityId',
            null,
            'CGContrReviewer__Compliance_Test_Record__c',
            new List<String>{ 'Id', 'ContentDocumentId', 'LinkedEntityId' }
        );
        ComplianceAgentConfigurationProvider.ContextConfig fixtureContext = createContext(
            'Fixture_Parent_Context',
            'CGContrReviewer__Compliance_Test_Record__c',
            'Evidence_Fixture_Fields',
            'OwnerId',
            null,
            null,
            new List<String>{ 'Id', 'Name', 'OwnerId' }
        );

        // Child first: forces recursive resolution of the parent Context.
        useConfiguration(setting, new List<ComplianceAgentConfigurationProvider.ContextConfig>{
            linkContext,
            fixtureContext
        });
        ContentVersion selectedFile = getFile(USER_PDF_TITLE);
        ContentVersion fixtureFile = getFile(FIXTURE_PDF_TITLE);
        CGContrReviewer__Compliance_Test_Record__c fixture = getFixture();

        Test.startTest();
        ComplianceAgentEvidenceBuilder.EvidencePacket packet =
            ComplianceAgentEvidenceBuilder.buildPacket(
                UserInfo.getUserId(),
                'User',
                String.valueOf(selectedFile.Id)
            );
        Test.stopTest();

        Assert.areEqual(2, packet.context.size());

        ComplianceAgentEvidenceBuilder.ContextBlock linkBlock =
            findBlock(packet.context, 'ContentDocumentLink');
        ComplianceAgentEvidenceBuilder.ContextBlock fixtureBlock =
            findBlock(packet.context, 'CGContrReviewer__Compliance_Test_Record__c');

        Assert.isNotNull(linkBlock);
        Assert.isNotNull(fixtureBlock);
        Assert.areEqual(1, fixtureBlock.records.size());
        Assert.areEqual(fixture.Id, fixtureBlock.records[0].get('Id'));
        Assert.isTrue(
            containsRecordValue(
                linkBlock.records,
                'ContentDocumentId',
                fixtureFile.ContentDocumentId
            ),
            'Nested link Context should include the file linked to the fixture.'
        );
    }

    @IsTest
    static void buildPacketReusesParentContextResolvedEarlier() {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting('User_Cached_Parent_Context', 'User', 'User', null, null);

        ComplianceAgentConfigurationProvider.ContextConfig fixtureContext = createContext(
            'Fixture_Cached_Parent_Context',
            'CGContrReviewer__Compliance_Test_Record__c',
            'Evidence_Fixture_Fields',
            'OwnerId',
            null,
            null,
            new List<String>{ 'Id', 'Name', 'OwnerId' }
        );
        ComplianceAgentConfigurationProvider.ContextConfig linkContext = createContext(
            'Link_Using_Cached_Parent_Context',
            'ContentDocumentLink',
            'Evidence_Link_Fields',
            'LinkedEntityId',
            null,
            'CGContrReviewer__Compliance_Test_Record__c',
            new List<String>{ 'Id', 'ContentDocumentId', 'LinkedEntityId' }
        );

        // Parent first: its record Ids are cached before the Child Context is built.
        useConfiguration(setting, new List<ComplianceAgentConfigurationProvider.ContextConfig>{
            fixtureContext,
            linkContext
        });
        ContentVersion selectedFile = getFile(USER_PDF_TITLE);
        ContentVersion fixtureFile = getFile(FIXTURE_PDF_TITLE);
        CGContrReviewer__Compliance_Test_Record__c fixture = getFixture();

        Test.startTest();
        ComplianceAgentEvidenceBuilder.EvidencePacket packet =
            ComplianceAgentEvidenceBuilder.buildPacket(
                UserInfo.getUserId(),
                'User',
                String.valueOf(selectedFile.Id)
            );
        Test.stopTest();

        ComplianceAgentEvidenceBuilder.ContextBlock fixtureBlock =
            findBlock(packet.context, 'CGContrReviewer__Compliance_Test_Record__c');
        ComplianceAgentEvidenceBuilder.ContextBlock linkBlock =
            findBlock(packet.context, 'ContentDocumentLink');

        Assert.isNotNull(fixtureBlock);
        Assert.isNotNull(linkBlock);
        Assert.areEqual(1, fixtureBlock.records.size());
        Assert.areEqual(fixture.Id, fixtureBlock.records[0].get('Id'));
        Assert.isTrue(
            containsRecordValue(
                linkBlock.records,
                'ContentDocumentId',
                fixtureFile.ContentDocumentId
            ),
            'The Child Context should reuse the Parent Context Ids cached earlier.'
        );
    }

    @IsTest
    static void buildPacketSupportsSourceObjectAsExplicitParentContext() {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting('User_Explicit_Source_Parent', 'User', 'User', null, null);

        ComplianceAgentConfigurationProvider.ContextConfig fixtureContext = createContext(
            'Fixture_With_User_Parent_Context',
            'CGContrReviewer__Compliance_Test_Record__c',
            'Evidence_Fixture_Fields',
            'OwnerId',
            null,
            'User',
            new List<String>{ 'Id', 'Name', 'OwnerId' }
        );
        ComplianceAgentConfigurationProvider.ContextConfig userContext = createContext(
            'User_Explicit_Parent_Context',
            'User',
            'Evidence_User_Fields',
            null,
            null,
            null,
            new List<String>{ 'Id', 'Name', 'Username' }
        );

        // Child first: resolving its Parent should use the Setting Source self-anchor.
        useConfiguration(setting, new List<ComplianceAgentConfigurationProvider.ContextConfig>{
            fixtureContext,
            userContext
        });
        ContentVersion selectedFile = getFile(USER_PDF_TITLE);
        CGContrReviewer__Compliance_Test_Record__c fixture = getFixture();

        Test.startTest();
        ComplianceAgentEvidenceBuilder.EvidencePacket packet =
            ComplianceAgentEvidenceBuilder.buildPacket(
                UserInfo.getUserId(),
                'User',
                String.valueOf(selectedFile.Id)
            );
        Test.stopTest();

        ComplianceAgentEvidenceBuilder.ContextBlock fixtureBlock =
            findBlock(packet.context, 'CGContrReviewer__Compliance_Test_Record__c');
        ComplianceAgentEvidenceBuilder.ContextBlock userBlock =
            findBlock(packet.context, 'User');

        Assert.isNotNull(fixtureBlock);
        Assert.isNotNull(userBlock);
        Assert.areEqual(1, fixtureBlock.records.size());
        Assert.areEqual(fixture.Id, fixtureBlock.records[0].get('Id'));
        Assert.areEqual(UserInfo.getUserId(), fixtureBlock.records[0].get('OwnerId'));
        Assert.areEqual(1, userBlock.records.size());
        Assert.areEqual(UserInfo.getUserId(), userBlock.records[0].get('Id'));
    }

    @IsTest
    static void buildPacketRejectsBlankFileSelection() {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting('User_Self_Evidence', 'User', 'User', null, null);
        useConfiguration(setting, new List<ComplianceAgentConfigurationProvider.ContextConfig>());

        Test.startTest();
        try {
            ComplianceAgentEvidenceBuilder.buildPacket(UserInfo.getUserId(), 'User', null);
            Assert.fail('Expected blank-file-selection exception.');
        } catch (ComplianceAgentException e) {
            Assert.isTrue(e.getMessage().contains('must select a file'));
        }
        Test.stopTest();
    }

    @IsTest
    static void buildPacketRejectsMissingContentVersion() {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting('User_Self_Evidence', 'User', 'User', null, null);
        useConfiguration(setting, new List<ComplianceAgentConfigurationProvider.ContextConfig>());
        Id nonexistentVersionId = createNonexistentId(
            ContentVersion.SObjectType.getDescribe().getKeyPrefix()
        );

        Test.startTest();
        try {
            ComplianceAgentEvidenceBuilder.buildPacket(
                UserInfo.getUserId(),
                'User',
                String.valueOf(nonexistentVersionId)
            );
            Assert.fail('Expected missing-file exception.');
        } catch (ComplianceAgentException e) {
            Assert.isTrue(e.getMessage().contains('does not exist or is not accessible'));
        }
        Test.stopTest();
    }

    @IsTest
    static void buildPacketRejectsFileNotLinkedToTarget() {
        CGContrReviewer__Compliance_Test_Record__c fixture = getFixture();
        ComplianceAgentConfigurationProvider.SettingConfig setting = createSetting(
            'Fixture_Self_Evidence',
            'CGContrReviewer__Compliance_Test_Record__c',
            'CGContrReviewer__Compliance_Test_Record__c',
            null,
            null
        );
        useConfiguration(setting, new List<ComplianceAgentConfigurationProvider.ContextConfig>());
        ContentVersion userFile = getFile(USER_PDF_TITLE);

        Test.startTest();
        try {
            ComplianceAgentEvidenceBuilder.buildPacket(
                fixture.Id,
                'CGContrReviewer__Compliance_Test_Record__c',
                String.valueOf(userFile.Id)
            );
            Assert.fail('Expected unlinked-file exception.');
        } catch (ComplianceAgentException e) {
            Assert.isTrue(e.getMessage().contains('not linked to the expected record'));
        }
        Test.stopTest();
    }

    @IsTest
    static void buildPacketRejectsMissingContexts() {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting('User_Without_Contexts', 'User', 'User', null, null);
        useConfiguration(setting, new List<ComplianceAgentConfigurationProvider.ContextConfig>());
        ContentVersion selectedFile = getFile(USER_PDF_TITLE);

        Test.startTest();
        try {
            ComplianceAgentEvidenceBuilder.buildPacket(
                UserInfo.getUserId(),
                'User',
                String.valueOf(selectedFile.Id)
            );
            Assert.fail('Expected missing-context exception.');
        } catch (ComplianceAgentException e) {
            Assert.isTrue(e.getMessage().contains('No Compliance Agent Context records'));
            Assert.isTrue(e.getMessage().contains('User_Without_Contexts'));
        }
        Test.stopTest();
    }

    @IsTest
    static void buildPacketRejectsDuplicateContextObjects() {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting('User_Duplicate_Contexts', 'User', 'User', null, null);
        ComplianceAgentConfigurationProvider.ContextConfig contextA = createContext(
            'User_Context_A', 'User', 'Fields_A', null, null, null,
            new List<String>{ 'Id', 'Name' }
        );
        ComplianceAgentConfigurationProvider.ContextConfig contextB = createContext(
            'User_Context_B', 'User', 'Fields_B', null, null, null,
            new List<String>{ 'Id', 'Username' }
        );
        useConfiguration(setting, new List<ComplianceAgentConfigurationProvider.ContextConfig>{
            contextA,
            contextB
        });
        ContentVersion selectedFile = getFile(USER_PDF_TITLE);

        Test.startTest();
        try {
            ComplianceAgentEvidenceBuilder.buildPacket(
                UserInfo.getUserId(),
                'User',
                String.valueOf(selectedFile.Id)
            );
            Assert.fail('Expected duplicate-context exception.');
        } catch (ComplianceAgentException e) {
            Assert.isTrue(e.getMessage().contains('Ambiguous configuration'));
            Assert.isTrue(e.getMessage().contains('User'));
        }
        Test.stopTest();
    }

    @IsTest
    static void buildPacketRejectsContextWithoutQueryableFields() {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting('User_Empty_Field_Set', 'User', 'User', null, null);
        ComplianceAgentConfigurationProvider.ContextConfig context = createContext(
            'User_Empty_Context',
            'User',
            'Empty_Field_Set',
            null,
            null,
            null,
            new List<String>()
        );
        useConfiguration(setting, new List<ComplianceAgentConfigurationProvider.ContextConfig>{
            context
        });
        ContentVersion selectedFile = getFile(USER_PDF_TITLE);

        Test.startTest();
        try {
            ComplianceAgentEvidenceBuilder.buildPacket(
                UserInfo.getUserId(),
                'User',
                String.valueOf(selectedFile.Id)
            );
            Assert.fail('Expected no-queryable-fields exception.');
        } catch (ComplianceAgentException e) {
            Assert.isTrue(e.getMessage().contains('has no queryable fields'));
            Assert.isTrue(e.getMessage().contains('User_Empty_Context'));
        }
        Test.stopTest();
    }

    @IsTest
    static void buildPacketRejectsUnanchoredContextWithoutRelationship() {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting('User_Unanchored_Context', 'User', 'User', null, null);
        ComplianceAgentConfigurationProvider.ContextConfig context = createContext(
            'Fixture_Unanchored_Context',
            'CGContrReviewer__Compliance_Test_Record__c',
            'Evidence_Fixture_Fields',
            null,
            null,
            null,
            new List<String>{ 'Id', 'Name' }
        );
        useConfiguration(setting, new List<ComplianceAgentConfigurationProvider.ContextConfig>{
            context
        });
        ContentVersion selectedFile = getFile(USER_PDF_TITLE);

        Test.startTest();
        try {
            ComplianceAgentEvidenceBuilder.buildPacket(
                UserInfo.getUserId(),
                'User',
                String.valueOf(selectedFile.Id)
            );
            Assert.fail('Expected missing-relationship exception.');
        } catch (ComplianceAgentException e) {
            Assert.isTrue(e.getMessage().contains('Relationship_Field__c'));
            Assert.isTrue(e.getMessage().contains('CGContrReviewer__Compliance_Test_Record__c'));
        }
        Test.stopTest();
    }

    @IsTest
    static void buildPacketRejectsRelationshipOutsideSourceAndTarget() {
        CGContrReviewer__Compliance_Test_Record__c fixture = getFixture();
        ComplianceAgentConfigurationProvider.SettingConfig setting = createSetting(
            'Fixture_Invalid_Context_Relationship',
            'CGContrReviewer__Compliance_Test_Record__c',
            'CGContrReviewer__Compliance_Test_Record__c',
            null,
            null
        );
        ComplianceAgentConfigurationProvider.ContextConfig context = createContext(
            'User_Profile_Context',
            'User',
            'Evidence_User_Fields',
            'ProfileId',
            null,
            null,
            new List<String>{ 'Id', 'Name', 'ProfileId' }
        );
        useConfiguration(setting, new List<ComplianceAgentConfigurationProvider.ContextConfig>{
            context
        });
        ContentVersion fixtureFile = getFile(FIXTURE_PDF_TITLE);

        Test.startTest();
        try {
            ComplianceAgentEvidenceBuilder.buildPacket(
                fixture.Id,
                'CGContrReviewer__Compliance_Test_Record__c',
                String.valueOf(fixtureFile.Id)
            );
            Assert.fail('Expected unrelated-relationship exception.');
        } catch (ComplianceAgentException e) {
            Assert.isTrue(e.getMessage().contains('does not point to either'));
            Assert.isTrue(e.getMessage().contains('ProfileId'));
        }
        Test.stopTest();
    }

    @IsTest
    static void buildPacketRejectsInvalidFilterCriteria() {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting('User_Invalid_Filter', 'User', 'User', null, null);
        ComplianceAgentConfigurationProvider.ContextConfig context = createContext(
            'User_Invalid_Filter_Context',
            'User',
            'Evidence_User_Fields',
            null,
            'Field_That_Does_Not_Exist__c = true',
            null,
            new List<String>{ 'Id', 'Name' }
        );
        useConfiguration(setting, new List<ComplianceAgentConfigurationProvider.ContextConfig>{
            context
        });
        ContentVersion selectedFile = getFile(USER_PDF_TITLE);

        Test.startTest();
        try {
            ComplianceAgentEvidenceBuilder.buildPacket(
                UserInfo.getUserId(),
                'User',
                String.valueOf(selectedFile.Id)
            );
            Assert.fail('Expected invalid-filter exception.');
        } catch (ComplianceAgentException e) {
            Assert.isTrue(e.getMessage().contains('Error querying Context'));
            Assert.isTrue(e.getMessage().contains('Filter Criteria'));
        }
        Test.stopTest();
    }

    @IsTest
    static void buildPacketRejectsMissingParentContextConfiguration() {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting('User_Missing_Parent', 'User', 'User', null, null);
        ComplianceAgentConfigurationProvider.ContextConfig childContext = createContext(
            'Link_Missing_Parent_Context',
            'ContentDocumentLink',
            'Evidence_Link_Fields',
            'LinkedEntityId',
            null,
            'CGContrReviewer__Compliance_Test_Record__c',
            new List<String>{ 'Id', 'ContentDocumentId', 'LinkedEntityId' }
        );
        useConfiguration(setting, new List<ComplianceAgentConfigurationProvider.ContextConfig>{
            childContext
        });
        ContentVersion selectedFile = getFile(USER_PDF_TITLE);

        Test.startTest();
        try {
            ComplianceAgentEvidenceBuilder.buildPacket(
                UserInfo.getUserId(),
                'User',
                String.valueOf(selectedFile.Id)
            );
            Assert.fail('Expected missing-parent-context exception.');
        } catch (ComplianceAgentException e) {
            Assert.isTrue(e.getMessage().contains('referenced as a Parent Context Object'));
            Assert.isTrue(e.getMessage().contains('CGContrReviewer__Compliance_Test_Record__c'));
        }
        Test.stopTest();
    }

    @IsTest
    static void buildPacketRejectsCircularParentContexts() {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting('User_Circular_Contexts', 'User', 'User', null, null);
        ComplianceAgentConfigurationProvider.ContextConfig fixtureContext = createContext(
            'Fixture_Circular_Context',
            'CGContrReviewer__Compliance_Test_Record__c',
            'Evidence_Fixture_Fields',
            'OwnerId',
            null,
            'ContentDocumentLink',
            new List<String>{ 'Id', 'Name', 'OwnerId' }
        );
        ComplianceAgentConfigurationProvider.ContextConfig linkContext = createContext(
            'Link_Circular_Context',
            'ContentDocumentLink',
            'Evidence_Link_Fields',
            'LinkedEntityId',
            null,
            'CGContrReviewer__Compliance_Test_Record__c',
            new List<String>{ 'Id', 'ContentDocumentId', 'LinkedEntityId' }
        );
        useConfiguration(setting, new List<ComplianceAgentConfigurationProvider.ContextConfig>{
            fixtureContext,
            linkContext
        });
        ContentVersion selectedFile = getFile(USER_PDF_TITLE);

        Test.startTest();
        try {
            ComplianceAgentEvidenceBuilder.buildPacket(
                UserInfo.getUserId(),
                'User',
                String.valueOf(selectedFile.Id)
            );
            Assert.fail('Expected circular-parent-context exception.');
        } catch (ComplianceAgentException e) {
            Assert.isTrue(e.getMessage().contains('Circular Parent Context Object'));
        }
        Test.stopTest();
    }

    private static ContentVersion createFile(
        String title,
        String pathOnClient,
        Id firstPublishLocationId
    ) {
        return new ContentVersion(
            Title = title,
            PathOnClient = pathOnClient,
            VersionData = Blob.valueOf('Evidence Builder test content: ' + title),
            FirstPublishLocationId = firstPublishLocationId
        );
    }

    private static ContentVersion getFile(String title) {
        return [
            SELECT Id, Title, ContentDocumentId
            FROM ContentVersion
            WHERE Title = :title
            LIMIT 1
        ];
    }

    private static CGContrReviewer__Compliance_Test_Record__c getFixture() {
        return [SELECT Id, Name, OwnerId FROM CGContrReviewer__Compliance_Test_Record__c LIMIT 1];
    }

    private static ComplianceAgentConfigurationProvider.SettingConfig createSetting(
        String developerName,
        String sourceObjectApiName,
        String targetObjectApiName,
        String sourceRelationshipFieldApiName,
        String targetRelationshipFieldApiName
    ) {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            new ComplianceAgentConfigurationProvider.SettingConfig();
        setting.metadataRecordId = UserInfo.getUserId();
        setting.developerName = developerName;
        setting.masterLabel = developerName.replace('_', ' ');
        setting.sourceObjectApiName = sourceObjectApiName;
        setting.targetObjectApiName = targetObjectApiName;
        setting.sourceRelationshipFieldApiName = sourceRelationshipFieldApiName;
        setting.targetRelationshipFieldApiName = targetRelationshipFieldApiName;
        return setting;
    }

    private static ComplianceAgentConfigurationProvider.ContextConfig createContext(
        String developerName,
        String contextObjectApiName,
        String fieldSetApiName,
        String relationshipFieldApiName,
        String filterCriteria,
        String parentContextObjectApiName,
        List<String> fieldNames
    ) {
        ComplianceAgentConfigurationProvider.ContextConfig context =
            new ComplianceAgentConfigurationProvider.ContextConfig();
        context.developerName = developerName;
        context.contextObjectApiName = contextObjectApiName;
        context.fieldSetApiName = fieldSetApiName;
        context.relationshipFieldApiName = relationshipFieldApiName;
        context.filterCriteria = filterCriteria;
        context.parentContextObjectApiName = parentContextObjectApiName;
        context.fieldNames = fieldNames;
        return context;
    }

    private static void useConfiguration(
        ComplianceAgentConfigurationProvider.SettingConfig setting,
        List<ComplianceAgentConfigurationProvider.ContextConfig> contexts
    ) {
        ConfigurationProviderStub stub = new ConfigurationProviderStub();
        stub.settings = new List<ComplianceAgentConfigurationProvider.SettingConfig>{ setting };
        stub.contexts = contexts;
        ComplianceAgentConfigurationProvider.instance = stub;
    }

    private static ComplianceAgentEvidenceBuilder.ContextBlock findBlock(
        List<ComplianceAgentEvidenceBuilder.ContextBlock> blocks,
        String objectApiName
    ) {
        for (ComplianceAgentEvidenceBuilder.ContextBlock block : blocks) {
            if (block.objectApiName == objectApiName) {
                return block;
            }
        }
        return null;
    }

    private static Boolean containsRecordValue(
        List<Map<String, Object>> records,
        String fieldApiName,
        Object expectedValue
    ) {
        for (Map<String, Object> record : records) {
            if (record.get(fieldApiName) == expectedValue) {
                return true;
            }
        }
        return false;
    }

    private static Id createNonexistentId(String keyPrefix) {
        return (Id) (keyPrefix + '000000000000');
    }

    private class ConfigurationProviderStub extends ComplianceAgentConfigurationProvider {
        private List<ComplianceAgentConfigurationProvider.SettingConfig> settings =
            new List<ComplianceAgentConfigurationProvider.SettingConfig>();
        private List<ComplianceAgentConfigurationProvider.ContextConfig> contexts =
            new List<ComplianceAgentConfigurationProvider.ContextConfig>();

        public override List<ComplianceAgentConfigurationProvider.SettingConfig> getActiveSettings(
            String sourceObjectApiName
        ) {
            return settings;
        }

        public override List<ComplianceAgentConfigurationProvider.ContextConfig> getContexts(
            Id settingMetadataRecordId
        ) {
            return contexts;
        }
    }
}