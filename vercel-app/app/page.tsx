"use client"

import { useEffect, useState } from "react"
import { Download, Play, Smartphone, Film, Tv, Star } from "lucide-react"
import { Button } from "@/components/ui/button"

// Configuration - Update these values
const APP_CONFIG = {
  name: "DanieWatch",
  tagline: "Stream Movies & TV Shows",
  description: "Your ultimate destination for streaming the latest movies and TV shows. Enjoy unlimited entertainment anytime, anywhere.",
  // Update this to your actual APK download URL
  downloadUrl: "#",
  // Update this to your app's deep link scheme (e.g., "daniewatch://")
  appScheme: "daniewatch://",
  // Android package name for Play Store fallback
  packageName: "com.daniewatch.app",
}

export default function DanieWatchLanding() {
  const [showDownload, setShowDownload] = useState(false)
  const [isRedirecting, setIsRedirecting] = useState(true)

  useEffect(() => {
    // Try to open the app using deep link via an anchor click
    const tryOpenApp = () => {
      // Create a temporary anchor element for deep link
      const link = document.createElement("a")
      link.href = APP_CONFIG.appScheme
      link.style.display = "none"
      document.body.appendChild(link)
      
      // Try to trigger the deep link
      try {
        link.click()
      } catch {
        // Silently fail if blocked
      }
      
      // Clean up
      setTimeout(() => {
        if (link.parentNode) {
          link.parentNode.removeChild(link)
        }
      }, 100)
    }

    tryOpenApp()

    // Show download page after a short delay
    const fallbackTimer = setTimeout(() => {
      setIsRedirecting(false)
      setShowDownload(true)
    }, 1500)

    return () => clearTimeout(fallbackTimer)
  }, [])

  const handleDownload = () => {
    if (APP_CONFIG.downloadUrl === "#") {
      alert("Download link not configured yet. Please update APP_CONFIG.downloadUrl in page.tsx")
      return
    }
    window.location.href = APP_CONFIG.downloadUrl
  }

  // Loading/Redirecting state
  if (isRedirecting && !showDownload) {
    return (
      <main className="min-h-screen flex items-center justify-center bg-background">
        <div className="text-center">
          <div className="relative mb-6">
            <div className="w-20 h-20 mx-auto bg-primary/20 rounded-2xl flex items-center justify-center animate-pulse">
              <Play className="w-10 h-10 text-primary" />
            </div>
          </div>
          <h1 className="text-2xl font-bold text-foreground mb-2">{APP_CONFIG.name}</h1>
          <p className="text-muted-foreground">Opening app...</p>
          <div className="mt-4 flex justify-center gap-1">
            <span className="w-2 h-2 bg-primary rounded-full animate-bounce" style={{ animationDelay: "0ms" }} />
            <span className="w-2 h-2 bg-primary rounded-full animate-bounce" style={{ animationDelay: "150ms" }} />
            <span className="w-2 h-2 bg-primary rounded-full animate-bounce" style={{ animationDelay: "300ms" }} />
          </div>
        </div>
      </main>
    )
  }

  // Download page
  return (
    <main className="min-h-screen bg-background">
      {/* Hero Section */}
      <section className="relative overflow-hidden">
        {/* Background gradient */}
        <div className="absolute inset-0 bg-gradient-to-b from-primary/10 via-background to-background" />
        
        {/* Decorative elements */}
        <div className="absolute top-20 left-10 w-72 h-72 bg-primary/5 rounded-full blur-3xl" />
        <div className="absolute top-40 right-10 w-96 h-96 bg-accent/5 rounded-full blur-3xl" />
        
        <div className="relative max-w-4xl mx-auto px-6 py-20">
          {/* App Icon and Name */}
          <div className="text-center mb-12">
            <div className="relative inline-block mb-6">
              <div className="w-28 h-28 bg-card border border-border rounded-3xl flex items-center justify-center shadow-2xl shadow-primary/20">
                <div className="w-20 h-20 bg-gradient-to-br from-primary to-accent rounded-2xl flex items-center justify-center">
                  <Play className="w-10 h-10 text-primary-foreground fill-current" />
                </div>
              </div>
              {/* Glow effect */}
              <div className="absolute inset-0 w-28 h-28 bg-primary/20 rounded-3xl blur-xl -z-10" />
            </div>
            
            <h1 className="text-5xl font-bold text-foreground mb-3 tracking-tight">
              {APP_CONFIG.name}
            </h1>
            <p className="text-xl text-primary font-medium mb-4">
              {APP_CONFIG.tagline}
            </p>
            <p className="text-muted-foreground max-w-md mx-auto leading-relaxed">
              {APP_CONFIG.description}
            </p>
          </div>

          {/* Download Button */}
          <div className="flex flex-col items-center gap-4 mb-16">
            <Button 
              onClick={handleDownload}
              size="lg"
              className="h-14 px-8 text-lg font-semibold bg-primary hover:bg-primary/90 text-primary-foreground rounded-xl shadow-lg shadow-primary/30 transition-all hover:scale-105 hover:shadow-xl hover:shadow-primary/40"
            >
              <Download className="w-5 h-5 mr-2" />
              Download APK
            </Button>
            <p className="text-sm text-muted-foreground flex items-center gap-2">
              <Smartphone className="w-4 h-4" />
              Android App
            </p>
          </div>

          {/* Features */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6 max-w-3xl mx-auto">
            <FeatureCard 
              icon={<Film className="w-6 h-6" />}
              title="Movies"
              description="Thousands of movies from classics to new releases"
            />
            <FeatureCard 
              icon={<Tv className="w-6 h-6" />}
              title="TV Shows"
              description="Binge-watch your favorite series anytime"
            />
            <FeatureCard 
              icon={<Star className="w-6 h-6" />}
              title="HD Quality"
              description="Stream in high definition for the best experience"
            />
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-border py-8">
        <div className="max-w-4xl mx-auto px-6 text-center">
          <p className="text-muted-foreground text-sm">
            {APP_CONFIG.name} - Stream your entertainment
          </p>
        </div>
      </footer>
    </main>
  )
}

function FeatureCard({ 
  icon, 
  title, 
  description 
}: { 
  icon: React.ReactNode
  title: string
  description: string 
}) {
  return (
    <div className="bg-card border border-border rounded-xl p-6 text-center hover:border-primary/50 transition-colors">
      <div className="w-12 h-12 mx-auto mb-4 bg-primary/10 rounded-xl flex items-center justify-center text-primary">
        {icon}
      </div>
      <h3 className="font-semibold text-foreground mb-2">{title}</h3>
      <p className="text-sm text-muted-foreground">{description}</p>
    </div>
  )
}
