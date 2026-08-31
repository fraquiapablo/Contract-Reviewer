/**
 * @description       : JSON contract returned by the compliance prompt template
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 08-19-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@JsonAccess(serializable='always' deserializable='always')
public class ComplianceReviewResult {
    @AuraEnabled public String status;
    @AuraEnabled public Integer discrepancyCount;
    @AuraEnabled public String summaryHtml;
    @AuraEnabled public List<Discrepancy> discrepancies;
}