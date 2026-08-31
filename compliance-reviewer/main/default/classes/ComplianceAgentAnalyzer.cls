/**
 * @description Invokes the Compliance Agent prompt template with the evidence packet
 *              and persists the analysis result as a Compliance_Review__c audit record.
 */
public with sharing class ComplianceAgentAnalyzer {

    private static final String PROMPT_TEMPLATE_NAME = 'Compliance_Agent_Contract_Evidence_Analysis';

    @TestVisible
    private static PromptInvoker invoker = new PromptInvoker();

    @AuraEnabled
    public static Id analyze(Id recordId, String objectApiName, String selectedContentVersionId) {
        try {
            ComplianceAgentEvidenceBuilder.EvidencePacket packet =
                ComplianceAgentEvidenceBuilder.buildPacket(recordId, objectApiName, selectedContentVersionId);

            String evidenceJson = JSON.serialize(packet);
            PromptResponse response = invoker.invoke(evidenceJson, packet.target.fileReference.contentDocumentId);
            ComplianceReviewResult result = parseResult(response.rawText);

            Compliance_Review__c review = new Compliance_Review__c();
            review.Source_Record_Id__c = String.valueOf(recordId);
            review.Source_Object_API_Name__c = objectApiName;
            review.Target_Record_Id__c = packet.target.recordId;
            review.Target_Object_API_Name__c = packet.target.objectApiName;
            review.Compliance_Agent_Setting__c = packet.settingDeveloperName;
            review.Request_Payload__c = evidenceJson;
            review.Content_Document_Id__c = packet.target.fileReference.contentDocumentId;
            review.Content_Version_Id__c = packet.target.fileReference.contentVersionId;
            review.File_Title__c = packet.target.fileReference.title;
            review.Status__c = result.status;
            review.Discrepancy_Count__c = result.discrepancyCount;
            review.Summary_Html__c = result.summaryHtml;
            review.Raw_Response__c = JSON.serialize(result);

            Database.insert(review, AccessLevel.SYSTEM_MODE);
            return review.Id;

        } catch (ComplianceAgentException e) {
            throw new AuraHandledException(e.getMessage());
        } catch (Exception e) {
            throw new AuraHandledException('Unexpected error while analyzing the contract: ' + e.getMessage());
        }
    }

    public virtual class PromptInvoker {
        public virtual PromptResponse invoke(String evidenceJson, String contentDocumentId) {
            Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();

            ConnectApi.WrappedValue evidenceValue = new ConnectApi.WrappedValue();
            evidenceValue.value = evidenceJson;
            inputParams.put('Input:evidenceJson', evidenceValue);

            ConnectApi.WrappedValue fileValue = new ConnectApi.WrappedValue();
            fileValue.value = new Map<String, String>{ 'id' => contentDocumentId };
            inputParams.put('Input:ContractFile', fileValue);

            ConnectApi.EinsteinPromptTemplateGenerationsInput genInput =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            genInput.inputParams = inputParams;
            genInput.isPreview = false;
            genInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            genInput.additionalConfig.applicationName = 'PromptBuilderPreview';
            genInput.additionalConfig.numGenerations = 1;

            String rawText = generateRawText(genInput);

            PromptResponse response = new PromptResponse();
            response.rawText = rawText;
            return response;
        }

        /**
         * Executes the external Einstein Prompt Template call.
         * Tests override only this method so that invoke() still builds and exposes
         * the same ConnectApi input used in production without making a real AI call.
         */
        protected virtual String generateRawText(
            ConnectApi.EinsteinPromptTemplateGenerationsInput genInput
        ) {
            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation output =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(PROMPT_TEMPLATE_NAME, genInput);

            if (output == null || output.generations == null || output.generations.isEmpty()) {
                System.debug(LoggingLevel.INFO, '### PT output: ' + JSON.serializePretty(output));
                throw new ComplianceAgentException('The AI model returned no response.');
            }

            return output.generations[0].text;
        }
    }

    public class PromptResponse {
        public String rawText;
    }

    @TestVisible
    private static ComplianceReviewResult parseResult(String rawText) {
        String cleaned = rawText == null ? '' : rawText.trim();
        Integer firstBrace = cleaned.indexOf('{');
        Integer lastBrace = cleaned.lastIndexOf('}');
        if (firstBrace == -1 || lastBrace <= firstBrace) {
            throw new ComplianceAgentException('The AI model returned a response without a valid JSON object.');
        }
        cleaned = cleaned.substring(firstBrace, lastBrace + 1);
        return (ComplianceReviewResult) JSON.deserialize(cleaned, ComplianceReviewResult.class);
    }

}