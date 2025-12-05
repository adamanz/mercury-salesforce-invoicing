/**
 * Test class for MercuryService
 * Covers success and error scenarios for API calls
 */
@isTest
private class MercuryServiceTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Test Account',
            BillingStreet = '123 Test St',
            BillingCity = 'San Francisco',
            BillingState = 'CA',
            BillingPostalCode = '94105',
            BillingCountry = 'USA'
        );
        insert acc;

        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com',
            AccountId = acc.Id
        );
        insert con;

        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = acc.Id,
            Amount = 1000,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
    }

    @isTest
    static void testCreateCustomer_Success() {
        Account acc = [SELECT Id, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry FROM Account LIMIT 1];
        Contact con = [SELECT Id, Email FROM Contact LIMIT 1];

        Test.setMock(HttpCalloutMock.class, MercuryMockFactory.createCustomerSuccess());

        Test.startTest();
        String customerId = MercuryService.createCustomer(acc, con);
        Test.stopTest();

        System.assertEquals('cust_test123', customerId, 'Customer ID should match mock response');
    }

    @isTest
    static void testCreateCustomer_Unauthorized() {
        Account acc = [SELECT Id, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry FROM Account LIMIT 1];
        Contact con = [SELECT Id, Email FROM Contact LIMIT 1];

        Test.setMock(HttpCalloutMock.class, MercuryMockFactory.unauthorized());

        Test.startTest();
        try {
            MercuryService.createCustomer(acc, con);
            System.assert(false, 'Expected exception');
        } catch (MercuryNonRetryableException e) {
            System.assert(e.getMessage().contains('401'), 'Error should contain status code');
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateInvoice_Success() {
        Account acc = [SELECT Id, Name, Mercury_Customer_Id__c FROM Account LIMIT 1];
        acc.Mercury_Customer_Id__c = 'cust_test123';
        update acc;

        Opportunity opp = [SELECT Id, Name, Amount, AccountId FROM Opportunity LIMIT 1];

        Test.setMock(HttpCalloutMock.class, MercuryMockFactory.createInvoiceSuccess());

        Test.startTest();
        MercuryService.MercuryInvoiceResult result = MercuryService.createInvoice(opp, acc.Mercury_Customer_Id__c);
        Test.stopTest();

        System.assertEquals('inv_test123', result.invoiceId, 'Invoice ID should match mock');
        System.assertEquals('sent', result.status, 'Status should match mock');
        System.assertEquals('https://pay.mercury.com/inv_test123', result.invoiceUrl, 'URL should match mock');
    }

    @isTest
    static void testCreateInvoice_RateLimited() {
        Account acc = [SELECT Id, Name, Mercury_Customer_Id__c FROM Account LIMIT 1];
        acc.Mercury_Customer_Id__c = 'cust_test123';
        update acc;

        Opportunity opp = [SELECT Id, Name, Amount, AccountId FROM Opportunity LIMIT 1];

        Test.setMock(HttpCalloutMock.class, MercuryMockFactory.rateLimited());

        Test.startTest();
        try {
            MercuryService.createInvoice(opp, acc.Mercury_Customer_Id__c);
            System.assert(false, 'Expected exception for rate limit');
        } catch (MercuryRetryableException e) {
            System.assert(e.getMessage().contains('429'), 'Error should contain rate limit code');
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateInvoice_Forbidden() {
        Account acc = [SELECT Id, Name, Mercury_Customer_Id__c FROM Account LIMIT 1];
        acc.Mercury_Customer_Id__c = 'cust_test123';
        update acc;

        Opportunity opp = [SELECT Id, Name, Amount, AccountId FROM Opportunity LIMIT 1];

        Test.setMock(HttpCalloutMock.class, MercuryMockFactory.forbidden());

        Test.startTest();
        try {
            MercuryService.createInvoice(opp, acc.Mercury_Customer_Id__c);
            System.assert(false, 'Expected exception for forbidden');
        } catch (MercuryNonRetryableException e) {
            System.assert(e.getMessage().contains('403'), 'Error should contain forbidden code');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetInvoiceStatus_Success() {
        Test.setMock(HttpCalloutMock.class, MercuryMockFactory.getInvoiceStatusPaid());

        Test.startTest();
        String status = MercuryService.getInvoiceStatus('inv_test123');
        Test.stopTest();

        System.assertEquals('paid', status, 'Status should match mock');
    }

    @isTest
    static void testGetInvoiceStatus_NotFound() {
        Test.setMock(HttpCalloutMock.class, MercuryMockFactory.notFound());

        Test.startTest();
        try {
            MercuryService.getInvoiceStatus('inv_nonexistent');
            System.assert(false, 'Expected exception for not found');
        } catch (MercuryNonRetryableException e) {
            System.assert(e.getMessage().contains('404'), 'Error should contain not found code');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetInvoiceStatus_ServerError() {
        Test.setMock(HttpCalloutMock.class, MercuryMockFactory.serverError());

        Test.startTest();
        try {
            MercuryService.getInvoiceStatus('inv_test123');
            System.assert(false, 'Expected exception for server error');
        } catch (MercuryRetryableException e) {
            System.assert(e.getMessage().contains('500'), 'Error should contain server error code');
        }
        Test.stopTest();
    }
}
