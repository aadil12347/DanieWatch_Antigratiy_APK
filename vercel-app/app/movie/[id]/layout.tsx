import type { Metadata } from "next"

export async function generateMetadata({ params }: { params: Promise<{ id: string }> }): Promise<Metadata> {
  const { id } = await params
  return {
    title: `Watch Movie on DanieWatch`,
    description: `Check out this movie on DanieWatch — Stream Movies & TV Shows. Open the app to start watching!`,
    openGraph: {
      title: `🎬 Watch this Movie on DanieWatch`,
      description: `Tap to open this movie in the DanieWatch app and start streaming instantly!`,
      siteName: "DanieWatch",
      type: "website",
      url: `https://daniewatch-app.vercel.app/movie/${id}`,
    },
    twitter: {
      card: "summary",
      title: `🎬 Watch this Movie on DanieWatch`,
      description: `Tap to open this movie in the DanieWatch app and start streaming!`,
    },
  }
}

export default function MovieLayout({ children }: { children: React.ReactNode }) {
  return <>{children}</>
}
