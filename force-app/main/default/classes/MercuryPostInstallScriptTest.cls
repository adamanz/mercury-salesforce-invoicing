/**
 * Test class for MercuryPostInstallScript
 */
@isTest
private class MercuryPostInstallScriptTest {

    @isTest
    static void testPostInstallSchedulesJob() {
        // Verify no job exists initially
        List<CronTrigger> jobsBefore = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = 'Mercury Invoice Status Check'
        ];
        System.assertEquals(0, jobsBefore.size(), 'No job should exist before install');

        Test.startTest();
        MercuryPostInstallScript.scheduleStatusCheckerIfNeeded();
        Test.stopTest();

        // Verify job was created
        List<CronTrigger> jobsAfter = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = 'Mercury Invoice Status Check'
        ];
        System.assertEquals(1, jobsAfter.size(), 'Job should be scheduled after install');

        // Clean up
        System.abortJob(jobsAfter[0].Id);
    }

    @isTest
    static void testPostInstallDoesNotDuplicateJob() {
        // Schedule job first
        String cronExp = '0 0 * * * ?';
        System.schedule('Mercury Invoice Status Check', cronExp, new MercuryInvoiceStatusChecker());

        Test.startTest();
        // Call again - should not create duplicate
        MercuryPostInstallScript.scheduleStatusCheckerIfNeeded();
        Test.stopTest();

        // Verify only one job exists
        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = 'Mercury Invoice Status Check'
        ];
        System.assertEquals(1, jobs.size(), 'Should not create duplicate job');

        // Clean up
        System.abortJob(jobs[0].Id);
    }

    @isTest
    static void testInstallHandler() {
        Test.startTest();
        MercuryPostInstallScript script = new MercuryPostInstallScript();
        Test.testInstall(script, null);
        Test.stopTest();

        // Verify job was created
        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = 'Mercury Invoice Status Check'
        ];
        System.assertEquals(1, jobs.size(), 'Job should be scheduled via install handler');

        // Clean up
        System.abortJob(jobs[0].Id);
    }
}
