import { LinkPreviewService } from './link-preview.service';

// We test the SSRF-blocking behaviour by mocking the global fetch.
// fetchPreview returns null for blocked IPs without ever calling fetch.
describe('LinkPreviewService – SSRF blocking', () => {
  let service: LinkPreviewService;

  beforeEach(() => {
    service = new LinkPreviewService();
    // Spy on global fetch; if it is called the test fails (blocked URLs must not reach network)
    global.fetch = jest.fn().mockResolvedValue({
      ok: false,
      headers: { get: () => null },
      body: null,
    } as unknown as Response);
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  const blocked = [
    'http://169.254.169.254/latest/meta-data/', // AWS IMDS
    'http://169.254.169.254/computeMetadata/v1/', // GCP IMDS
    'http://169.254.0.1/', // IPv4 link-local
    'http://[fe80::1]/', // IPv6 link-local
    'http://[fc00::1]/', // IPv6 ULA
    'http://10.0.0.1/', // RFC-1918
    'http://192.168.1.1/', // RFC-1918
    'http://127.0.0.1/', // loopback
    'http://localhost/', // loopback
    'http://172.16.0.1/', // RFC-1918
  ];

  test.each(blocked)('blocks %s', async (url) => {
    const result = await service.fetchPreview(url);
    expect(result).toBeNull();
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('allows a public HTTPS URL', async () => {
    (global.fetch as jest.Mock).mockResolvedValue({
      ok: true,
      headers: { get: (h: string) => (h === 'content-type' ? 'text/html' : null) },
      body: {
        getReader: () => ({
          read: jest
            .fn()
            .mockResolvedValueOnce({
              done: false,
              value: new TextEncoder().encode(
                '<html><head><title>Example</title></head></html>',
              ),
            })
            .mockResolvedValueOnce({ done: true, value: undefined }),
          cancel: jest.fn(),
        }),
      },
    } as unknown as Response);

    const result = await service.fetchPreview('check out https://example.com');
    expect(result?.url).toBe('https://example.com');
    expect(global.fetch).toHaveBeenCalledWith(
      'https://example.com',
      expect.objectContaining({ signal: expect.any(AbortSignal) }),
    );
  });
});
