/**
 * Queueable handler for processing Mercury invoices
 * Handles customer creation and invoice generation with proper error tracking
 */
public class MercuryInvoiceHandler implements Queueable, Database.AllowsCallouts {

    private List<Id> opportunityIds;

    public MercuryInvoiceHandler(List<Id> opportunityIds) {
        this.opportunityIds = opportunityIds;
    }

    /**
     * Entry point for processing invoices from trigger
     * @param opps List of opportunities to process
     */
    public static void processInvoices(List<Opportunity> opps) {
        List<Id> oppIds = new List<Id>();
        for (Opportunity opp : opps) {
            oppIds.add(opp.Id);
        }
        System.enqueueJob(new MercuryInvoiceHandler(oppIds));
    }

    public void execute(QueueableContext context) {
        List<Opportunity> opps = [
            SELECT Id, Name, Amount, AccountId, Account.Name,
                   Account.Mercury_Customer_Id__c, Account.BillingStreet,
                   Account.BillingCity, Account.BillingState,
                   Account.BillingPostalCode, Account.BillingCountry
            FROM Opportunity
            WHERE Id IN :opportunityIds
        ];

        List<Opportunity> oppsToUpdate = new List<Opportunity>();
        List<Account> accountsToUpdate = new List<Account>();
        Set<Id> processedAccountIds = new Set<Id>();

        for (Opportunity opp : opps) {
            Datetime now = Datetime.now();

            try {
                String customerId = opp.Account.Mercury_Customer_Id__c;

                // Create customer if doesn't exist
                if (String.isBlank(customerId)) {
                    List<Contact> contacts = [
                        SELECT Id, Email, FirstName, LastName
                        FROM Contact
                        WHERE AccountId = :opp.AccountId
                        AND Email != null
                        LIMIT 1
                    ];

                    if (contacts.isEmpty()) {
                        throw new MercuryNonRetryableException(
                            'No Contact with email found for Account. A contact with email is required for invoicing.'
                        );
                    }

                    customerId = MercuryService.createCustomer(opp.Account, contacts[0]);

                    if (!processedAccountIds.contains(opp.AccountId)) {
                        accountsToUpdate.add(new Account(
                            Id = opp.AccountId,
                            Mercury_Customer_Id__c = customerId,
                            Mercury_Sync_Status__c = 'Synced',
                            Mercury_Last_Sync_Attempt__c = now,
                            Mercury_Error_Message__c = null
                        ));
                        processedAccountIds.add(opp.AccountId);
                    }
                }

                // Create invoice
                MercuryService.MercuryInvoiceResult result = MercuryService.createInvoice(opp, customerId);

                oppsToUpdate.add(new Opportunity(
                    Id = opp.Id,
                    Mercury_Invoice_Id__c = result.invoiceId,
                    Mercury_Invoice_Status__c = capitalizeStatus(result.status),
                    Mercury_Invoice_URL__c = result.invoiceUrl,
                    Mercury_Last_Sync_Attempt__c = now,
                    Mercury_Error_Message__c = null
                ));

            } catch (MercuryRetryableException e) {
                // Log error but could be retried
                oppsToUpdate.add(new Opportunity(
                    Id = opp.Id,
                    Mercury_Error_Message__c = e.getMessage().left(255),
                    Mercury_Last_Sync_Attempt__c = now
                ));
                System.debug(LoggingLevel.ERROR, 'Retryable error for Opp ' + opp.Id + ': ' + e.getMessage());

            } catch (MercuryNonRetryableException e) {
                // Non-retryable error - mark appropriately
                oppsToUpdate.add(new Opportunity(
                    Id = opp.Id,
                    Mercury_Error_Message__c = e.getMessage().left(255),
                    Mercury_Last_Sync_Attempt__c = now
                ));
                System.debug(LoggingLevel.ERROR, 'Non-retryable error for Opp ' + opp.Id + ': ' + e.getMessage());

            } catch (Exception e) {
                // Unexpected error
                oppsToUpdate.add(new Opportunity(
                    Id = opp.Id,
                    Mercury_Error_Message__c = ('Unexpected error: ' + e.getMessage()).left(255),
                    Mercury_Last_Sync_Attempt__c = now
                ));
                System.debug(LoggingLevel.ERROR, 'Unexpected error for Opp ' + opp.Id + ': ' + e.getMessage());
            }
        }

        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }
        if (!oppsToUpdate.isEmpty()) {
            update oppsToUpdate;
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
