/**
 * @description       : JSON contract returned by the compliance prompt template
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 08-19-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@JsonAccess(serializable='always' deserializable='always')
public class Discrepancy {
    @AuraEnabled public String field;
    @AuraEnabled public String expectedValueFromContract;
    @AuraEnabled public String actualValueFromSalesforce;
    @AuraEnabled public String severity;
    @AuraEnabled public String recordId;
    @AuraEnabled public String objectApiName;
}