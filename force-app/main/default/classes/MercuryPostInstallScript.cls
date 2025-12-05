/**
 * Post-install script that runs after package installation
 * Automatically schedules the Mercury Invoice Status Checker job
 */
global class MercuryPostInstallScript implements InstallHandler {

    global void onInstall(InstallContext context) {
        // Schedule the status checker if not already scheduled
        scheduleStatusCheckerIfNeeded();
    }

    /**
     * Schedules the hourly status checker job if it doesn't already exist
     */
    public static void scheduleStatusCheckerIfNeeded() {
        String jobName = 'Mercury Invoice Status Check';

        // Check if job already exists
        List<CronTrigger> existingJobs = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName
            LIMIT 1
        ];

        if (existingJobs.isEmpty()) {
            // Schedule hourly at minute 0
            String cronExp = '0 0 * * * ?';
            try {
                System.schedule(jobName, cronExp, new MercuryInvoiceStatusChecker());
            } catch (Exception e) {
                // Log error but don't fail installation
                System.debug(LoggingLevel.ERROR, 'Failed to schedule Mercury status checker: ' + e.getMessage());
            }
        }
    }
}
