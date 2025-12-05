/**
 * Test class for status synchronization functionality
 * Tests the scheduled job and status update scenarios
 */
@isTest
private class MercuryStatusSyncTest {

    @TestSetup
    static void setup() {
        Account acc = new Account(
            Name = 'Test Account',
            Mercury_Customer_Id__c = 'cust_test123'
        );
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = acc.Id,
            Amount = 1000,
            StageName = 'Invoice',
            CloseDate = Date.today().addDays(30),
            Mercury_Invoice_Id__c = 'inv_test123',
            Mercury_Invoice_Status__c = 'Sent'
        );
        insert opp;
    }

    @isTest
    static void testStatusSync_PaidClosesWon() {
        Test.setMock(HttpCalloutMock.class, MercuryMockFactory.getInvoiceStatusPaid());

        Test.startTest();
        System.enqueueJob(new MercuryInvoiceStatusQueueable());
        Test.stopTest();

        Opportunity opp = [SELECT Id, StageName, Mercury_Invoice_Status__c FROM Opportunity LIMIT 1];
        System.assertEquals('Closed Won', opp.StageName, 'Paid invoice should close opportunity as Won');
        System.assertEquals('Paid', opp.Mercury_Invoice_Status__c, 'Status should be Paid');
    }

    @isTest
    static void testStatusSync_OverdueStaysOpen() {
        Test.setMock(HttpCalloutMock.class, MercuryMockFactory.getInvoiceStatusOverdue());

        Test.startTest();
        System.enqueueJob(new MercuryInvoiceStatusQueueable());
        Test.stopTest();

        Opportunity opp = [SELECT Id, StageName, Mercury_Invoice_Status__c FROM Opportunity LIMIT 1];
        System.assertEquals('Invoice', opp.StageName, 'Overdue invoice should not change stage');
        System.assertEquals('Overdue', opp.Mercury_Invoice_Status__c, 'Status should be Overdue');
    }

    @isTest
    static void testStatusSync_ViewedStaysOpen() {
        Test.setMock(HttpCalloutMock.class, MercuryMockFactory.getInvoiceStatusViewed());

        Test.startTest();
        System.enqueueJob(new MercuryInvoiceStatusQueueable());
        Test.stopTest();

        Opportunity opp = [SELECT Id, StageName, Mercury_Invoice_Status__c FROM Opportunity LIMIT 1];
        System.assertEquals('Invoice', opp.StageName, 'Viewed invoice should not change stage');
        System.assertEquals('Viewed', opp.Mercury_Invoice_Status__c, 'Status should be Viewed');
    }

    @isTest
    static void testStatusSync_ApiError_RecordUpdatedWithError() {
        Test.setMock(HttpCalloutMock.class, MercuryMockFactory.serverError());

        Test.startTest();
        System.enqueueJob(new MercuryInvoiceStatusQueueable());
        Test.stopTest();

        Opportunity opp = [SELECT Id, StageName, Mercury_Invoice_Status__c, Mercury_Error_Message__c, Mercury_Last_Sync_Attempt__c
                          FROM Opportunity LIMIT 1];
        System.assertEquals('Invoice', opp.StageName, 'Stage should remain unchanged on error');
        System.assertNotEquals(null, opp.Mercury_Error_Message__c, 'Error message should be populated');
        System.assertNotEquals(null, opp.Mercury_Last_Sync_Attempt__c, 'Last sync attempt should be populated');
    }

    @isTest
    static void testScheduleHourly() {
        Test.startTest();
        String jobId = MercuryInvoiceStatusChecker.scheduleHourly();
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Job should be scheduled');

        // Verify job exists
        List<CronTrigger> jobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = 'Mercury Invoice Status Check'];
        System.assertEquals(1, jobs.size(), 'One scheduled job should exist');

        // Clean up
        MercuryInvoiceStatusChecker.unschedule('Mercury Invoice Status Check');
    }

    @isTest
    static void testSkipAlreadyPaidInvoices() {
        // Update opportunity to already be Paid
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        opp.Mercury_Invoice_Status__c = 'Paid';
        opp.StageName = 'Closed Won';
        update opp;

        Test.setMock(HttpCalloutMock.class, MercuryMockFactory.getInvoiceStatusPaid());

        Test.startTest();
        System.enqueueJob(new MercuryInvoiceStatusQueueable());
        Test.stopTest();

        // Verify no changes were made (query filter excludes already paid)
        opp = [SELECT Id, Mercury_Last_Sync_Attempt__c FROM Opportunity LIMIT 1];
        System.assertEquals(null, opp.Mercury_Last_Sync_Attempt__c, 'Already paid invoices should be skipped');
    }
}
