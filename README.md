# Mercury Salesforce Invoicing Integration

Generate and send invoices via Mercury's API directly from Salesforce Opportunities, then automatically mark them as Closed Won.

## Overview

This integration connects Salesforce with Mercury's Accounts Receivable API to:
1. Create customers in Mercury from Salesforce Account/Contact data
2. Generate and send invoices when Opportunities reach a specific stage
3. Track invoice status and automatically update Opportunity to Closed Won when paid

## Mercury API Overview

### Authentication

Mercury uses **Bearer token authentication** via API tokens:

```
Authorization: Bearer secret-token:mercury_production_xxx
```

**Token Management:**
- Generate tokens at: https://app.mercury.com/settings/tokens
- Three token types available:
  - **Read Only**: Fetch data only (no IP whitelist required)
  - **Read and Write**: Full access including transactions (requires IP whitelist)
  - **Custom**: Scoped permissions for specific operations

**Important:** The Invoicing API requires a **Mercury subscription plan** (Plus at $29.90/mo or Pro at $299/mo).

### Base URL

```
https://api.mercury.com/api/v1
```

### Key Endpoints

#### Customers

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/ar/customers` | Create a new customer |
| GET | `/ar/customers` | List all customers |
| GET | `/ar/customers/{id}` | Get customer by ID |
| PUT | `/ar/customers/{id}` | Update customer |
| DELETE | `/ar/customers/{id}` | Delete customer |

#### Invoices

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/ar/invoices` | Create and optionally send invoice |
| GET | `/ar/invoices` | List all invoices |
| GET | `/ar/invoices/{id}` | Get invoice by ID |
| PUT | `/ar/invoices/{id}` | Update invoice |
| POST | `/ar/invoices/{id}/cancel` | Cancel invoice |
| GET | `/ar/invoices/{id}/attachments` | Get invoice attachments |

### Invoice Creation Request

```json
{
  "customerId": "cust_xxx",
  "invoiceNumber": "INV-001",
  "dueDate": "2025-01-15",
  "lineItems": [
    {
      "description": "Consulting Services",
      "quantity": 10,
      "unitPrice": 150.00
    }
  ],
  "sendEmailOption": "sendNow",
  "creditCardEnabled": true,
  "achEnabled": true,
  "wireEnabled": true
}
```

### Invoice Statuses

- `draft` - Invoice created but not sent
- `sent` - Invoice emailed to customer
- `viewed` - Customer has viewed the invoice
- `paid` - Payment received
- `overdue` - Past due date
- `cancelled` - Invoice cancelled

## Salesforce Implementation

### Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Opportunity   │────▶│  Apex Trigger   │────▶│  Mercury API    │
│  Stage Change   │     │  / Flow         │     │  Callout        │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Opportunity   │◀────│  Platform Event │◀────│  Webhook or     │
│   Closed Won    │     │  / Scheduled    │     │  Polling        │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

### Components to Build

1. **Custom Metadata / Named Credential**
   - Store Mercury API token securely
   - Configure endpoint URL

2. **Mercury Customer Sync (Apex)**
   - Create/update Mercury customers from Salesforce Accounts
   - Store Mercury Customer ID on Account record

3. **Invoice Generation Service (Apex)**
   - Create invoices from Opportunity line items
   - Handle API callouts to Mercury
   - Store Mercury Invoice ID on Opportunity

4. **Invoice Status Tracking**
   - Option A: Webhook endpoint (requires Salesforce Site)
   - Option B: Scheduled Apex to poll invoice status

5. **Opportunity Trigger/Flow**
   - Fire when Opportunity reaches "Invoice" stage
   - Call invoice generation service

### Custom Fields Required

**Account Object:**
- `Mercury_Customer_Id__c` (Text, 50)
- `Mercury_Sync_Status__c` (Picklist: Pending, Synced, Error)

**Opportunity Object:**
- `Mercury_Invoice_Id__c` (Text, 50)
- `Mercury_Invoice_Status__c` (Picklist: Draft, Sent, Viewed, Paid, Overdue, Cancelled)
- `Mercury_Invoice_URL__c` (URL)

### Sample Apex Code

#### Named Credential Setup

Create a Named Credential called `Mercury_API`:
- URL: `https://api.mercury.com`
- Identity Type: Named Principal
- Authentication Protocol: Custom (Bearer Token)

#### Mercury Service Class

```apex
public class MercuryService {

    private static final String NAMED_CREDENTIAL = 'callout:Mercury_API';

    // Create a customer in Mercury
    public static String createCustomer(Account acc, Contact primaryContact) {
        Map<String, Object> customerData = new Map<String, Object>{
            'name' => acc.Name,
            'email' => primaryContact?.Email,
            'address' => new Map<String, Object>{
                'address1' => acc.BillingStreet,
                'city' => acc.BillingCity,
                'state' => acc.BillingState,
                'postalCode' => acc.BillingPostalCode,
                'country' => acc.BillingCountry
            }
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + '/api/v1/ar/customers');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(customerData));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
            Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) response.get('id');
        } else {
            throw new MercuryException('Failed to create customer: ' + res.getBody());
        }
    }

    // Create and send an invoice
    public static MercuryInvoiceResult createInvoice(Opportunity opp, String mercuryCustomerId) {
        List<Map<String, Object>> lineItems = new List<Map<String, Object>>();

        for (OpportunityLineItem oli : [
            SELECT Id, Name, Quantity, UnitPrice, Description
            FROM OpportunityLineItem
            WHERE OpportunityId = :opp.Id
        ]) {
            lineItems.add(new Map<String, Object>{
                'description' => oli.Description != null ? oli.Description : oli.Name,
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
        req.setBody(JSON.serialize(invoiceData));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
            Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return new MercuryInvoiceResult(
                (String) response.get('id'),
                (String) response.get('status'),
                (String) response.get('invoiceUrl')
            );
        } else {
            throw new MercuryException('Failed to create invoice: ' + res.getBody());
        }
    }

    // Check invoice status
    public static String getInvoiceStatus(String invoiceId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + '/api/v1/ar/invoices/' + invoiceId);
        req.setMethod('GET');

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) response.get('status');
        } else {
            throw new MercuryException('Failed to get invoice status: ' + res.getBody());
        }
    }

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

    public class MercuryException extends Exception {}
}
```

#### Opportunity Trigger

```apex
trigger OpportunityTrigger on Opportunity (after update) {
    List<Opportunity> oppsToInvoice = new List<Opportunity>();

    for (Opportunity opp : Trigger.new) {
        Opportunity oldOpp = Trigger.oldMap.get(opp.Id);

        // Check if stage changed to one that should trigger invoicing
        if (opp.StageName == 'Invoice' && oldOpp.StageName != 'Invoice') {
            oppsToInvoice.add(opp);
        }
    }

    if (!oppsToInvoice.isEmpty()) {
        MercuryInvoiceHandler.processInvoices(oppsToInvoice);
    }
}
```

#### Invoice Handler (Queueable for Callouts)

```apex
public class MercuryInvoiceHandler implements Queueable, Database.AllowsCallouts {

    private List<Id> opportunityIds;

    public MercuryInvoiceHandler(List<Id> opportunityIds) {
        this.opportunityIds = opportunityIds;
    }

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

        for (Opportunity opp : opps) {
            try {
                String customerId = opp.Account.Mercury_Customer_Id__c;

                // Create customer if doesn't exist
                if (String.isBlank(customerId)) {
                    Contact primaryContact = [
                        SELECT Id, Email, FirstName, LastName
                        FROM Contact
                        WHERE AccountId = :opp.AccountId
                        LIMIT 1
                    ];

                    customerId = MercuryService.createCustomer(opp.Account, primaryContact);

                    accountsToUpdate.add(new Account(
                        Id = opp.AccountId,
                        Mercury_Customer_Id__c = customerId,
                        Mercury_Sync_Status__c = 'Synced'
                    ));
                }

                // Create invoice
                MercuryService.MercuryInvoiceResult result = MercuryService.createInvoice(opp, customerId);

                oppsToUpdate.add(new Opportunity(
                    Id = opp.Id,
                    Mercury_Invoice_Id__c = result.invoiceId,
                    Mercury_Invoice_Status__c = result.status,
                    Mercury_Invoice_URL__c = result.invoiceUrl
                ));

            } catch (Exception e) {
                System.debug('Error processing invoice for Opp ' + opp.Id + ': ' + e.getMessage());
            }
        }

        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }
        if (!oppsToUpdate.isEmpty()) {
            update oppsToUpdate;
        }
    }
}
```

#### Scheduled Job to Check Invoice Status

```apex
public class MercuryInvoiceStatusChecker implements Schedulable {

    public void execute(SchedulableContext sc) {
        System.enqueueJob(new MercuryInvoiceStatusQueueable());
    }

    public static void scheduleHourly() {
        String cronExp = '0 0 * * * ?'; // Every hour
        System.schedule('Mercury Invoice Status Check', cronExp, new MercuryInvoiceStatusChecker());
    }
}

public class MercuryInvoiceStatusQueueable implements Queueable, Database.AllowsCallouts {

    public void execute(QueueableContext context) {
        List<Opportunity> oppsWithInvoices = [
            SELECT Id, Mercury_Invoice_Id__c, Mercury_Invoice_Status__c, StageName
            FROM Opportunity
            WHERE Mercury_Invoice_Id__c != null
            AND Mercury_Invoice_Status__c NOT IN ('paid', 'cancelled')
            AND StageName != 'Closed Won'
            AND StageName != 'Closed Lost'
            LIMIT 50
        ];

        List<Opportunity> oppsToUpdate = new List<Opportunity>();

        for (Opportunity opp : oppsWithInvoices) {
            try {
                String status = MercuryService.getInvoiceStatus(opp.Mercury_Invoice_Id__c);

                Opportunity oppUpdate = new Opportunity(
                    Id = opp.Id,
                    Mercury_Invoice_Status__c = status
                );

                // Auto close won when paid
                if (status == 'paid') {
                    oppUpdate.StageName = 'Closed Won';
                }

                oppsToUpdate.add(oppUpdate);

            } catch (Exception e) {
                System.debug('Error checking invoice status: ' + e.getMessage());
            }
        }

        if (!oppsToUpdate.isEmpty()) {
            update oppsToUpdate;
        }
    }
}
```

## Setup Instructions

### 1. Mercury Setup

1. Sign up for Mercury at https://mercury.com if you don't have an account
2. Upgrade to Plus ($29.90/mo) or Pro ($299/mo) plan for API access
3. Generate an API token at https://app.mercury.com/settings/tokens
   - Select "Custom" token type
   - Enable scopes: `ar:customers:read`, `ar:customers:write`, `ar:invoices:read`, `ar:invoices:write`
4. If using Read/Write token, whitelist your Salesforce org's IP addresses

### 2. Salesforce Setup

1. **Create Custom Fields**
   - Add fields listed above to Account and Opportunity objects

2. **Create Named Credential**
   - Setup > Named Credentials > New
   - Label: Mercury API
   - Name: Mercury_API
   - URL: https://api.mercury.com
   - Identity Type: Named Principal
   - Authentication Protocol: Custom Header
   - Header Name: Authorization
   - Header Value: Bearer YOUR_TOKEN_HERE

3. **Deploy Apex Classes**
   - MercuryService.cls
   - MercuryInvoiceHandler.cls
   - MercuryInvoiceStatusChecker.cls
   - MercuryInvoiceStatusQueueable.cls
   - OpportunityTrigger.trigger

4. **Add Remote Site Setting**
   - Setup > Remote Site Settings > New
   - Remote Site Name: Mercury_API
   - Remote Site URL: https://api.mercury.com

5. **Schedule the Status Checker**
   ```apex
   MercuryInvoiceStatusChecker.scheduleHourly();
   ```

## Testing

### Test in Mercury Sandbox

Mercury doesn't have a traditional sandbox, but you can:
1. Create test customers and invoices with small amounts
2. Use the API to immediately cancel test invoices
3. Mark invoices as paid manually in Mercury UI for testing

### Apex Test Class

```apex
@isTest
private class MercuryServiceTest {

    @isTest
    static void testCreateInvoice() {
        // Setup test data
        Account acc = new Account(
            Name = 'Test Account',
            Mercury_Customer_Id__c = 'test_customer_123'
        );
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = acc.Id,
            Amount = 1000,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        // Mock the callout
        Test.setMock(HttpCalloutMock.class, new MercuryMockResponse());

        Test.startTest();
        opp.StageName = 'Invoice';
        update opp;
        Test.stopTest();

        // Verify results
        opp = [SELECT Mercury_Invoice_Id__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertNotEquals(null, opp.Mercury_Invoice_Id__c);
    }
}

public class MercuryMockResponse implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setStatusCode(201);
        res.setBody('{"id": "inv_test123", "status": "sent", "invoiceUrl": "https://pay.mercury.com/test"}');
        return res;
    }
}
```

## Error Handling

Common API errors to handle:
- `400` - Bad request (invalid data)
- `401` - Unauthorized (invalid/expired token)
- `403` - Forbidden (no subscription or insufficient permissions)
- `404` - Not found (invalid customer/invoice ID)
- `429` - Rate limited

## Resources

- [Mercury API Documentation](https://docs.mercury.com/reference)
- [Mercury Invoicing API Reference](https://docs.mercury.com/reference/accounts_receivable)
- [Mercury Pricing](https://mercury.com/pricing)
- [Salesforce Named Credentials](https://help.salesforce.com/s/articleView?id=sf.named_credentials_about.htm)

## License

MIT
