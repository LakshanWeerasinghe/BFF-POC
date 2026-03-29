import { NextRequest } from 'next/server';
import { proxyTo } from '../../../lib/proxy';

const APIM_ENABLED = process.env.APIM_ENABLED === 'true';
const APIM_GATEWAY = process.env.APIM_GATEWAY_URL || 'https://localhost:8243';
const BACKEND_URL  = process.env.BACKEND_URL       || 'http://localhost:8080';

function targetUrl(): string {
  return APIM_ENABLED
    ? `${APIM_GATEWAY}/library/0.9.0/songs`
    : `${BACKEND_URL}/api/songs`;
}

export function GET(req: NextRequest) {
  return proxyTo(req, targetUrl());
}

export function POST(req: NextRequest) {
  return proxyTo(req, targetUrl());
}
