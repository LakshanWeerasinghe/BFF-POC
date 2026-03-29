import https from 'https';
import http from 'http';
import { NextRequest, NextResponse } from 'next/server';

// Reusable HTTPS agent that accepts self-signed certificates.
// Used only in server-side route handlers (never shipped to the browser).
const insecureAgent = new https.Agent({ rejectUnauthorized: false });

/**
 * Forward a Next.js route-handler request to `targetUrl`, preserving the
 * method, relevant headers, and body.  Returns a NextResponse with the
 * proxied status code and body.
 */
export function proxyTo(req: NextRequest, targetUrl: string): Promise<NextResponse> {
  return new Promise((resolve) => {
    const url    = new URL(targetUrl);
    const isHttps = url.protocol === 'https:';

    // Collect the body for non-GET/HEAD requests.
    const collectBody = (): Promise<string | undefined> =>
      req.method !== 'GET' && req.method !== 'HEAD'
        ? req.text()
        : Promise.resolve(undefined);

    collectBody().then((body) => {
      const headers: Record<string, string> = {};

      const contentType = req.headers.get('content-type');
      if (contentType) headers['content-type'] = contentType;

      const auth = req.headers.get('authorization');
      if (auth) headers['authorization'] = auth;

      const userAuth = req.headers.get('x-sonicwave-user-auth');
      if (userAuth) headers['x-sonicwave-user-auth'] = userAuth;

      if (body) headers['content-length'] = String(Buffer.byteLength(body));

      const options: https.RequestOptions = {
        hostname: url.hostname,
        port:     url.port || (isHttps ? '443' : '80'),
        path:     url.pathname + url.search,
        method:   req.method,
        headers,
        ...(isHttps && { agent: insecureAgent }),
      };

      const transport = isHttps ? https : http;

      const proxyReq = transport.request(options, (proxyRes) => {
        const chunks: Buffer[] = [];
        proxyRes.on('data', (chunk: Buffer) => chunks.push(chunk));
        proxyRes.on('end', () => {
          const resHeaders: Record<string, string> = {};
          const ct = proxyRes.headers['content-type'];
          if (ct) resHeaders['content-type'] = Array.isArray(ct) ? ct[0] : ct;

          resolve(
            new NextResponse(Buffer.concat(chunks), {
              status:  proxyRes.statusCode ?? 502,
              headers: resHeaders,
            }),
          );
        });
        proxyRes.on('error', () =>
          resolve(new NextResponse('Proxy response error', { status: 502 })),
        );
      });

      proxyReq.on('error', () =>
        resolve(new NextResponse('Proxy connection error', { status: 502 })),
      );

      if (body) proxyReq.write(body);
      proxyReq.end();
    });
  });
}
