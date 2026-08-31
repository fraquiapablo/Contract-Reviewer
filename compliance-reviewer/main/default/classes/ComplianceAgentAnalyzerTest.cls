/**
 * @description       : Unit tests for ComplianceAgentAnalyzer and its Prompt Template input contract.
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 08-28-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@IsTest
private class ComplianceAgentAnalyzerTest {

    private static final String FILE_TITLE = 'Analyzer Contract';
    private static final String SETTING_NAME = 'User_Analyzer_Setting';

    @TestSetup
    static void setupData() {
        insert new ContentVersion(
            Title = FILE_TITLE,
            PathOnClient = 'analyzer-contract.pdf',
            VersionData = Blob.valueOf('Compliance Agent Analyzer test content'),
            FirstPublishLocationId = UserInfo.getUserId()
        );
    }

    @IsTest
    static void analyzeCreatesCompleteAuditRecordWithoutCallingEinstein() {
        useValidConfiguration();
        PromptInvokerStub promptStub = usePromptResponse(createValidResponseJson());
        ContentVersion selectedFile = getFile();

        Test.startTest();
        Id reviewId = ComplianceAgentAnalyzer.analyze(
            UserInfo.getUserId(),
            'User',
            String.valueOf(selectedFile.Id)
        );
        Test.stopTest();

        Assert.isTrue(promptStub.wasInvoked, 'Prompt stub should have been invoked once.');
        Assert.areEqual(1, promptStub.invocationCount);
        Assert.areEqual(
            String.valueOf(selectedFile.ContentDocumentId),
            promptStub.receivedContentDocumentId
        );
        Assert.isNotNull(promptStub.receivedEvidenceJson);

        Map<String, Object> sentPacket = (Map<String, Object>) JSON.deserializeUntyped(
            promptStub.receivedEvidenceJson
        );
        Map<String, Object> sentTarget = (Map<String, Object>) sentPacket.get('target');
        List<Object> sentContexts = (List<Object>) sentPacket.get('context');
        Map<String, Object> firstContext = (Map<String, Object>) sentContexts[0];
        List<Object> sentRecords = (List<Object>) firstContext.get('records');

        Assert.areEqual(SETTING_NAME, sentPacket.get('settingDeveloperName'));
        Assert.areEqual('User', sentTarget.get('objectApiName'));
        Assert.areEqual(String.valueOf(UserInfo.getUserId()), sentTarget.get('recordId'));
        Assert.areEqual(1, sentContexts.size());
        Assert.areEqual('User', firstContext.get('objectApiName'));
        Assert.areEqual(1, sentRecords.size());

        Compliance_Review__c review = [
            SELECT Source_Record_Id__c,
                Source_Object_API_Name__c,
                Target_Record_Id__c,
                Target_Object_API_Name__c,
                Compliance_Agent_Setting__c,
                Request_Payload__c,
                Content_Document_Id__c,
                Content_Version_Id__c,
                File_Title__c,
                Status__c,
                Discrepancy_Count__c,
                Summary_Html__c,
                Raw_Response__c
            FROM Compliance_Review__c
            WHERE Id = :reviewId
        ];

        Assert.areEqual(String.valueOf(UserInfo.getUserId()), review.Source_Record_Id__c);
        Assert.areEqual('User', review.Source_Object_API_Name__c);
        Assert.areEqual(String.valueOf(UserInfo.getUserId()), review.Target_Record_Id__c);
        Assert.areEqual('User', review.Target_Object_API_Name__c);
        Assert.areEqual(SETTING_NAME, review.Compliance_Agent_Setting__c);
        Assert.areEqual(promptStub.receivedEvidenceJson, review.Request_Payload__c);
        Assert.areEqual(
            String.valueOf(selectedFile.ContentDocumentId),
            review.Content_Document_Id__c
        );
        Assert.areEqual(String.valueOf(selectedFile.Id), review.Content_Version_Id__c);
        Assert.areEqual(FILE_TITLE, review.File_Title__c);
        Assert.areEqual('Issues Found', review.Status__c);
        Assert.areEqual(Decimal.valueOf('1'), review.Discrepancy_Count__c);
        Assert.areEqual('<p>One discrepancy found.</p>', review.Summary_Html__c);

        ComplianceReviewResult persistedResult = (ComplianceReviewResult) JSON.deserialize(
            review.Raw_Response__c,
            ComplianceReviewResult.class
        );
        Assert.areEqual('Issues Found', persistedResult.status);
        Assert.areEqual(1, persistedResult.discrepancyCount);
        Assert.areEqual(1, persistedResult.discrepancies.size());
        Assert.areEqual('Username', persistedResult.discrepancies[0].field);
        Assert.areEqual('High', persistedResult.discrepancies[0].severity);
    }

    @IsTest
    static void promptInvokerBuildsExpectedGenerationInputWithoutCallingEinstein() {
        String evidenceJson = '{"fixture":"evidence"}';
        String contentDocumentId = '069000000000001AAA';
        String expectedRawText = createNoIssuesResponseJson();
        PromptInvokerStub promptStub = new PromptInvokerStub();
        promptStub.rawText = expectedRawText;

        Test.startTest();
        ComplianceAgentAnalyzer.PromptResponse response = promptStub.invoke(
            evidenceJson,
            contentDocumentId
        );
        Test.stopTest();

        Assert.isTrue(promptStub.wasInvoked);
        Assert.areEqual(1, promptStub.invocationCount);
        Assert.areEqual(evidenceJson, promptStub.receivedEvidenceJson);
        Assert.areEqual(contentDocumentId, promptStub.receivedContentDocumentId);
        Assert.areEqual(expectedRawText, response.rawText);
        Assert.isNotNull(promptStub.receivedGenerationInput);
        Assert.areEqual(2, promptStub.receivedGenerationInput.inputParams.size());
        Assert.isTrue(
            promptStub.receivedGenerationInput.inputParams.containsKey('Input:evidenceJson')
        );
        Assert.isTrue(
            promptStub.receivedGenerationInput.inputParams.containsKey('Input:ContractFile')
        );
        Assert.isFalse(promptStub.receivedGenerationInput.isPreview);
        Assert.isNotNull(promptStub.receivedGenerationInput.additionalConfig);
        Assert.areEqual(
            'PromptBuilderPreview',
            promptStub.receivedGenerationInput.additionalConfig.applicationName
        );
        Assert.areEqual(
            1,
            promptStub.receivedGenerationInput.additionalConfig.numGenerations
        );
    }

    @IsTest
    static void analyzeAcceptsJsonWrappedInModelText() {
        useValidConfiguration();
        String wrappedResponse = 'Analysis result follows:\n```json\n' +
            createNoIssuesResponseJson() + '\n```\nEnd of response.';
        PromptInvokerStub promptStub = usePromptResponse(wrappedResponse);
        ContentVersion selectedFile = getFile();

        Test.startTest();
        Id reviewId = ComplianceAgentAnalyzer.analyze(
            UserInfo.getUserId(),
            'User',
            String.valueOf(selectedFile.Id)
        );
        Test.stopTest();

        Compliance_Review__c review = [
            SELECT Status__c, Discrepancy_Count__c, Summary_Html__c
            FROM Compliance_Review__c
            WHERE Id = :reviewId
        ];
        
        Assert.isTrue(promptStub.wasInvoked);
        Assert.areEqual('No Issues Found', review.Status__c);
        Assert.areEqual(Decimal.valueOf('0'), review.Discrepancy_Count__c);
        Assert.areEqual('<p>No discrepancies found.</p>', review.Summary_Html__c);
    }

    @IsTest
    static void parseResultDeserializesCompleteContract() {
        String responseJson = createValidResponseJson();

        Test.startTest();
        ComplianceReviewResult result = ComplianceAgentAnalyzer.parseResult(responseJson);
        Test.stopTest();

        Assert.areEqual('Issues Found', result.status);
        Assert.areEqual(1, result.discrepancyCount);
        Assert.areEqual('<p>One discrepancy found.</p>', result.summaryHtml);
        Assert.areEqual(1, result.discrepancies.size());

        Discrepancy discrepancy = result.discrepancies[0];
        Assert.areEqual('Username', discrepancy.field);
        Assert.areEqual('contract-user', discrepancy.expectedValueFromContract);
        Assert.areEqual('salesforce-user', discrepancy.actualValueFromSalesforce);
        Assert.areEqual('High', discrepancy.severity);
        Assert.areEqual(String.valueOf(UserInfo.getUserId()), discrepancy.recordId);
        Assert.areEqual('User', discrepancy.objectApiName);
    }

    @IsTest
    static void parseResultRejectsNullAndTextWithoutJsonObject() {
        Test.startTest();
        try {
            ComplianceAgentAnalyzer.parseResult(null);
            Assert.fail('Expected null-response exception.');
        } catch (ComplianceAgentException e) {
            Assert.isTrue(e.getMessage().contains('without a valid JSON object'));
        }

        try {
            ComplianceAgentAnalyzer.parseResult('The model returned plain text only.');
            Assert.fail('Expected response-without-JSON exception.');
        } catch (ComplianceAgentException e) {
            Assert.isTrue(e.getMessage().contains('without a valid JSON object'));
        }

        try {
            ComplianceAgentAnalyzer.parseResult('{');
            Assert.fail('Expected incomplete-JSON-object exception.');
        } catch (ComplianceAgentException e) {
            Assert.isTrue(e.getMessage().contains('without a valid JSON object'));
        }
        Test.stopTest();
    }

    @IsTest
    static void analyzeTranslatesPromptBusinessException() {
        useValidConfiguration();
        PromptInvokerStub promptStub = new PromptInvokerStub();
        promptStub.throwBusinessException = true;
        ComplianceAgentAnalyzer.invoker = promptStub;
        ContentVersion selectedFile = getFile();

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ComplianceAgentAnalyzer.analyze(
                UserInfo.getUserId(),
                'User',
                String.valueOf(selectedFile.Id)
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'));
        }
        Test.stopTest();

        Assert.isTrue(exceptionThrown, 'Analyzer should translate expected prompt errors.');
        Assert.isTrue(promptStub.wasInvoked);
        Assert.areEqual(0, [SELECT COUNT() FROM Compliance_Review__c]);
    }

    @IsTest
    static void analyzeTranslatesUnexpectedPromptException() {
        useValidConfiguration();
        PromptInvokerStub promptStub = new PromptInvokerStub();
        promptStub.throwUnexpectedException = true;
        ComplianceAgentAnalyzer.invoker = promptStub;
        ContentVersion selectedFile = getFile();

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ComplianceAgentAnalyzer.analyze(
                UserInfo.getUserId(),
                'User',
                String.valueOf(selectedFile.Id)
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'));
        }
        Test.stopTest();

        Assert.isTrue(exceptionThrown, 'Analyzer should translate unexpected prompt errors.');
        Assert.isTrue(promptStub.wasInvoked);
        Assert.areEqual(0, [SELECT COUNT() FROM Compliance_Review__c]);
    }

    @IsTest
    static void analyzeTranslatesResponseWithoutJsonObject() {
        useValidConfiguration();
        PromptInvokerStub promptStub = usePromptResponse('No structured result was generated.');
        ContentVersion selectedFile = getFile();

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ComplianceAgentAnalyzer.analyze(
                UserInfo.getUserId(),
                'User',
                String.valueOf(selectedFile.Id)
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'));
        }
        Test.stopTest();

        Assert.isTrue(exceptionThrown);
        Assert.isTrue(promptStub.wasInvoked);
        Assert.areEqual(0, [SELECT COUNT() FROM Compliance_Review__c]);
    }

    @IsTest
    static void analyzeTranslatesMalformedJsonAsUnexpectedError() {
        useValidConfiguration();
        PromptInvokerStub promptStub = usePromptResponse('{invalid-json}');
        ContentVersion selectedFile = getFile();

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ComplianceAgentAnalyzer.analyze(
                UserInfo.getUserId(),
                'User',
                String.valueOf(selectedFile.Id)
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'));
        }
        Test.stopTest();

        Assert.isTrue(exceptionThrown);
        Assert.isTrue(promptStub.wasInvoked);
        Assert.areEqual(0, [SELECT COUNT() FROM Compliance_Review__c]);
    }

    @IsTest
    static void analyzeDoesNotInvokePromptWhenEvidenceBuildFails() {
        ComplianceAgentConfigurationProvider.SettingConfig setting = createSetting();
        useConfiguration(
            setting,
            new List<ComplianceAgentConfigurationProvider.ContextConfig>()
        );
        PromptInvokerStub promptStub = usePromptResponse(createValidResponseJson());
        ContentVersion selectedFile = getFile();

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            ComplianceAgentAnalyzer.analyze(
                UserInfo.getUserId(),
                'User',
                String.valueOf(selectedFile.Id)
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            Assert.isTrue(e.getTypeName().contains('AuraHandledException'));
        }
        Test.stopTest();

        Assert.isTrue(exceptionThrown);
        Assert.isFalse(promptStub.wasInvoked, 'Prompt must not run when evidence is invalid.');
        Assert.areEqual(0, promptStub.invocationCount);
        Assert.areEqual(0, [SELECT COUNT() FROM Compliance_Review__c]);
    }

    private static void useValidConfiguration() {
        ComplianceAgentConfigurationProvider.SettingConfig setting = createSetting();
        ComplianceAgentConfigurationProvider.ContextConfig context =
            new ComplianceAgentConfigurationProvider.ContextConfig();
        context.developerName = 'Analyzer_User_Context';
        context.contextObjectApiName = 'User';
        context.fieldSetApiName = 'Analyzer_User_Fields';
        context.relationshipFieldApiName = null;
        context.filterCriteria = null;
        context.parentContextObjectApiName = null;
        context.fieldNames = new List<String>{ 'Id', 'Name', 'Username' };

        useConfiguration(
            setting,
            new List<ComplianceAgentConfigurationProvider.ContextConfig>{ context }
        );
    }

    private static ComplianceAgentConfigurationProvider.SettingConfig createSetting() {
        ComplianceAgentConfigurationProvider.SettingConfig setting =
            new ComplianceAgentConfigurationProvider.SettingConfig();
        setting.metadataRecordId = UserInfo.getUserId();
        setting.developerName = SETTING_NAME;
        setting.masterLabel = 'User Analyzer Setting';
        setting.sourceObjectApiName = 'User';
        setting.targetObjectApiName = 'User';
        setting.sourceRelationshipFieldApiName = null;
        setting.targetRelationshipFieldApiName = null;
        return setting;
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

    private static PromptInvokerStub usePromptResponse(String rawText) {
        PromptInvokerStub stub = new PromptInvokerStub();
        stub.rawText = rawText;
        ComplianceAgentAnalyzer.invoker = stub;
        return stub;
    }

    private static ContentVersion getFile() {
        return [
            SELECT Id, Title, ContentDocumentId
            FROM ContentVersion
            WHERE Title = :FILE_TITLE
            LIMIT 1
        ];
    }

    private static String createValidResponseJson() {
        Map<String, Object> discrepancy = new Map<String, Object>{
            'field' => 'Username',
            'expectedValueFromContract' => 'contract-user',
            'actualValueFromSalesforce' => 'salesforce-user',
            'severity' => 'High',
            'recordId' => String.valueOf(UserInfo.getUserId()),
            'objectApiName' => 'User'
        };
        Map<String, Object> response = new Map<String, Object>{
            'status' => 'Issues Found',
            'discrepancyCount' => 1,
            'summaryHtml' => '<p>One discrepancy found.</p>',
            'discrepancies' => new List<Object>{ discrepancy }
        };
        return JSON.serialize(response);
    }

    private static String createNoIssuesResponseJson() {
        Map<String, Object> response = new Map<String, Object>{
            'status' => 'No Issues Found',
            'discrepancyCount' => 0,
            'summaryHtml' => '<p>No discrepancies found.</p>',
            'discrepancies' => new List<Object>()
        };
        return JSON.serialize(response);
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

    private class PromptInvokerStub extends ComplianceAgentAnalyzer.PromptInvoker {
        private String rawText;
        private Boolean throwBusinessException = false;
        private Boolean throwUnexpectedException = false;
        private Boolean wasInvoked = false;
        private Integer invocationCount = 0;
        private String receivedEvidenceJson;
        private String receivedContentDocumentId;
        private ConnectApi.EinsteinPromptTemplateGenerationsInput receivedGenerationInput;

        protected override String generateRawText(
            ConnectApi.EinsteinPromptTemplateGenerationsInput genInput
        ) {
            wasInvoked = true;
            invocationCount++;
            receivedGenerationInput = genInput;
            receivedEvidenceJson = String.valueOf(
                genInput.inputParams.get('Input:evidenceJson').value
            );
            Map<String, String> fileReference = (Map<String, String>)
                genInput.inputParams.get('Input:ContractFile').value;
            receivedContentDocumentId = fileReference.get('id');

            if (throwBusinessException) {
                throw new ComplianceAgentException('Simulated expected prompt error.');
            }
            if (throwUnexpectedException) {
                Integer.valueOf('force-unexpected-prompt-error');
            }

            return rawText;
        }
    }
}