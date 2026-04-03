import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  async rewrites() {
    const bffUrl = process.env.BFF_URL || 'http://localhost:7000';
    return [
      {
        source:      '/bff/:path*',
        destination: `${bffUrl}/bff/:path*`,
      },
    ];
  },
};

export default nextConfig;
