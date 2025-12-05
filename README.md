# Mercury Salesforce Invoicing

[![Salesforce API](https://img.shields.io/badge/Salesforce%20API-v59.0-blue)](https://developer.salesforce.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Apex Tests](https://img.shields.io/badge/Apex%20Tests-22%20Passing-brightgreen)](force-app/main/default/classes)

Generate and send invoices via Mercury's Accounts Receivable API directly from Salesforce Opportunities. Automatically close opportunities as Won when invoices are paid.

<a href="https://login.salesforce.com/packaging/installPackage.apexp?p0=04tfo000001FYK9AAO">
  <img src="https://img.shields.io/badge/Install%20Package-Production-blue?style=for-the-badge&logo=salesforce" alt="Install in Production"/>
</a>
&nbsp;
<a href="https://test.salesforce.com/packaging/installPackage.apexp?p0=04tfo000001FYK9AAO">
  <img src="https://img.shields.io/badge/Install%20Package-Sandbox-orange?style=for-the-badge&logo=salesforce" alt="Install in Sandbox"/>
</a>

---

## Features

- **Automatic Customer Sync** - Creates Mercury customers from Salesforce Account/Contact data
- **Invoice Generation** - Creates and sends invoices when Opportunities reach the "Invoice" stage
- **Status Polling** - Scheduled job polls Mercury for invoice status updates (Mercury doesn't support webhooks)
- **Auto-Close Won** - Automatically sets Opportunity to "Closed Won" when invoice is paid
- **Error Tracking** - Comprehensive error logging with retry logic for transient failures

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Opportunity   │────▶│  Apex Trigger   │────▶│  Mercury API    │
│  Stage Change   │     │  (Queueable)    │     │  Callout        │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Opportunity   │◀────│  Scheduled Apex │◀────│  Polling        │
│   Closed Won    │     │  (Hourly)       │     │  (Status Check) │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

## Prerequisites

- **Mercury Account** with Plus ($29.90/mo) or Pro ($299/mo) plan for API access
- **API Token** from [Mercury Settings](https://app.mercury.com/settings/tokens) with scopes:
  - `ar:customers:read`, `ar:customers:write`
  - `ar:invoices:read`, `ar:invoices:write`
- **Salesforce** org (Production, Developer, or Sandbox)

## Installation

### Option 1: Install Package (Recommended)

Click the button above or use these links:
- **Production/Developer**: https://login.salesforce.com/packaging/installPackage.apexp?p0=04tfo000001FYK9AAO
- **Sandbox**: https://test.salesforce.com/packaging/installPackage.apexp?p0=04tfo000001FYK9AAO

### Option 2: Deploy from Source

```bash
# Clone the repository
git clone https://github.com/adamanz/mercury-salesforce-invoicing.git
cd mercury-salesforce-invoicing

# Deploy to your org
sf project deploy start --target-org your-org-alias
```

## Post-Installation Setup

### 1. Configure Named Credential

1. Go to **Setup → Named Credentials → External Credentials**
2. Click **New External Credential**
3. Configure:
   - Label: `Mercury_External`
   - Authentication Protocol: `Custom`
4. Add a Principal with:
   - Parameter Name: `Authorization`
   - Value: `Bearer secret-token:YOUR_MERCURY_TOKEN`
5. Create Named Credential pointing to this External Credential

**Or use Legacy Named Credential:**
1. Go to **Setup → Named Credentials → Legacy**
2. Create new with:
   - Label: `Mercury_API`
   - URL: `https://api.mercury.com`
   - Authentication: Custom Header
   - Header: `Authorization` = `Bearer secret-token:YOUR_TOKEN`

### 2. Add "Invoice" Stage to Opportunity

If you don't have an "Invoice" stage in your Sales Process:
1. Go to **Setup → Object Manager → Opportunity → Fields → Stage**
2. Add "Invoice" as a picklist value

### 3. Schedule the Status Checker

Run in **Developer Console → Anonymous Apex**:

```apex
MercuryInvoiceStatusChecker.scheduleHourly();
```

### 4. Configure IP Allowlist (Required for Write Tokens)

Add your Salesforce org's outbound IPs to Mercury's token allowlist:
1. Find your Salesforce IPs at **Setup → Company Information**
2. Add them at [Mercury Token Settings](https://app.mercury.com/settings/tokens)

## Custom Fields

### Account
| Field | Type | Description |
|-------|------|-------------|
| `Mercury_Customer_Id__c` | Text(50) | Mercury customer ID |
| `Mercury_Sync_Status__c` | Picklist | Pending, Synced, Error |
| `Mercury_Error_Message__c` | Text(255) | Last error message |
| `Mercury_Last_Sync_Attempt__c` | DateTime | Last sync timestamp |

### Opportunity
| Field | Type | Description |
|-------|------|-------------|
| `Mercury_Invoice_Id__c` | Text(50) | Mercury invoice ID |
| `Mercury_Invoice_Status__c` | Picklist | Draft, Sent, Viewed, Paid, Overdue, Cancelled |
| `Mercury_Invoice_URL__c` | URL | Link to Mercury payment page |
| `Mercury_Error_Message__c` | Text(255) | Last error message |
| `Mercury_Last_Sync_Attempt__c` | DateTime | Last sync timestamp |

## Usage

1. Create an **Opportunity** with an associated **Account** and **Contact** (Contact must have email)
2. Change the Opportunity Stage to **"Invoice"**
3. The integration will:
   - Create a Mercury customer (if not exists)
   - Generate and send an invoice
   - Update the Opportunity with invoice details
4. When the customer pays:
   - Scheduled job detects "paid" status
   - Opportunity automatically moves to "Closed Won"

## API Reference

### Mercury Endpoints Used

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/ar/customers` | Create customer |
| POST | `/ar/invoices` | Create & send invoice |
| GET | `/ar/invoices/{id}` | Get invoice status |

### Error Handling

| Code | Meaning | Retryable |
|------|---------|-----------|
| 400 | Bad Request | No |
| 401 | Unauthorized | No - rotate token |
| 403 | Forbidden | No - check subscription |
| 404 | Not Found | No |
| 429 | Rate Limited | Yes |
| 5xx | Server Error | Yes |

## Testing

Run the test suite:

```bash
sf apex run test --class-names MercuryServiceTest --class-names MercuryStatusSyncTest --class-names MercuryIntegrationFlowTest --result-format human --wait 10
```

**Note:** Mercury doesn't provide a sandbox. For testing:
- Create test invoices with small amounts ($1)
- Cancel immediately via API or Mercury UI
- Use internal email addresses for test customers

## Components

### Apex Classes
- `MercuryService` - Core API service
- `MercuryInvoiceHandler` - Queueable for invoice creation
- `MercuryInvoiceStatusChecker` - Schedulable for polling
- `MercuryInvoiceStatusQueueable` - Queueable for status checks
- `MercuryRetryableException` - For retryable errors
- `MercuryNonRetryableException` - For non-retryable errors

### Test Classes
- `MercuryServiceTest` - Unit tests for service
- `MercuryStatusSyncTest` - Status sync tests
- `MercuryIntegrationFlowTest` - End-to-end tests
- `MercuryMockFactory` - Mock response factory

### Triggers
- `OpportunityTrigger` - Fires on stage change to "Invoice"

## Resources

- [Mercury API Documentation](https://docs.mercury.com/reference)
- [Mercury Invoicing API](https://docs.mercury.com/reference/accounts_receivable)
- [Mercury Pricing](https://mercury.com/pricing)
- [Salesforce Named Credentials](https://help.salesforce.com/s/articleView?id=sf.named_credentials_about.htm)

## License

MIT
