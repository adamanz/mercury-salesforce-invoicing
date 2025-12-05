/**
 * Exception thrown for Mercury API errors that should not be retried (400, 401, 403, 404)
 */
public class MercuryNonRetryableException extends Exception {}
