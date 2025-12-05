/**
 * Exception thrown for Mercury API errors that can be retried (429, 5xx)
 */
public class MercuryRetryableException extends Exception {}
