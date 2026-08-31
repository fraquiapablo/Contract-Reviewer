/**
 * @description       : @AuraEnabled entry layer for the LWC. Exposes review context resolution and translates business exceptions into AuraHandledException.
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 08-14-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
public with sharing class ComplianceAgentController {

    public class ReviewContextResult {
        @AuraEnabled public String settingDeveloperName;
        @AuraEnabled public String targetObjectApiName;
        @AuraEnabled public String targetRecordId;
        @AuraEnabled public List<AvailableFile> availableFiles;
    }

    public class AvailableFile {
        @AuraEnabled public String contentVersionId;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String title;
        @AuraEnabled public String fileExtension;
        @AuraEnabled public Datetime contentModifiedDate;
        @AuraEnabled public Boolean isArchived;
    }

    @AuraEnabled(cacheable=true)
    public static ReviewContextResult getReviewContext(Id recordId, String objectApiName) {
        try {
            return ComplianceAgentResolver.resolve(recordId, objectApiName);
        } catch (ComplianceAgentException e) {
            throw new AuraHandledException(e.getMessage());
        } catch (Exception e) {
            throw new AuraHandledException('Unexpected error while resolving the configuration: ' + e.getMessage());
        }
    }
}