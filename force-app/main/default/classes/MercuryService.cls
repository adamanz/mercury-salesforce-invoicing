/**
 * Service class for Mercury API integration
 * Handles customer and invoice operations with proper error handling
 */
public class MercuryService {

    private static final String NAMED_CREDENTIAL = 'callout:Mercury_API';
    private static final Integer TIMEOUT_MS = 30000;

    /**
     * Create a customer in Mercury from Salesforce Account/Contact data
     * @param acc The Account to create as a Mercury customer
     * @param primaryContact The primary contact for the customer
     * @return The Mercury Customer ID
     */
    public static String createCustomer(Account acc, Contact primaryContact) {
        Map<String, Object> customerData = new Map<String, Object>{
            'name' => acc.Name,
            'email' => primaryContact?.Email
        };

        // Add address if available
        Map<String, Object> address = new Map<String, Object>();
        if (String.isNotBlank(acc.BillingStreet)) {
            address.put('address1', acc.BillingStreet);
        }
        if (String.isNotBlank(acc.BillingCity)) {
            address.put('city', acc.BillingCity);
        }
        if (String.isNotBlank(acc.BillingState)) {
            address.put('state', acc.BillingState);
        }
        if (String.isNotBlank(acc.BillingPostalCode)) {
            address.put('postalCode', acc.BillingPostalCode);
        }
        if (String.isNotBlank(acc.BillingCountry)) {
            address.put('country', acc.BillingCountry);
        }

        if (!address.isEmpty()) {
            customerData.put('address', address);
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + '/api/v1/ar/customers');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(TIMEOUT_MS);
        req.setBody(JSON.serialize(customerData));

        HttpResponse res = sendRequest(req);
        handleResponse(res);

        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (String) response.get('id');
    }

    /**
     * Create and send an invoice in Mercury
     * @param opp The Opportunity to create an invoice for
     * @param mercuryCustomerId The Mercury Customer ID
     * @return MercuryInvoiceResult with invoice details
     */
    public static MercuryInvoiceResult createInvoice(Opportunity opp, String mercuryCustomerId) {
        List<Map<String, Object>> lineItems = new List<Map<String, Object>>();

        // Get line items from Opportunity
        for (OpportunityLineItem oli : [
            SELECT Id, Name, Quantity, UnitPrice, Description
            FROM OpportunityLineItem
            WHERE OpportunityId = :opp.Id
        ]) {
            lineItems.add(new Map<String, Object>{
                'description' => String.isNotBlank(oli.Description) ? oli.Description : oli.Name,
                'quantity' => oli.Quantity,
                'unitPrice' => oli.UnitPrice
            });
        }

        // If no line items, create one from opportunity amount
        if (lineItems.isEmpty()) {
            lineItems.add(new Map<String, Object>{
                'description' => opp.Name,
                'quantity' => 1,
                'unitPrice' => opp.Amount
            });
        }

        Map<String, Object> invoiceData = new Map<String, Object>{
            'customerId' => mercuryCustomerId,
            'invoiceNumber' => 'SF-' + opp.Id,
            'dueDate' => Date.today().addDays(30).format(),
            'lineItems' => lineItems,
            'sendEmailOption' => 'sendNow',
            'creditCardEnabled' => true,
            'achEnabled' => true,
            'wireEnabled' => true
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + '/api/v1/ar/invoices');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(TIMEOUT_MS);
        req.setBody(JSON.serialize(invoiceData));

        HttpResponse res = sendRequest(req);
        handleResponse(res);

        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return new MercuryInvoiceResult(
            (String) response.get('id'),
            (String) response.get('status'),
            (String) response.get('invoiceUrl')
        );
    }

    /**
     * Get the current status of an invoice
     * @param invoiceId The Mercury Invoice ID
     * @return The invoice status string
     */
    public static String getInvoiceStatus(String invoiceId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + '/api/v1/ar/invoices/' + invoiceId);
        req.setMethod('GET');
        req.setTimeout(TIMEOUT_MS);

        HttpResponse res = sendRequest(req);
        handleResponse(res);

        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (String) response.get('status');
    }

    /**
     * Send HTTP request with standard handling
     */
    private static HttpResponse sendRequest(HttpRequest req) {
        Http http = new Http();
        return http.send(req);
    }

    /**
     * Handle API response and throw appropriate exceptions
     */
    private static void handleResponse(HttpResponse res) {
        Integer statusCode = res.getStatusCode();

        if (statusCode >= 200 && statusCode < 300) {
            return; // Success
        }

        String errorBody = res.getBody();
        String errorMessage = 'Mercury API Error (' + statusCode + '): ' + errorBody;

        // Determine if retryable
        if (statusCode == 429 || statusCode >= 500) {
            throw new MercuryRetryableException(errorMessage);
        } else {
            throw new MercuryNonRetryableException(errorMessage);
        }
    }

    /**
     * Result class for invoice creation
     */
    public class MercuryInvoiceResult {
        public String invoiceId;
        public String status;
        public String invoiceUrl;

        public MercuryInvoiceResult(String invoiceId, String status, String invoiceUrl) {
            this.invoiceId = invoiceId;
            this.status = status;
            this.invoiceUrl = invoiceUrl;
        }
    }

    /**
     * Legacy exception class for backwards compatibility
     */
    public class MercuryException extends Exception {}
}
