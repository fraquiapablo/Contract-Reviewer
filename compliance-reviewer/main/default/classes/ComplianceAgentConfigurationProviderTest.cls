/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 08-21-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@IsTest
private class ComplianceAgentConfigurationProviderTest {

    private static final String SETTING_DEVELOPER_NAME =
        'Compliance_Test_Record_Provider_Test';
    private static final String SETTING_LABEL =
        'Compliance Test Record Provider Test';
    private static final String CONTEXT_DEVELOPER_NAME =
        'Compliance_Test_Record_Provider_Context';
    private static final String FIELD_SET_API_NAME =
        'CGContrReviewer__Compliance_Agent_Test_Fields';

    @IsTest
    static void getInstanceReturnsDefaultProvider() {
        ComplianceAgentConfigurationProvider.resetInstance();

        ComplianceAgentConfigurationProvider provider =
            ComplianceAgentConfigurationProvider.getInstance();

        Assert.isNotNull(provider, 'The default configuration provider should exist.');
    }

    @IsTest
    static void resetInstanceRestoresDefaultProvider() {
        ConfigurationProviderStub stub = new ConfigurationProviderStub();
        ComplianceAgentConfigurationProvider.instance = stub;

        Assert.isTrue(
            ComplianceAgentConfigurationProvider.getInstance() == stub,
            'The test stub should be installed before resetting the singleton.'
        );

        ComplianceAgentConfigurationProvider.resetInstance();

        Assert.isTrue(
            ComplianceAgentConfigurationProvider.getInstance() != stub,
            'Resetting the singleton should restore the real provider.'
        );
    }

    @IsTest
    static void getActiveSettingsMapsProtectedFixture() {
        ComplianceAgentConfigurationProvider.resetInstance();
        ComplianceAgentConfigurationProvider provider =
            ComplianceAgentConfigurationProvider.getInstance();
        String objectApiName = getFixtureObjectApiName();

        Test.startTest();
        List<ComplianceAgentConfigurationProvider.SettingConfig> settings =
            provider.getActiveSettings(objectApiName);
        Test.stopTest();

        Assert.areEqual(
            1,
            settings.size(),
            'Exactly one active test setting should exist for the fixture object.'
        );

        ComplianceAgentConfigurationProvider.SettingConfig setting = settings[0];

        Assert.isNotNull(setting.metadataRecordId, 'The metadata record Id should be mapped.');
        Assert.areEqual(SETTING_DEVELOPER_NAME, setting.developerName);
        Assert.areEqual(SETTING_LABEL, setting.masterLabel);
        Assert.areEqual(objectApiName, setting.sourceObjectApiName);
        Assert.isNull(setting.sourceRelationshipFieldApiName);
        Assert.areEqual(objectApiName, setting.targetObjectApiName);
        Assert.isNull(setting.targetRelationshipFieldApiName);
    }

    @IsTest
    static void getActiveSettingsReturnsEmptyListWhenNoConfigurationExists() {
        ComplianceAgentConfigurationProvider.resetInstance();

        Test.startTest();
        List<ComplianceAgentConfigurationProvider.SettingConfig> settings =
            ComplianceAgentConfigurationProvider.getInstance().getActiveSettings(
                'Definitely_Not_A_Configured_Object__c'
            );
        Test.stopTest();

        Assert.isNotNull(settings, 'The provider should return a list, not null.');
        Assert.areEqual(0, settings.size());
    }

    @IsTest
    static void getContextsMapsProtectedFixtureAndFieldSetMembers() {
        ComplianceAgentConfigurationProvider.resetInstance();
        ComplianceAgentConfigurationProvider provider =
            ComplianceAgentConfigurationProvider.getInstance();
        String objectApiName = getFixtureObjectApiName();

        List<ComplianceAgentConfigurationProvider.SettingConfig> settings =
            provider.getActiveSettings(objectApiName);
        Assert.areEqual(1, settings.size(), 'The parent test setting should exist.');

        Test.startTest();
        List<ComplianceAgentConfigurationProvider.ContextConfig> contexts =
            provider.getContexts(settings[0].metadataRecordId);
        Test.stopTest();

        Assert.areEqual(
            1,
            contexts.size(),
            'Exactly one context should belong to the test setting.'
        );

        ComplianceAgentConfigurationProvider.ContextConfig context = contexts[0];

        Assert.areEqual(CONTEXT_DEVELOPER_NAME, context.developerName);
        Assert.areEqual(objectApiName, context.contextObjectApiName);
        Assert.areEqual(FIELD_SET_API_NAME, context.fieldSetApiName);
        Assert.isNull(context.relationshipFieldApiName);
        Assert.isNull(context.filterCriteria);
        Assert.isNull(context.parentContextObjectApiName);
        Assert.isNotNull(context.fieldNames);
        Assert.areEqual(
            2,
            context.fieldNames.size(),
            'The provider should add Id to the Name field declared in the Field Set.'
        );
        Assert.isTrue(context.fieldNames.contains('Id'));
        Assert.isTrue(context.fieldNames.contains('Name'));
    }

    @IsTest
    static void getContextsReturnsEmptyListForNullSettingId() {
        ComplianceAgentConfigurationProvider.resetInstance();

        Test.startTest();
        List<ComplianceAgentConfigurationProvider.ContextConfig> contexts =
            ComplianceAgentConfigurationProvider.getInstance().getContexts(null);
        Test.stopTest();

        Assert.isNotNull(contexts, 'The provider should return a list, not null.');
        Assert.areEqual(0, contexts.size());
    }

    @IsTest
    static void getFieldSetMembersReturnsIdAndConfiguredFields() {
        Test.startTest();
        List<String> fieldNames =
            ComplianceAgentConfigurationProvider.getFieldSetMembers(
                getFixtureObjectApiName(),
                FIELD_SET_API_NAME
            );
        Test.stopTest();

        Assert.isNotNull(fieldNames);
        Assert.areEqual(
            2,
            fieldNames.size(),
            'The provider should add Id to the Name field declared in the Field Set.'
        );
        Assert.isTrue(fieldNames.contains('Id'));
        Assert.isTrue(fieldNames.contains('Name'));
    }

    @IsTest
    static void getFieldSetMembersRejectsUnknownObject() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            ComplianceAgentConfigurationProvider.getFieldSetMembers(
                'Definitely_Not_An_Object__c',
                FIELD_SET_API_NAME
            );
            Assert.fail('Expected an exception for an unknown context object.');
        } catch (ComplianceAgentException e) {
            exceptionThrown = true;
            Assert.isTrue(
                e.getMessage().contains('does not exist or is not accessible'),
                'The exception should identify the invalid context object.'
            );
        }
        Test.stopTest();

        Assert.isTrue(exceptionThrown);
    }

    @IsTest
    static void getFieldSetMembersRejectsUnknownFieldSet() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            ComplianceAgentConfigurationProvider.getFieldSetMembers(
                getFixtureObjectApiName(),
                'Definitely_Not_A_Field_Set'
            );
            Assert.fail('Expected an exception for an unknown Field Set.');
        } catch (ComplianceAgentException e) {
            exceptionThrown = true;
            Assert.isTrue(
                e.getMessage().contains('was not found on object'),
                'The exception should identify the invalid Field Set.'
            );
        }
        Test.stopTest();

        Assert.isTrue(exceptionThrown);
    }

    private static String getFixtureObjectApiName() {
        return Compliance_Test_Record__c.SObjectType.getDescribe().getName();
    }

    private class ConfigurationProviderStub
        extends ComplianceAgentConfigurationProvider {
    }
}