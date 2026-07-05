import path from "node:path";
import { fileURLToPath } from "node:url";
import { createMDX } from "fumadocs-mdx/next";

const docsRoot = path.dirname(fileURLToPath(import.meta.url));
const withMDX = createMDX();

/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "export",
  reactStrictMode: true,
  turbopack: {
    root: docsRoot
  },
  typescript: {
    ignoreBuildErrors: false
  }
};

export default withMDX(nextConfig);
