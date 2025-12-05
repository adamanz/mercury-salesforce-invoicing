/**
 * Trigger to initiate Mercury invoice creation when Opportunity stage changes
 * Stage name is configurable via Mercury Settings custom metadata
 */
trigger OpportunityTrigger on Opportunity (after update) {
    List<Opportunity> oppsToInvoice = new List<Opportunity>();

    // Get the configured trigger stage from settings
    String triggerStage = MercurySettings.getInvoiceTriggerStage();

    for (Opportunity opp : Trigger.new) {
        Opportunity oldOpp = Trigger.oldMap.get(opp.Id);

        // Check if stage changed to one that should trigger invoicing
        // Only process if no invoice exists yet
        if (opp.StageName == triggerStage &&
            oldOpp.StageName != triggerStage &&
            String.isBlank(opp.Mercury_Invoice_Id__c)) {
            oppsToInvoice.add(opp);
        }
    }

    if (!oppsToInvoice.isEmpty()) {
        MercuryInvoiceHandler.processInvoices(oppsToInvoice);
    }
}
