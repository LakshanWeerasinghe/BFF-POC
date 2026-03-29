import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  // Expose to the browser bundle (process.env.* in client components / api.ts).
  // Server-side route handlers read process.env directly — no entry needed here.
  env: {
    APIM_ENABLED:       process.env.APIM_ENABLED       || 'false',
    APIM_CLIENT_ID:     process.env.APIM_CLIENT_ID     || '',
    APIM_CLIENT_SECRET: process.env.APIM_CLIENT_SECRET || '',
  },
};

export default nextConfig;
