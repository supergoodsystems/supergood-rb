ERRORS = {
  CACHING_RESPONSE: 'Error Caching Response',
  CACHING_REQUEST: 'Error Caching Request',
  DUMPING_DATA_TO_DISK: 'Error Dumping Data to Disk',
  POSTING_EVENTS: 'Error Posting Events',
  POSTING_ERRORS: 'Error Posting Errors',
  WRITING_TO_DISK: 'Error writing to disk',
  TEST_ERROR: 'Test Error for Testing Purposes',
  CONFIG_FETCH_ERROR: 'Error Fetching Remote Config',
  UNAUTHORIZED: 'Unauthorized: Invalid Client ID or Secret. Exiting.',
  NO_CLIENT_ID:
    'No Client ID Provided, set SUPERGOOD_CLIENT_ID or pass it as an argument',
  NO_CLIENT_SECRET:
    'No Client Secret Provided, set SUPERGOOD_CLIENT_SECRET or pass it as an argument'
};

LOCAL_CLIENT_ID = 'local-client-id';
LOCAL_CLIENT_SECRET = 'local-client-secret';

DEFAULT_SUPERGOOD_BYTE_LIMIT = 500000

DEFAULT_CONFIG = {
  keysToHash: [],
  flushInterval: 1000,
  remoteConfigFetchInterval: 10000,
  ignoredDomains: [],
  allowedDomains: [],
  forceRedactAll: true
}

# GZIP_START_BYTES = b'\x1f\x8b'

class SupergoodException < StandardError
  def initialize(msg = message)
    super(msg)
  end
end
