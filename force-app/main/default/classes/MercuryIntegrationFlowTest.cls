/**
 * Integration test for the full Mercury invoicing flow
 * Tests end-to-end scenarios from Opportunity stage change to invoice creation
 */
@isTest
private class MercuryIntegrationFlowTest {

    @isTest
    static void testFullFlow_NewCustomerAndInvoice() {
        // Setup: Account without Mercury Customer ID
        Account acc = new Account(
            Name = 'New Customer Account',
            BillingStreet = '123 Main St',
            BillingCity = 'San Francisco',
            BillingState = 'CA',
            BillingPostalCode = '94105'
        );
        insert acc;

        Contact con = new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            Email = 'john@example.com',
            AccountId = acc.Id
        );
        insert con;

        Opportunity opp = new Opportunity(
            Name = 'New Deal',
            AccountId = acc.Id,
            Amount = 5000,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        // Mock: First call creates customer, second creates invoice
        Test.setMock(HttpCalloutMock.class, MercuryMockFactory.multiCallMock(
            new List<HttpCalloutMock>{
                MercuryMockFactory.createCustomerSuccess(),
                MercuryMockFactory.createInvoiceSuccess()
            }
        ));

        Test.startTest();
        // Trigger invoice creation by changing stage
        opp.StageName = 'Invoice';
        update opp;
        Test.stopTest();

        // Verify Account got Mercury Customer ID
        acc = [SELECT Id, Mercury_Customer_Id__c, Mercury_Sync_Status__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals('cust_test123', acc.Mercury_Customer_Id__c, 'Account should have Mercury Customer ID');
        System.assertEquals('Synced', acc.Mercury_Sync_Status__c, 'Account sync status should be Synced');

        // Verify Opportunity got Mercury Invoice ID
        opp = [SELECT Id, Mercury_Invoice_Id__c, Mercury_Invoice_Status__c, Mercury_Invoice_URL__c
               FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('inv_test123', opp.Mercury_Invoice_Id__c, 'Opportunity should have Invoice ID');
        System.assertEquals('Sent', opp.Mercury_Invoice_Status__c, 'Invoice status should be Sent');
        System.assertEquals('https://pay.mercury.com/inv_test123', opp.Mercury_Invoice_URL__c, 'Invoice URL should be set');
    }

    @isTest
    static void testFullFlow_ExistingCustomer() {
        // Setup: Account with existing Mercury Customer ID
        Account acc = new Account(
            Name = 'Existing Customer Account',
            Mercury_Customer_Id__c = 'cust_existing123',
            Mercury_Sync_Status__c = 'Synced'
        );
        insert acc;

        Contact con = new Contact(
            FirstName = 'Jane',
            LastName = 'Smith',
            Email = 'jane@example.com',
            AccountId = acc.Id
        );
        insert con;

        Opportunity opp = new Opportunity(
            Name = 'Repeat Deal',
            AccountId = acc.Id,
            Amount = 3000,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        // Mock: Only invoice creation needed
        Test.setMock(HttpCalloutMock.class, MercuryMockFactory.createInvoiceSuccess());

        Test.startTest();
        opp.StageName = 'Invoice';
        update opp;
        Test.stopTest();

        // Verify Opportunity got Mercury Invoice ID
        opp = [SELECT Id, Mercury_Invoice_Id__c, Mercury_Invoice_Status__c
               FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('inv_test123', opp.Mercury_Invoice_Id__c, 'Opportunity should have Invoice ID');
        System.assertEquals('Sent', opp.Mercury_Invoice_Status__c, 'Invoice status should be Sent');
    }

    @isTest
    static void testFullFlow_NoContactWithEmail() {
        // Setup: Account without any contact with email
        Account acc = new Account(
            Name = 'No Email Customer'
        );
        insert acc;

        // Contact without email
        Contact con = new Contact(
            FirstName = 'No',
            LastName = 'Email',
            AccountId = acc.Id
        );
        insert con;

        Opportunity opp = new Opportunity(
            Name = 'Problem Deal',
            AccountId = acc.Id,
            Amount = 1000,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        // No mock needed - should fail before API call
        Test.setMock(HttpCalloutMock.class, MercuryMockFactory.createCustomerSuccess());

        Test.startTest();
        opp.StageName = 'Invoice';
        update opp;
        Test.stopTest();

        // Verify error was logged
        opp = [SELECT Id, Mercury_Invoice_Id__c, Mercury_Error_Message__c
               FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(null, opp.Mercury_Invoice_Id__c, 'No invoice should be created');
        System.assert(opp.Mercury_Error_Message__c.contains('Contact'), 'Error should mention contact issue');
    }

    @isTest
    static void testFullFlow_ApiErrorOnCustomerCreate() {
        // Setup: New account needing customer creation
        Account acc = new Account(
            Name = 'Error Account'
        );
        insert acc;

        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'test@example.com',
            AccountId = acc.Id
        );
        insert con;

        Opportunity opp = new Opportunity(
            Name = 'Error Deal',
            AccountId = acc.Id,
            Amount = 1000,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        // Mock: Customer creation fails
        Test.setMock(HttpCalloutMock.class, MercuryMockFactory.unauthorized());

        Test.startTest();
        opp.StageName = 'Invoice';
        update opp;
        Test.stopTest();

        // Verify error was logged
        opp = [SELECT Id, Mercury_Invoice_Id__c, Mercury_Error_Message__c, Mercury_Last_Sync_Attempt__c
               FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(null, opp.Mercury_Invoice_Id__c, 'No invoice should be created');
        System.assertNotEquals(null, opp.Mercury_Error_Message__c, 'Error message should be populated');
        System.assertNotEquals(null, opp.Mercury_Last_Sync_Attempt__c, 'Last sync attempt should be populated');
    }

    @isTest
    static void testTriggerNotFiredForOtherStageChanges() {
        Account acc = new Account(
            Name = 'Test Account',
            Mercury_Customer_Id__c = 'cust_test123'
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

        // No mock - trigger shouldn't fire
        Test.startTest();
        opp.StageName = 'Qualification';
        update opp;
        Test.stopTest();

        // Verify no invoice was created
        opp = [SELECT Id, Mercury_Invoice_Id__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(null, opp.Mercury_Invoice_Id__c, 'No invoice should be created for non-Invoice stage');
    }

    @isTest
    static void testTriggerNotFiredWhenInvoiceExists() {
        Account acc = new Account(
            Name = 'Test Account',
            Mercury_Customer_Id__c = 'cust_test123'
        );
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = acc.Id,
            Amount = 1000,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Mercury_Invoice_Id__c = 'inv_existing123'
        );
        insert opp;

        // No mock needed - trigger shouldn't fire when invoice exists
        Test.startTest();
        opp.StageName = 'Invoice';
        update opp;
        Test.stopTest();

        // Verify invoice ID wasn't changed
        opp = [SELECT Id, Mercury_Invoice_Id__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('inv_existing123', opp.Mercury_Invoice_Id__c, 'Existing invoice ID should not change');
    }
}
