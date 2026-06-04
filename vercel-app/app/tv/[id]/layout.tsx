import type { Metadata } from "next"

export async function generateMetadata({ params }: { params: Promise<{ id: string }> }): Promise<Metadata> {
  const { id } = await params
  return {
    title: `Watch TV Show on DanieWatch`,
    description: `Check out this TV show on DanieWatch — Stream Movies & TV Shows. Open the app to start watching!`,
    openGraph: {
      title: `📺 Watch this TV Show on DanieWatch`,
      description: `Tap to open this TV show in the DanieWatch app and start streaming instantly!`,
      siteName: "DanieWatch",
      type: "website",
      url: `https://daniewatch-app.vercel.app/tv/${id}`,
    },
    twitter: {
      card: "summary",
      title: `📺 Watch this TV Show on DanieWatch`,
      description: `Tap to open this TV show in the DanieWatch app and start streaming!`,
    },
  }
}

export default function TvLayout({ children }: { children: React.ReactNode }) {
  return <>{children}</>
}
