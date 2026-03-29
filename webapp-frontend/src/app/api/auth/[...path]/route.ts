import { NextRequest } from 'next/server';
import { proxyTo } from '../../../../lib/proxy';

const APIM_ENABLED  = process.env.APIM_ENABLED === 'true';
const APIM_GATEWAY  = process.env.APIM_GATEWAY_URL  || 'https://localhost:8243';
const AUTH_SERVICE  = process.env.AUTH_SERVICE_URL  || 'http://localhost:9090';

function targetUrl(path: string[]): string {
  const segment = path.join('/');
  return APIM_ENABLED
    ? `${APIM_GATEWAY}/library/0.9.0/${segment}`
    : `${AUTH_SERVICE}/auth/${segment}`;
}

export async function GET(req: NextRequest, { params }: { params: Promise<{ path: string[] }> }) {
  const { path } = await params;
  return proxyTo(req, targetUrl(path));
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ path: string[] }> }) {
  const { path } = await params;
  return proxyTo(req, targetUrl(path));
}
