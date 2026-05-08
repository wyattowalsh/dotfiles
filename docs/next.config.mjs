import { createMDX } from "fumadocs-mdx/next";

const withMDX = createMDX();

/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "export",
  reactStrictMode: true,
  turbopack: {
    root: import.meta.dirname
  },
  typescript: {
    ignoreBuildErrors: false
  }
};

export default withMDX(nextConfig);
