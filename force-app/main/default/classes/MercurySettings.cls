/**
 * Helper class to access Mercury Settings custom metadata
 * Provides cached access to configuration values with sensible defaults
 */
public class MercurySettings {

    private static Mercury_Settings__mdt cachedSettings;

    /**
     * Get the active settings record (cached)
     */
    public static Mercury_Settings__mdt getSettings() {
        if (cachedSettings == null) {
            List<Mercury_Settings__mdt> settings = [
                SELECT DeveloperName, Invoice_Due_Days__c, Polling_Frequency_Minutes__c,
                       Auto_Close_On_Payment__c, Enable_Credit_Card__c, Enable_ACH__c,
                       Enable_Wire__c, Invoice_Trigger_Stage__c, Send_Email_On_Create__c
                FROM Mercury_Settings__mdt
                WHERE DeveloperName = 'Default'
                LIMIT 1
            ];

            if (!settings.isEmpty()) {
                cachedSettings = settings[0];
            } else {
                // Return defaults if no record exists
                cachedSettings = new Mercury_Settings__mdt(
                    DeveloperName = 'Default',
                    Invoice_Due_Days__c = 30,
                    Polling_Frequency_Minutes__c = 60,
                    Auto_Close_On_Payment__c = true,
                    Enable_Credit_Card__c = true,
                    Enable_ACH__c = true,
                    Enable_Wire__c = true,
                    Invoice_Trigger_Stage__c = 'Invoice',
                    Send_Email_On_Create__c = true
                );
            }
        }
        return cachedSettings;
    }

    /**
     * Get the number of days until invoice due date
     */
    public static Integer getInvoiceDueDays() {
        Decimal days = getSettings().Invoice_Due_Days__c;
        return days != null ? days.intValue() : 30;
    }

    /**
     * Get the polling frequency in minutes
     */
    public static Integer getPollingFrequencyMinutes() {
        Decimal minutes = getSettings().Polling_Frequency_Minutes__c;
        return minutes != null ? minutes.intValue() : 60;
    }

    /**
     * Check if opportunities should auto-close when invoice is paid
     */
    public static Boolean isAutoCloseOnPayment() {
        Boolean value = getSettings().Auto_Close_On_Payment__c;
        return value != null ? value : true;
    }

    /**
     * Check if credit card payments are enabled
     */
    public static Boolean isCreditCardEnabled() {
        Boolean value = getSettings().Enable_Credit_Card__c;
        return value != null ? value : true;
    }

    /**
     * Check if ACH payments are enabled
     */
    public static Boolean isACHEnabled() {
        Boolean value = getSettings().Enable_ACH__c;
        return value != null ? value : true;
    }

    /**
     * Check if wire payments are enabled
     */
    public static Boolean isWireEnabled() {
        Boolean value = getSettings().Enable_Wire__c;
        return value != null ? value : true;
    }

    /**
     * Get the opportunity stage that triggers invoice creation
     */
    public static String getInvoiceTriggerStage() {
        String stage = getSettings().Invoice_Trigger_Stage__c;
        return String.isNotBlank(stage) ? stage : 'Invoice';
    }

    /**
     * Check if invoice email should be sent on creation
     */
    public static Boolean isSendEmailOnCreate() {
        Boolean value = getSettings().Send_Email_On_Create__c;
        return value != null ? value : true;
    }

    /**
     * Clear cached settings (useful for tests)
     */
    @TestVisible
    private static void clearCache() {
        cachedSettings = null;
    }
}
