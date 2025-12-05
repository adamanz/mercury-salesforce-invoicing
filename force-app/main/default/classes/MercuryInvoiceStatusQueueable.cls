/**
 * Queueable class to poll Mercury for invoice status updates
 * Automatically closes Opportunities as Won when invoices are paid
 */
public class MercuryInvoiceStatusQueueable implements Queueable, Database.AllowsCallouts {

    private static final Integer BATCH_SIZE = 50;

    public void execute(QueueableContext context) {
        // Query opportunities with pending invoices
        List<Opportunity> oppsWithInvoices = [
            SELECT Id, Mercury_Invoice_Id__c, Mercury_Invoice_Status__c, StageName
            FROM Opportunity
            WHERE Mercury_Invoice_Id__c != null
            AND Mercury_Invoice_Status__c NOT IN ('Paid', 'Cancelled')
            AND StageName != 'Closed Won'
            AND StageName != 'Closed Lost'
            LIMIT :BATCH_SIZE
        ];

        if (oppsWithInvoices.isEmpty()) {
            return;
        }

        // Get settings
        Boolean autoCloseOnPayment = MercurySettings.isAutoCloseOnPayment();

        List<Opportunity> oppsToUpdate = new List<Opportunity>();
        Datetime now = Datetime.now();

        for (Opportunity opp : oppsWithInvoices) {
            try {
                String status = MercuryService.getInvoiceStatus(opp.Mercury_Invoice_Id__c);
                String capitalizedStatus = capitalizeStatus(status);

                Opportunity oppUpdate = new Opportunity(
                    Id = opp.Id,
                    Mercury_Invoice_Status__c = capitalizedStatus,
                    Mercury_Last_Sync_Attempt__c = now,
                    Mercury_Error_Message__c = null
                );

                // Auto close won when paid (if enabled in settings)
                if (status == 'paid' && autoCloseOnPayment) {
                    oppUpdate.StageName = 'Closed Won';
                }

                oppsToUpdate.add(oppUpdate);

            } catch (MercuryRetryableException e) {
                // Don't update status on retryable errors, just log attempt
                oppsToUpdate.add(new Opportunity(
                    Id = opp.Id,
                    Mercury_Last_Sync_Attempt__c = now,
                    Mercury_Error_Message__c = e.getMessage().left(255)
                ));
                System.debug(LoggingLevel.WARN, 'Retryable error checking invoice status: ' + e.getMessage());

            } catch (MercuryNonRetryableException e) {
                // Log non-retryable error
                oppsToUpdate.add(new Opportunity(
                    Id = opp.Id,
                    Mercury_Last_Sync_Attempt__c = now,
                    Mercury_Error_Message__c = e.getMessage().left(255)
                ));
                System.debug(LoggingLevel.ERROR, 'Non-retryable error checking invoice status: ' + e.getMessage());

            } catch (Exception e) {
                // Log unexpected error
                oppsToUpdate.add(new Opportunity(
                    Id = opp.Id,
                    Mercury_Last_Sync_Attempt__c = now,
                    Mercury_Error_Message__c = ('Unexpected: ' + e.getMessage()).left(255)
                ));
                System.debug(LoggingLevel.ERROR, 'Error checking invoice status: ' + e.getMessage());
            }
        }

        if (!oppsToUpdate.isEmpty()) {
            update oppsToUpdate;
        }

        // Chain another job if there might be more records
        if (oppsWithInvoices.size() == BATCH_SIZE) {
            // Check if we're within limits before chaining
            if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                System.enqueueJob(new MercuryInvoiceStatusQueueable());
            }
        }
    }

    /**
     * Capitalize status for picklist value
     */
    private String capitalizeStatus(String status) {
        if (String.isBlank(status)) {
            return status;
        }
        return status.substring(0, 1).toUpperCase() + status.substring(1).toLowerCase();
    }
}
