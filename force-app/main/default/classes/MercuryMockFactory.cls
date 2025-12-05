/**
 * Factory class for creating mock HTTP responses in tests
 * Provides various success and error scenarios for Mercury API calls
 */
@isTest
public class MercuryMockFactory {

    // ============= SUCCESS RESPONSES =============

    public static HttpCalloutMock createCustomerSuccess() {
        return new MercuryMock(201, '{"id": "cust_test123", "name": "Test Customer", "email": "test@example.com"}');
    }

    public static HttpCalloutMock createInvoiceSuccess() {
        return new MercuryMock(201, '{"id": "inv_test123", "status": "sent", "invoiceUrl": "https://pay.mercury.com/inv_test123"}');
    }

    public static HttpCalloutMock getInvoiceStatusPaid() {
        return new MercuryMock(200, '{"id": "inv_test123", "status": "paid"}');
    }

    public static HttpCalloutMock getInvoiceStatusSent() {
        return new MercuryMock(200, '{"id": "inv_test123", "status": "sent"}');
    }

    public static HttpCalloutMock getInvoiceStatusViewed() {
        return new MercuryMock(200, '{"id": "inv_test123", "status": "viewed"}');
    }

    public static HttpCalloutMock getInvoiceStatusOverdue() {
        return new MercuryMock(200, '{"id": "inv_test123", "status": "overdue"}');
    }

    public static HttpCalloutMock getInvoiceStatusCancelled() {
        return new MercuryMock(200, '{"id": "inv_test123", "status": "cancelled"}');
    }

    // ============= ERROR RESPONSES =============

    public static HttpCalloutMock badRequest() {
        return new MercuryMock(400, '{"error": "Invalid request", "message": "Missing required field: email"}');
    }

    public static HttpCalloutMock unauthorized() {
        return new MercuryMock(401, '{"error": "Unauthorized", "message": "Invalid or expired token"}');
    }

    public static HttpCalloutMock forbidden() {
        return new MercuryMock(403, '{"error": "Forbidden", "message": "Subscription required for this endpoint"}');
    }

    public static HttpCalloutMock notFound() {
        return new MercuryMock(404, '{"error": "Not found", "message": "Customer not found"}');
    }

    public static HttpCalloutMock rateLimited() {
        return new MercuryMock(429, '{"error": "Too Many Requests", "message": "Rate limit exceeded"}',
            new Map<String, String>{'Retry-After' => '60'});
    }

    public static HttpCalloutMock serverError() {
        return new MercuryMock(500, '{"error": "Internal Server Error"}');
    }

    public static HttpCalloutMock serviceUnavailable() {
        return new MercuryMock(503, '{"error": "Service Unavailable"}');
    }

    // ============= MULTI-CALL MOCK =============

    /**
     * Creates a mock that returns different responses for sequential calls
     * Useful for testing scenarios like: create customer, then create invoice
     */
    public static HttpCalloutMock multiCallMock(List<HttpCalloutMock> mocks) {
        return new MercuryMultiMock(mocks);
    }

    // ============= BASE MOCK CLASS =============

    public class MercuryMock implements HttpCalloutMock {
        private Integer statusCode;
        private String body;
        private Map<String, String> headers;

        public MercuryMock(Integer statusCode, String body) {
            this(statusCode, body, new Map<String, String>());
        }

        public MercuryMock(Integer statusCode, String body, Map<String, String> headers) {
            this.statusCode = statusCode;
            this.body = body;
            this.headers = headers;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(this.statusCode);
            res.setBody(this.body);
            res.setHeader('Content-Type', 'application/json');
            for (String key : this.headers.keySet()) {
                res.setHeader(key, this.headers.get(key));
            }
            return res;
        }
    }

    // ============= MULTI-CALL MOCK CLASS =============

    public class MercuryMultiMock implements HttpCalloutMock {
        private List<HttpCalloutMock> mocks;
        private Integer callCount = 0;

        public MercuryMultiMock(List<HttpCalloutMock> mocks) {
            this.mocks = mocks;
        }

        public HttpResponse respond(HttpRequest req) {
            if (callCount < mocks.size()) {
                return mocks[callCount++].respond(req);
            }
            // Default to last mock if more calls than expected
            return mocks[mocks.size() - 1].respond(req);
        }
    }
}
