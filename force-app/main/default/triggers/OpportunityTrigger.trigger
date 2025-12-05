/**
 * Trigger to initiate Mercury invoice creation when Opportunity stage changes to 'Invoice'
 */
trigger OpportunityTrigger on Opportunity (after update) {
    List<Opportunity> oppsToInvoice = new List<Opportunity>();

    for (Opportunity opp : Trigger.new) {
        Opportunity oldOpp = Trigger.oldMap.get(opp.Id);

        // Check if stage changed to one that should trigger invoicing
        // Only process if no invoice exists yet
        if (opp.StageName == 'Invoice' &&
            oldOpp.StageName != 'Invoice' &&
            String.isBlank(opp.Mercury_Invoice_Id__c)) {
            oppsToInvoice.add(opp);
        }
    }

    if (!oppsToInvoice.isEmpty()) {
        MercuryInvoiceHandler.processInvoices(oppsToInvoice);
    }
}
