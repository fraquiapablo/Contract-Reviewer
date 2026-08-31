/**
 * @description       : Unit tests for ComplianceAgentResolver and controller resolution behavior.
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 08-28-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@IsTest
private class ComplianceAgentResolverTest {

    private static final String USER_PDF_TITLE = 'Resolver User Contract';
    private static final String FIXTURE_PDF_TITLE = 'Resolver Fixture Contract';
    private static final String FIXTURE_TXT_TITLE = 'Resolver Fixture Notes';

    @TestSetup
    static void setupData() {
        CGContrReviewer__Compliance_Test_Record__c fixture = new CGContrReviewer__Compliance_Test_Record__c();
        insert fixture;

        insert new List<ContentVersion>{
            createFile(USER_PDF_TITLE, 'resolver-user-contract.pdf', UserInfo.getUserId()),
            createFile(FIXTURE_PDF_TITLE, 'resolver-fixture-contract.pdf', fixture.Id),
            createFile(FIXTURE_TXT_TITLE, 'resolver-fixture-notes.txt', fixture.Id)
        };
    }

    @IsTest
    static void getActiveSettingReturnsUniqueSetting() {
        ComplianceAgentConfigurationProvider.SettingConfig expected =
            createSetting('User_Self', 'User', 'User', null, null);
        useSettings(new List<ComplianceAgentConfigurationProvider.SettingConfig>{ expected });

        Test.startTest();
        ComplianceAgentConfigurationProvider.SettingConfig actual =
            ComplianceAgentResolver.getActiveSetting('User');
        Test.stopTest();

        Assert.areEqual(expected, actual, 'Resolver should return the unique active setting.');
    }

    @IsTest
    static void getActiveSettingRejectsMissingConfiguration() {
        useSettings(new List<ComplianceAgentConfigurationProvider.SettingConfig>());

        Test.startTest();
        try {
            ComplianceAgentResolver.getActiveSetting('User');
            Assert.fail('Expected missing-setting exception.');
        } catch (ComplianceAgentException e) {
            Assert.isTrue(
                e.getMessage().contains('No active Compliance Agent Setting'),
                'Error should explain that no active setting exists.'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void getActiveSettingRejectsAmbiguousConfiguration() {
        useSettings(new List<ComplianceAgentConfigurationProvider.SettingConfig>{
            createSetting('User_Setting_A', 'User', 'User', null, null),
            createSetting('User_Setting_B', 'User', 'User', null, null)
        });

        Test.startTest();
        try {
            ComplianceAgentResolver.getActiveSetting('User');
            Assert.fail('Expected ambiguous-setting exception.');
        } catch (ComplianceAgentException e) {
            Assert.isTrue(e.getMessage().contains('Ambiguous configuration'));
            Assert.isTrue(e.getMessage().contains('User_Setting_A'));
            Assert.isTrue(e.getMessage().contains('User_Setting_B'));
        }
        Test.stopTest();
    }

    @IsTest
    static void resolveTargetSupportsUserSelfRelationship() {
        Id currentUserId = UserInfo.getUserId();
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting('User_Self', 'User', 'User', null, null);

        Test.startTest();
        Id targetId = ComplianceAgentResolver.resolveTargetRecordId(setting, currentUserId);
        Test.stopTest();

        Assert.areEqual(currentUserId, targetId);
    }

    @IsTest
    static void resolveTargetSupportsFixtureSelfRelationship() {
        CGContrReviewer__Compliance_Test_Record__c fixture = getFixture();
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting(
                'Fixture_Self',
                'CGContrReviewer__Compliance_Test_Record__c',
                'CGContrReviewer__Compliance_Test_Record__c',
                null,
                null
            );

        Test.startTest();
        Id targetId = ComplianceAgentResolver.resolveTargetRecordId(setting, fixture.Id);
        Test.stopTest();

        Assert.areEqual(fixture.Id, targetId);
    }

    @IsTest
    static void resolveTargetSupportsRelationshipStoredOnTarget() {
        CGContrReviewer__Compliance_Test_Record__c fixture = getFixture();
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting(
                'User_To_Fixture',
                'User',
                'CGContrReviewer__Compliance_Test_Record__c',
                null,
                'OwnerId'
            );

        Test.startTest();
        Id targetId = ComplianceAgentResolver.resolveTargetRecordId(
            setting,
            UserInfo.getUserId()
        );
        Test.stopTest();

        Assert.areEqual(fixture.Id, targetId);
    }

    @IsTest
    static void resolveTargetSupportsRelationshipStoredOnSource() {
        CGContrReviewer__Compliance_Test_Record__c fixture = getFixture();
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting(
                'Fixture_To_User',
                'CGContrReviewer__Compliance_Test_Record__c',
                'User',
                'OwnerId',
                null
            );

        Test.startTest();
        Id targetId = ComplianceAgentResolver.resolveTargetRecordId(setting, fixture.Id);
        Test.stopTest();

        Assert.areEqual(UserInfo.getUserId(), targetId);
    }

    @IsTest
    static void resolveTargetRejectsMissingRelationshipConfiguration() {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting('User_To_Profile', 'User', 'Profile', null, null);

        Test.startTest();
        try {
            ComplianceAgentResolver.resolveTargetRecordId(setting, UserInfo.getUserId());
            Assert.fail('Expected incomplete-configuration exception.');
        } catch (ComplianceAgentException e) {
            Assert.isTrue(e.getMessage().contains('Incomplete configuration'));
        }
        Test.stopTest();
    }

    @IsTest
    static void resolveTargetRejectsEmptySourceRelationship() {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting('User_To_Contact', 'User', 'Contact', 'ContactId', null);

        Test.startTest();
        try {
            ComplianceAgentResolver.resolveTargetRecordId(setting, UserInfo.getUserId());
            Assert.fail('Expected empty-source-reference exception.');
        } catch (ComplianceAgentException e) {
            Assert.isTrue(
                e.getMessage().contains('does not have a valid reference'),
                'Error should explain that the source lookup is empty.'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void resolveTargetRejectsMissingTargetRecord() {
        delete [SELECT Id FROM CGContrReviewer__Compliance_Test_Record__c];

        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting(
                'User_To_Fixture',
                'User',
                'CGContrReviewer__Compliance_Test_Record__c',
                null,
                'OwnerId'
            );

        Test.startTest();
        try {
            ComplianceAgentResolver.resolveTargetRecordId(setting, UserInfo.getUserId());
            Assert.fail('Expected missing-related-record exception.');
        } catch (ComplianceAgentException e) {
            Assert.isTrue(e.getMessage().contains('No related record was found'));
        }
        Test.stopTest();
    }

    @IsTest
    static void resolveTargetRejectsMissingSourceRecord() {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting(
                'Fixture_To_User',
                'CGContrReviewer__Compliance_Test_Record__c',
                'User',
                'OwnerId',
                null
            );
        Id nonexistentFixtureId = createNonexistentId(
            CGContrReviewer__Compliance_Test_Record__c.SObjectType.getDescribe().getKeyPrefix()
        );

        Test.startTest();
        try {
            ComplianceAgentResolver.resolveTargetRecordId(setting, nonexistentFixtureId);
            Assert.fail('Expected missing-source-record exception.');
        } catch (ComplianceAgentException e) {
            Assert.isTrue(e.getMessage().contains('does not have a valid reference'));
        }
        Test.stopTest();
    }

    @IsTest
    static void listAvailableFilesReturnsOnlyPdfFiles() {
        CGContrReviewer__Compliance_Test_Record__c fixture = getFixture();

        Test.startTest();
        List<ComplianceAgentController.AvailableFile> files =
            ComplianceAgentResolver.listAvailableFiles(fixture.Id);
        Test.stopTest();

        Assert.areEqual(1, files.size(), 'TXT files must not be returned.');
        Assert.areEqual(FIXTURE_PDF_TITLE, files[0].title);
        Assert.areEqual('pdf', files[0].fileExtension.toLowerCase());
        Assert.isNotNull(files[0].contentDocumentId);
        Assert.isNotNull(files[0].contentVersionId);
        Assert.isNotNull(files[0].contentModifiedDate);
        Assert.areEqual(false, files[0].isArchived);
    }

    @IsTest
    static void listAvailableFilesReturnsEmptyListWhenNoFilesExist() {
        CGContrReviewer__Compliance_Test_Record__c fixtureWithoutFiles = new CGContrReviewer__Compliance_Test_Record__c();
        insert fixtureWithoutFiles;

        Test.startTest();
        List<ComplianceAgentController.AvailableFile> files =
            ComplianceAgentResolver.listAvailableFiles(fixtureWithoutFiles.Id);
        Test.stopTest();

        Assert.areEqual(0, files.size());
    }

    @IsTest
    static void resolveBuildsCompleteReviewContextForUser() {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting('User_Self', 'User', 'User', null, null);
        useSettings(new List<ComplianceAgentConfigurationProvider.SettingConfig>{ setting });

        Test.startTest();
        ComplianceAgentController.ReviewContextResult result =
            ComplianceAgentResolver.resolve(UserInfo.getUserId(), 'User');
        Test.stopTest();

        Assert.areEqual('User_Self', result.settingDeveloperName);
        Assert.areEqual('User', result.targetObjectApiName);
        Assert.areEqual(String.valueOf(UserInfo.getUserId()), result.targetRecordId);
        Assert.isTrue(
            containsFileWithTitle(result.availableFiles, USER_PDF_TITLE),
            'The PDF explicitly published to the user should be available.'
        );
    }

    @IsTest
    static void resolveBuildsCompleteReviewContextForFixture() {
        CGContrReviewer__Compliance_Test_Record__c fixture = getFixture();
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting(
                'Fixture_Self',
                'CGContrReviewer__Compliance_Test_Record__c',
                'CGContrReviewer__Compliance_Test_Record__c',
                null,
                null
            );
        useSettings(new List<ComplianceAgentConfigurationProvider.SettingConfig>{ setting });

        Test.startTest();
        ComplianceAgentController.ReviewContextResult result =
            ComplianceAgentResolver.resolve(fixture.Id, 'CGContrReviewer__Compliance_Test_Record__c');
        Test.stopTest();

        Assert.areEqual('Fixture_Self', result.settingDeveloperName);
        Assert.areEqual('CGContrReviewer__Compliance_Test_Record__c', result.targetObjectApiName);
        Assert.areEqual(String.valueOf(fixture.Id), result.targetRecordId);
        Assert.isTrue(
            containsFileWithTitle(result.availableFiles, FIXTURE_PDF_TITLE),
            'The PDF explicitly published to the fixture should be available.'
        );
    }

    @IsTest
    static void resolveQueryableFieldSupportsDirectAndRelationshipNames() {
        Test.startTest();
        String directField = ComplianceAgentResolver.resolveQueryableFieldApiName(
            'CGContrReviewer__Compliance_Test_Record__c',
            'OwnerId'
        );
        String qualifiedField = ComplianceAgentResolver.resolveQueryableFieldApiName(
            'CGContrReviewer__Compliance_Test_Record__c',
            'CGContrReviewer__Compliance_Test_Record__c.OwnerId'
        );
        String relationshipName = ComplianceAgentResolver.resolveQueryableFieldApiName(
            'CGContrReviewer__Compliance_Test_Record__c',
            'Owner'
        );
        String blankField = ComplianceAgentResolver.resolveQueryableFieldApiName(
            'CGContrReviewer__Compliance_Test_Record__c',
            null
        );
        Test.stopTest();

        Assert.areEqual('OwnerId', directField);
        Assert.areEqual('OwnerId', qualifiedField);
        Assert.areEqual('OwnerId', relationshipName);
        Assert.isNull(blankField);
    }

    @IsTest
    static void resolveQueryableFieldSupportsFieldDefinitionDurableId() {
        String reviewObjectApiName =
            Compliance_Review__c.SObjectType.getDescribe().getName();

        String reviewFieldApiName =
            Compliance_Review__c.Content_Document_Id__c
                .getDescribe()
                .getName();

        // FieldDefinition can expose the field with its namespace in a
        // managed 2GP build, while Apex Describe can return the local API name.
        String fieldNamePattern = '%' + reviewFieldApiName;

        List<FieldDefinition> fieldDefinitions = [
            SELECT DurableId, QualifiedApiName
            FROM FieldDefinition
            WHERE EntityDefinition.QualifiedApiName = :reviewObjectApiName
            AND QualifiedApiName LIKE :fieldNamePattern
            LIMIT 1
        ];

        Assert.areEqual(
            1,
            fieldDefinitions.size(),
            'The custom field should have a FieldDefinition entry.'
        );

        FieldDefinition fieldDefinition = fieldDefinitions[0];

        List<String> durableIdParts = fieldDefinition.DurableId.split('\\.');
        String fieldIdentifier =
            durableIdParts[durableIdParts.size() - 1];

        Test.startTest();

        String resolvedField =
            ComplianceAgentResolver.resolveQueryableFieldApiName(
                reviewObjectApiName,
                fieldIdentifier
            );

        Test.stopTest();

        Assert.areEqual(
            reviewFieldApiName,
            resolvedField,
            'The DurableId should resolve to the field API name exposed by Apex Describe.'
        );
    }

    @IsTest
    static void resolveQueryableFieldRejectsValidIdThatIsNotAFieldDefinition() {
        String validNonFieldId = String.valueOf(UserInfo.getUserId());
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            ComplianceAgentResolver.resolveQueryableFieldApiName(
                'CGContrReviewer__Compliance_Test_Record__c',
                validNonFieldId
            );
            Assert.fail('Expected an exception for an Id that is not a FieldDefinition.');
        } catch (ComplianceAgentException e) {
            exceptionThrown = true;
            Assert.isTrue(
                e.getMessage().contains('does not exist or is not accessible'),
                'The resolver should reject an Id that does not identify a field on the object.'
            );
        }
        Test.stopTest();

        Assert.isTrue(exceptionThrown);
    }

    @IsTest
    static void resolveQueryableFieldRejectsInvalidObjectAndField() {
        Test.startTest();
        try {
            ComplianceAgentResolver.resolveQueryableFieldApiName(
                'Object_That_Does_Not_Exist__c',
                'OwnerId'
            );
            Assert.fail('Expected invalid-object exception.');
        } catch (ComplianceAgentException e) {
            Assert.isTrue(e.getMessage().contains('does not exist or is not accessible'));
        }

        try {
            ComplianceAgentResolver.resolveQueryableFieldApiName(
                'CGContrReviewer__Compliance_Test_Record__c',
                'Field_That_Does_Not_Exist__c'
            );
            Assert.fail('Expected invalid-field exception.');
        } catch (ComplianceAgentException e) {
            Assert.isTrue(e.getMessage().contains('does not exist or is not accessible'));
        }
        Test.stopTest();
    }

    @IsTest
    static void controllerReturnsResolvedContext() {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            createSetting('User_Self', 'User', 'User', null, null);
        useSettings(new List<ComplianceAgentConfigurationProvider.SettingConfig>{ setting });

        Test.startTest();
        ComplianceAgentController.ReviewContextResult result =
            ComplianceAgentController.getReviewContext(UserInfo.getUserId(), 'User');
        Test.stopTest();

        Assert.areEqual('User_Self', result.settingDeveloperName);
        Assert.areEqual(String.valueOf(UserInfo.getUserId()), result.targetRecordId);
        Assert.isTrue(
            containsFileWithTitle(result.availableFiles, USER_PDF_TITLE),
            'Controller should return the PDF explicitly published to the user.'
        );
    }

    @IsTest
    static void controllerTranslatesBusinessException() {
        useSettings(new List<ComplianceAgentConfigurationProvider.SettingConfig>());

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ComplianceAgentController.getReviewContext(UserInfo.getUserId(), 'User');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'));
        }
        Test.stopTest();

        Assert.isTrue(exceptionThrown, 'Controller should translate business errors.');
    }

    @IsTest
    static void controllerTranslatesUnexpectedException() {
        ConfigurationProviderStub stub = new ConfigurationProviderStub();
        stub.throwUnexpectedException = true;
        ComplianceAgentConfigurationProvider.instance = stub;

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ComplianceAgentController.getReviewContext(UserInfo.getUserId(), 'User');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'));
        }
        Test.stopTest();

        Assert.isTrue(exceptionThrown, 'Controller should translate unexpected errors.');
    }

    private static ContentVersion createFile(
        String title,
        String pathOnClient,
        Id firstPublishLocationId
    ) {
        return new ContentVersion(
            Title = title,
            PathOnClient = pathOnClient,
            VersionData = Blob.valueOf('Resolver test content: ' + title),
            FirstPublishLocationId = firstPublishLocationId
        );
    }

    private static CGContrReviewer__Compliance_Test_Record__c getFixture() {
        return [SELECT Id, OwnerId FROM CGContrReviewer__Compliance_Test_Record__c LIMIT 1];
    }

    private static Boolean containsFileWithTitle(
        List<ComplianceAgentController.AvailableFile> files,
        String expectedTitle
    ) {
        for (ComplianceAgentController.AvailableFile file : files) {
            if (file.title == expectedTitle) {
                return true;
            }
        }
        return false;
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
        setting.developerName = developerName;
        setting.masterLabel = developerName.replace('_', ' ');
        setting.sourceObjectApiName = sourceObjectApiName;
        setting.targetObjectApiName = targetObjectApiName;
        setting.sourceRelationshipFieldApiName = sourceRelationshipFieldApiName;
        setting.targetRelationshipFieldApiName = targetRelationshipFieldApiName;
        return setting;
    }

    private static void useSettings(
        List<ComplianceAgentConfigurationProvider.SettingConfig> settings
    ) {
        ConfigurationProviderStub stub = new ConfigurationProviderStub();
        stub.settings = settings;
        ComplianceAgentConfigurationProvider.instance = stub;
    }

    private static Id createNonexistentId(String keyPrefix) {
        return (Id) (keyPrefix + '000000000000');
    }

    private class ConfigurationProviderStub extends ComplianceAgentConfigurationProvider {
        private List<ComplianceAgentConfigurationProvider.SettingConfig> settings =
            new List<ComplianceAgentConfigurationProvider.SettingConfig>();
        private Boolean throwUnexpectedException = false;

        public override List<ComplianceAgentConfigurationProvider.SettingConfig> getActiveSettings(
            String sourceObjectApiName
        ) {
            if (throwUnexpectedException) {
                Integer.valueOf('force-unexpected-exception');
            }
            return settings;
        }
    }
}