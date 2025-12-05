# Mercury Salesforce Invoicing

[![Salesforce API](https://img.shields.io/badge/Salesforce%20API-v59.0-blue)](https://developer.salesforce.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Apex Tests](https://img.shields.io/badge/Apex%20Tests-25%20Passing-brightgreen)](force-app/main/default/classes)

Generate and send invoices via Mercury's Accounts Receivable API directly from Salesforce Opportunities. Automatically close opportunities as Won when invoices are paid.

<a href="https://login.salesforce.com/packaging/installPackage.apexp?p0=04tfo000001FYOzAAO">
  <img src="https://img.shields.io/badge/Install%20Package-Production-blue?style=for-the-badge&logo=salesforce" alt="Install in Production"/>
</a>
&nbsp;
<a href="https://test.salesforce.com/packaging/installPackage.apexp?p0=04tfo000001FYOzAAO">
  <img src="https://img.shields.io/badge/Install%20Package-Sandbox-orange?style=for-the-badge&logo=salesforce" alt="Install in Sandbox"/>
</a>

---

## Features

- **Automatic Customer Sync** - Creates Mercury customers from Salesforce Account/Contact data
- **Invoice Generation** - Creates and sends invoices when Opportunities reach the configured trigger stage
- **Status Polling** - Scheduled job polls Mercury for invoice status updates (Mercury doesn't support webhooks)
- **Auto-Close Won** - Automatically sets Opportunity to "Closed Won" when invoice is paid
- **Error Tracking** - Comprehensive error logging with retry logic for transient failures
- **Pre-configured Components** - Named Credential, Remote Site Setting, and Permission Set included
- **Setup Flow Wizard** - Guided configuration wizard for easy setup
- **Custom Metadata Settings** - Configure invoice behavior without code changes
- **Auto-Scheduling** - Post-install script automatically schedules the status checker

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
- **Production/Developer**: https://login.salesforce.com/packaging/installPackage.apexp?p0=04tfo000001FYOzAAO
- **Sandbox**: https://test.salesforce.com/packaging/installPackage.apexp?p0=04tfo000001FYOzAAO

### Option 2: Deploy from Source

```bash
# Clone the repository
git clone https://github.com/adamanz/mercury-salesforce-invoicing.git
cd mercury-salesforce-invoicing

# Deploy to your org
sf project deploy start --target-org your-org-alias
```

## Quick Start (2 Steps)

The package includes pre-configured components and **automatically schedules the status checker** on install.

### Step 1: Add Your Mercury Token

1. Go to **Setup → Named Credentials → Named Credentials**
2. Click **Mercury_API** (already created by the package)
3. Click **Edit** and add a Custom Header:
   - Header Name: `Authorization`
   - Header Value: `Bearer secret-token:YOUR_MERCURY_TOKEN`
4. Save

### Step 2: Assign Permission Set

1. Go to **Setup → Permission Sets**
2. Click **Mercury API Access**
3. Click **Manage Assignments → Add Assignment**
4. Select users who need to create invoices

**That's it!** The integration is ready to use. The status checker is automatically scheduled hourly.

---

## Additional Setup (Optional)

### Run Setup Wizard

For guided configuration, run the **Mercury Setup Wizard** flow:
1. Go to **Setup → Flows**
2. Find **Mercury Setup Wizard**
3. Click **Run** to configure settings interactively

### Customize Settings via Custom Metadata

Go to **Setup → Custom Metadata Types → Mercury Settings → Manage Records → Default**:

| Setting | Default | Description |
|---------|---------|-------------|
| Invoice Due Days | 30 | Days until invoice is due |
| Invoice Trigger Stage | Invoice | Opportunity stage that triggers invoicing |
| Send Email On Create | true | Send invoice email automatically |
| Auto Close On Payment | true | Close Opportunity as Won when paid |
| Enable Credit Card | true | Accept credit card payments |
| Enable ACH | true | Accept ACH bank transfers |
| Enable Wire | true | Accept wire transfers |
| Polling Frequency Minutes | 60 | How often to check invoice status |

### Add Custom Stage to Opportunity

If using a custom trigger stage (default is "Invoice"):
1. Go to **Setup → Object Manager → Opportunity → Fields → Stage**
2. Add your stage name as a picklist value
3. Update **Invoice Trigger Stage** in Mercury Settings

### Configure IP Allowlist (Required for Write Tokens)

Add your Salesforce org's outbound IPs to Mercury:
1. Find IPs at **Setup → Company Information**
2. Add them at [Mercury Token Settings](https://app.mercury.com/settings/tokens)

## What's Included

### Pre-Configured Components
| Component | Name | Description |
|-----------|------|-------------|
| Named Credential | `Mercury_API` | Pre-configured for Mercury API (just add your token) |
| Remote Site Setting | `Mercury_API` | Allows callouts to api.mercury.com |
| Permission Set | `Mercury API Access` | Controls who can use the integration |
| Custom Metadata | `Mercury_Settings__mdt` | Configurable settings for invoice behavior |
| Flow | `Mercury Setup Wizard` | Guided setup wizard |

### Custom Fields

**Account:**
| Field | Type | Description |
|-------|------|-------------|
| `Mercury_Customer_Id__c` | Text(50) | Mercury customer ID |
| `Mercury_Sync_Status__c` | Picklist | Pending, Synced, Error |
| `Mercury_Error_Message__c` | Text(255) | Last error message |
| `Mercury_Last_Sync_Attempt__c` | DateTime | Last sync timestamp |

**Opportunity:**
| Field | Type | Description |
|-------|------|-------------|
| `Mercury_Invoice_Id__c` | Text(50) | Mercury invoice ID |
| `Mercury_Invoice_Status__c` | Picklist | Draft, Sent, Viewed, Paid, Overdue, Cancelled |
| `Mercury_Invoice_URL__c` | URL | Link to Mercury payment page |
| `Mercury_Error_Message__c` | Text(255) | Last error message |
| `Mercury_Last_Sync_Attempt__c` | DateTime | Last sync timestamp |

### Apex Classes
- `MercuryService` - Core API service
- `MercuryInvoiceHandler` - Queueable for invoice creation
- `MercuryInvoiceStatusChecker` - Schedulable for polling
- `MercuryInvoiceStatusQueueable` - Queueable for status checks
- `MercurySettings` - Settings helper class
- `MercuryPostInstallScript` - Auto-schedules status checker on install
- `MercuryRetryableException` - For retryable errors (429, 5xx)
- `MercuryNonRetryableException` - For non-retryable errors (4xx)

### Test Classes (25 tests, 100% pass rate)
- `MercuryServiceTest` - Unit tests for service
- `MercuryStatusSyncTest` - Status sync tests
- `MercuryIntegrationFlowTest` - End-to-end tests
- `MercuryPostInstallScriptTest` - Post-install script tests
- `MercuryMockFactory` - Mock response factory

### Trigger
- `OpportunityTrigger` - Fires on stage change to configured trigger stage

## Usage

1. Create an **Opportunity** with an associated **Account** and **Contact** (Contact must have email)
2. Change the Opportunity Stage to **"Invoice"** (or your configured trigger stage)
3. The integration will:
   - Create a Mercury customer (if not exists)
   - Generate and send an invoice
   - Update the Opportunity with invoice details
4. When the customer pays:
   - Scheduled job detects "paid" status
   - Opportunity automatically moves to "Closed Won"

## Error Handling

| Code | Meaning | Retryable | Action |
|------|---------|-----------|--------|
| 400 | Bad Request | No | Check required fields |
| 401 | Unauthorized | No | Rotate token |
| 403 | Forbidden | No | Check Mercury subscription |
| 404 | Not Found | No | Verify customer/invoice ID |
| 429 | Rate Limited | Yes | Auto-retry with backoff |
| 5xx | Server Error | Yes | Auto-retry with backoff |

Errors are logged to `Mercury_Error_Message__c` on the Account or Opportunity record.

## Testing

Run the test suite:

```bash
sf apex run test --class-names MercuryServiceTest --class-names MercuryStatusSyncTest --class-names MercuryIntegrationFlowTest --result-format human --wait 10
```

**Note:** Mercury doesn't provide a sandbox. For testing:
- Create test invoices with small amounts ($1)
- Cancel immediately via API or Mercury UI
- Use internal email addresses for test customers

## Resources

- [Mercury API Documentation](https://docs.mercury.com/reference)
- [Mercury Invoicing API](https://docs.mercury.com/reference/accounts_receivable)
- [Mercury Pricing](https://mercury.com/pricing)
- [Salesforce Named Credentials](https://help.salesforce.com/s/articleView?id=sf.named_credentials_about.htm)

## License

MIT
