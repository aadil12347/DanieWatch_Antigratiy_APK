"use client"

import { useEffect, useState } from "react"
import { use } from "react"
import { Play, Tv, Download, ArrowLeft } from "lucide-react"
import { Button } from "@/components/ui/button"
import Link from "next/link"

const APP_CONFIG = {
  name: "DanieWatch",
  appScheme: "daniewatch://",
  packageName: "com.daniewatch.app",
}

export default function TvDeepLink({ params }: { params: Promise<{ id: string }> }) {
  const resolvedParams = use(params)
  const { id } = resolvedParams
  const [showFallback, setShowFallback] = useState(false)
  const [isRedirecting, setIsRedirecting] = useState(true)

  const appLink = `${APP_CONFIG.appScheme}tv/${id}`
  const intentLink = `intent://tv/${id}#Intent;scheme=daniewatch;package=${APP_CONFIG.packageName};end`

  useEffect(() => {
    // Try to open the app using the deep link
    const tryOpenApp = () => {
      const isAndroid = /Android/i.test(navigator.userAgent)

      if (isAndroid) {
        window.location.href = intentLink
      } else {
        const iframe = document.createElement("iframe")
        iframe.style.display = "none"
        iframe.src = appLink
        document.body.appendChild(iframe)

        setTimeout(() => {
          if (iframe.parentNode) {
            iframe.parentNode.removeChild(iframe)
          }
        }, 100)
      }
    }

    tryOpenApp()

    const fallbackTimer = setTimeout(() => {
      setIsRedirecting(false)
      setShowFallback(true)
    }, 1500)

    return () => clearTimeout(fallbackTimer)
  }, [appLink, intentLink])

  // Loading/Redirecting state
  if (isRedirecting && !showFallback) {
    return (
      <main className="min-h-screen flex items-center justify-center bg-background">
        <div className="text-center">
          <div className="relative mb-6">
            <div className="w-20 h-20 mx-auto bg-primary/20 rounded-2xl flex items-center justify-center animate-pulse">
              <Play className="w-10 h-10 text-primary" />
            </div>
          </div>
          <h1 className="text-2xl font-bold text-foreground mb-2">{APP_CONFIG.name}</h1>
          <p className="text-muted-foreground">Opening TV show in app…</p>
          <div className="mt-4 flex justify-center gap-1">
            <span className="w-2 h-2 bg-primary rounded-full animate-bounce" style={{ animationDelay: "0ms" }} />
            <span className="w-2 h-2 bg-primary rounded-full animate-bounce" style={{ animationDelay: "150ms" }} />
            <span className="w-2 h-2 bg-primary rounded-full animate-bounce" style={{ animationDelay: "300ms" }} />
          </div>
        </div>
      </main>
    )
  }

  // Fallback UI
  return (
    <main className="min-h-screen bg-background flex items-center justify-center">
      <div className="max-w-md w-full mx-auto px-6 py-12">
        <div className="absolute inset-0 bg-gradient-to-b from-primary/5 via-background to-background -z-10" />

        <div className="text-center">
          {/* App Icon */}
          <div className="relative inline-block mb-6">
            <div className="w-24 h-24 bg-card border border-border rounded-3xl flex items-center justify-center shadow-2xl shadow-primary/20">
              <div className="w-16 h-16 bg-gradient-to-br from-primary to-accent rounded-2xl flex items-center justify-center">
                <Tv className="w-8 h-8 text-primary-foreground" />
              </div>
            </div>
            <div className="absolute inset-0 w-24 h-24 bg-primary/20 rounded-3xl blur-xl -z-10" />
          </div>

          {/* Content Info */}
          <h1 className="text-3xl font-bold text-foreground mb-2 tracking-tight">
            {APP_CONFIG.name}
          </h1>
          <div className="inline-flex items-center gap-2 px-4 py-1.5 bg-primary/10 rounded-full mb-3">
            <Tv className="w-4 h-4 text-primary" />
            <span className="text-primary font-semibold text-sm uppercase tracking-wider">TV Show</span>
          </div>
          <p className="text-muted-foreground mb-8">
            View this TV show in the DanieWatch app for the best experience.
          </p>

          {/* Action Buttons */}
          <div className="flex flex-col gap-3">
            <Button
              asChild
              size="lg"
              className="h-14 text-lg font-semibold bg-primary hover:bg-primary/90 text-primary-foreground rounded-xl shadow-lg shadow-primary/30 transition-all hover:scale-105"
            >
              <a href={appLink}>
                <Play className="w-5 h-5 mr-2" />
                Open in DanieWatch
              </a>
            </Button>

            <Button
              asChild
              variant="outline"
              size="lg"
              className="h-12 rounded-xl border-border hover:bg-card"
            >
              <Link href="/">
                <Download className="w-4 h-4 mr-2" />
                Download App
              </Link>
            </Button>
          </div>

          <p className="text-xs text-muted-foreground mt-6">
            If the app doesn't open, make sure DanieWatch is installed on your device.
          </p>

          <Link href="/" className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground mt-4 transition-colors">
            <ArrowLeft className="w-3 h-3" />
            Back to homepage
          </Link>
        </div>
      </div>
    </main>
  )
}
