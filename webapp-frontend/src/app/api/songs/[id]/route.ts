import { NextRequest } from 'next/server';
import { proxyTo } from '../../../../lib/proxy';

const APIM_ENABLED = process.env.APIM_ENABLED === 'true';
const APIM_GATEWAY = process.env.APIM_GATEWAY_URL || 'https://localhost:8243';
const BACKEND_URL  = process.env.BACKEND_URL       || 'http://localhost:8080';

function targetUrl(id: string): string {
  return APIM_ENABLED
    ? `${APIM_GATEWAY}/library/0.9.0/songs/${id}`
    : `${BACKEND_URL}/api/songs/${id}`;
}

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return proxyTo(req, targetUrl(id));
}
