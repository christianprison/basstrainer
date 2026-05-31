/** @type {import('next').NextConfig} */
const nextConfig = {
  // Statischer Export für GitHub Pages (erzeugt ./out)
  output: "export",
  eslint: {
    ignoreDuringBuilds: true,
  },
  typescript: {
    ignoreBuildErrors: true,
  },
  images: {
    unoptimized: true,
  },
}

export default nextConfig
