import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getReviewContext from '@salesforce/apex/ComplianceAgentController.getReviewContext';
import analyze from '@salesforce/apex/ComplianceAgentAnalyzer.analyze';
import { NavigationMixin } from 'lightning/navigation';

export default class ComplianceAgentReviewButton extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;

    reviewContext;
    wiredResult;
    error;
    isProcessing = false;
    selectedContentVersionId;

    @wire(getReviewContext, { recordId: '$recordId', objectApiName: '$objectApiName' })
    wiredReviewContext(result) {
        this.wiredResult = result;
        if (result.data) {
            this.reviewContext = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.reviewContext = undefined;
            this.error = result.error.body?.message || 'Error retrieving the configuration.';
        }
    }

    get hasError() {
        return !!this.error;
    }

    /*
    get isFileType() {
        return this.reviewContext?.contentType === 'File';
    }
    */

    get fileOptions() {
        if (!this.reviewContext?.availableFiles) {
            return [];
        }
        return this.reviewContext.availableFiles.map((f) => ({
            label: f.title + (f.isArchived ? ' (Archived)' : ''),
            value: f.contentVersionId
        }));
    }

    get hasFiles() {
        return this.fileOptions.length > 0;
    }

    get canAnalyze() {
        return !!this.reviewContext && !!this.selectedContentVersionId;
    }

    get isAnalyzeDisabled() {
        return !this.canAnalyze  || this.isProcessing;
    }

    handleFileChange(event) {
        this.selectedContentVersionId = event.detail.value;
    }

    async handleAnalyze() {
        this.isProcessing = true;
        this.error = undefined;
        try {
            const reviewId = await analyze({
                recordId: this.recordId,
                objectApiName: this.objectApiName,
                selectedContentVersionId: this.selectedContentVersionId
            });
            this.navigateToReview(reviewId);
        } catch (e) {
            this.error = e.body?.message || 'Error analyzing the contract.';
        } finally {
            this.isProcessing = false;
        }
    }

    navigateToReview(reviewId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: reviewId,
                actionName: 'view'
            }
        });
    }

    handleRefresh() {
        refreshApex(this.wiredResult);
    }
}