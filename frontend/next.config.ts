import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Empty turbopack config — signals intentional use of Turbopack (Next.js 16 default)
  turbopack: {},
  // Transpile ESM-only packages
  transpilePackages: ['@rainbow-me/rainbowkit'],
};

export default nextConfig;
