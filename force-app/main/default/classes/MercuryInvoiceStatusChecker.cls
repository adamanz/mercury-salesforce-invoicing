/**
 * Schedulable class to check invoice statuses
 * Mercury does not support webhooks, so polling is required
 */
public class MercuryInvoiceStatusChecker implements Schedulable {

    public void execute(SchedulableContext sc) {
        System.enqueueJob(new MercuryInvoiceStatusQueueable());
    }

    /**
     * Schedule the job to run hourly
     */
    public static String scheduleHourly() {
        String cronExp = '0 0 * * * ?'; // Every hour at minute 0
        return System.schedule('Mercury Invoice Status Check', cronExp, new MercuryInvoiceStatusChecker());
    }

    /**
     * Schedule the job to run every 15 minutes (for high volume)
     */
    public static String scheduleQuarterly() {
        String cronExp = '0 0,15,30,45 * * * ?'; // Every 15 minutes
        return System.schedule('Mercury Invoice Status Check - Frequent', cronExp, new MercuryInvoiceStatusChecker());
    }

    /**
     * Remove the scheduled job
     * @param jobName The name of the scheduled job to remove
     */
    public static void unschedule(String jobName) {
        for (CronTrigger ct : [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName
        ]) {
            System.abortJob(ct.Id);
        }
    }
}
