import React from "react";
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Helmet } from "react-helmet-async";
import { useAuth } from "@/contexts/AuthContext";

import { setTutorialFlag } from "@/contexts/TutorialContext";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useToast } from "@/hooks/use-toast";
import { Loader2, Mail, Lock, ArrowLeft, User, Eye, EyeOff, KeyRound, CheckCircle2, MailCheck, ShieldCheck } from "lucide-react";
import { cn } from "@/lib/utils";
import { useRouteContentReady } from "@/hooks/useRouteContentReady";

type AuthMode = "select" | "login" | "signup" | "forgot" | "check-email" | "reset-password";

const Auth = () => {
  const [isLoading, setIsLoading] = useState(false);
  const [mode, setMode] = useState<AuthMode>("select");
  const [email, setEmail] = useState("");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [sentEmail, setSentEmail] = useState("");

  const { user, signInWithGoogle, signInWithEmail, signUpWithEmail, resetPassword, updatePassword, isRecoveryMode } = useAuth();
  const navigate = useNavigate();
  const { toast } = useToast();

  // Detect recovery mode from Supabase (user clicked reset link)
  useEffect(() => {
    if (isRecoveryMode) {
      setMode("reset-password");
    }
  }, [isRecoveryMode]);

  useEffect(() => {
    // Don't redirect to home if in recovery mode — user needs to set new password
    if (user && !isRecoveryMode && mode !== "reset-password") {
      navigate("/");
    }
  }, [user, navigate, isRecoveryMode, mode]);

  const handleGoogleSignIn = async () => {
    setIsLoading(true);
    try {
      const { error } = await signInWithGoogle();
      if (error) {
        toast({
          title: "Error",
          description: error.message || "Failed to sign in with Google",
          variant: "destructive",
        });
      }
    } catch (err) {
      toast({
        title: "Error",
        description: "Something went wrong. Please try again.",
        variant: "destructive",
      });
    } finally {
      setIsLoading(false);
    }
  };

  const handleEmailAuth = async (e: React.FormEvent) => {
    e.preventDefault();

    // Skip email/password validation for reset-password mode (fields are hidden)
    if (mode !== "reset-password") {
      if (!email.trim()) {
        toast({
          title: "Error",
          description: "Please enter your email address",
          variant: "destructive",
        });
        return;
      }

      if (mode !== "forgot" && !password.trim()) {
        toast({
          title: "Error",
          description: "Please enter your password",
          variant: "destructive",
        });
        return;
      }
    }

    if (mode === "signup" && password.length < 6) {
      toast({
        title: "Error",
        description: "Password must be at least 6 characters",
        variant: "destructive",
      });
      return;
    }

    if (mode === "signup" && !username.trim()) {
      toast({
        title: "Error",
        description: "Please enter a username",
        variant: "destructive",
      });
      return;
    }

    setIsLoading(true);
    try {
      if (mode === "login") {
        const { error } = await signInWithEmail(email, password);
        if (error) {
          toast({
            title: "Login Failed",
            description: error.message || "Invalid email or password",
            variant: "destructive",
          });
        } else {
          toast({
            title: "Welcome back! 🎉",
            description: "You have successfully signed in to DanieWatch.",
          });
        }
      } else if (mode === "signup") {
        const { error } = await signUpWithEmail(email, password, username);
        if (error) {
          if (error.message.includes("already registered")) {
            toast({
              title: "Account Exists",
              description: "This email is already registered. Please sign in instead.",
              variant: "destructive",
            });
          } else {
            toast({
              title: "Signup Failed",
              description: error.message || "Failed to create account",
              variant: "destructive",
            });
          }
        } else {
          // Set tutorial flag for new signups
          setTutorialFlag();
          toast({
            title: "Account Created! 🎉",
            description: "Check your email for a confirmation link to verify your account.",
          });
        }
      } else if (mode === "forgot") {
        const { error } = await resetPassword(email);
        if (error) {
          toast({
            title: "Error",
            description: error.message || "Failed to send reset email",
            variant: "destructive",
          });
        } else {
          // Show the check-email confirmation screen
          setSentEmail(email);
          setMode("check-email");
        }
      } else if (mode === "reset-password") {
        if (newPassword.length < 6) {
          toast({
            title: "Error",
            description: "Password must be at least 6 characters",
            variant: "destructive",
          });
          setIsLoading(false);
          return;
        }
        if (newPassword !== confirmPassword) {
          toast({
            title: "Error",
            description: "Passwords do not match",
            variant: "destructive",
          });
          setIsLoading(false);
          return;
        }
        const { error } = await updatePassword(newPassword);
        if (error) {
          toast({
            title: "Error",
            description: error.message || "Failed to update password",
            variant: "destructive",
          });
        } else {
          toast({
            title: "Password Updated! 🎉",
            description: "Your password has been changed successfully.",
          });
          navigate("/");
        }
      }
    } catch (err) {
      toast({
        title: "Error",
        description: "Something went wrong. Please try again.",
        variant: "destructive",
      });
    } finally {
      setIsLoading(false);
    }
  };

  const switchMode = (newMode: AuthMode) => {
    setMode(newMode);
    setEmail("");
    setUsername("");
    setPassword("");
    setNewPassword("");
    setConfirmPassword("");
    setShowPassword(false);
  };

  // Password strength helper
  const getPasswordStrength = (pw: string) => {
    if (!pw) return { level: 0, label: "", color: "" };
    if (pw.length < 6) return { level: 1, label: "Too short", color: "bg-red-500" };
    let score = 0;
    if (pw.length >= 8) score++;
    if (/[A-Z]/.test(pw)) score++;
    if (/[0-9]/.test(pw)) score++;
    if (/[^A-Za-z0-9]/.test(pw)) score++;
    if (score <= 1) return { level: 2, label: "Weak", color: "bg-orange-500" };
    if (score === 2) return { level: 3, label: "Good", color: "bg-yellow-500" };
    return { level: 4, label: "Strong", color: "bg-green-500" };
  };

  const pwStrength = getPasswordStrength(mode === "signup" ? password : newPassword);

  useRouteContentReady(true);

  return (
    <>
      <Helmet>
        <title>Sign In - DanieWatch</title>
        <meta name="description" content="Sign in to save your watchlist and access all features" />
      </Helmet>

      <div className="min-h-screen flex items-center justify-center bg-background relative overflow-hidden">
        {/* Cinematic Background */}
        <div className="absolute inset-0">
          {/* Base gradient */}
          <div className="absolute inset-0 bg-gradient-to-br from-[hsl(0,84%,55%,0.08)] via-background to-background" />
          {/* Top-left glow */}
          <div
            className="absolute -top-32 -left-32 w-[500px] h-[500px] rounded-full"
            style={{
              background: "radial-gradient(circle, hsl(0 84% 55% / 0.12) 0%, transparent 70%)",
              animation: "pulse 4s ease-in-out infinite",
            }}
          />
          {/* Bottom-right glow */}
          <div
            className="absolute -bottom-32 -right-32 w-[400px] h-[400px] rounded-full"
            style={{
              background: "radial-gradient(circle, hsl(0 84% 55% / 0.06) 0%, transparent 70%)",
              animation: "pulse 5s ease-in-out infinite 1.5s",
            }}
          />
          {/* Film strip decorations */}
          <div className="absolute top-0 left-0 w-full h-full pointer-events-none overflow-hidden opacity-[0.03]">
            <div className="absolute top-[10%] -left-[5%] w-[110%] h-[1px] bg-white rotate-[15deg]" />
            <div className="absolute top-[30%] -left-[5%] w-[110%] h-[1px] bg-white rotate-[-8deg]" />
            <div className="absolute top-[60%] -left-[5%] w-[110%] h-[1px] bg-white rotate-[5deg]" />
            <div className="absolute top-[85%] -left-[5%] w-[110%] h-[1px] bg-white rotate-[-12deg]" />
          </div>
          {/* Floating dots */}
          <div className="absolute inset-0 pointer-events-none">
            {[...Array(5)].map((_, i) => (
              <div
                key={i}
                className="absolute rounded-full bg-[hsl(0,84%,60%)]"
                style={{
                  width: `${3 + i}px`,
                  height: `${3 + i}px`,
                  left: `${12 + i * 18}%`,
                  top: `${15 + (i % 3) * 28}%`,
                  opacity: 0.15 + i * 0.03,
                  animation: `float ${6 + i * 1.5}s ease-in-out infinite ${i * 0.8}s`,
                }}
              />
            ))}
          </div>
        </div>

        <div className="relative z-10 w-full max-w-[420px] mx-4">
          {/* Logo */}
          <div
            className="flex items-center justify-center gap-3 mb-8"
            style={{ animation: "slideDown 0.6s ease-out" }}
          >
            <div className="relative w-12 h-12 flex items-center justify-center">
              <div
                className="absolute inset-0 rounded-2xl blur-xl"
                style={{ background: "hsl(0 84% 55% / 0.25)" }}
              />
              <svg viewBox="0 0 100 100" className="w-full h-full relative z-10" style={{ filter: "drop-shadow(0 0 12px hsl(0 84% 55% / 0.5))" }}>
                <defs>
                  <linearGradient id="authLogoGrad" x1="0%" y1="0%" x2="100%" y2="100%">
                    <stop offset="0%" stopColor="hsl(0, 84%, 65%)" />
                    <stop offset="100%" stopColor="hsl(0, 84%, 50%)" />
                  </linearGradient>
                </defs>
                <path
                  d="M25 15 C15 15 10 25 10 50 C10 75 15 85 25 85 L55 85 C75 85 90 70 90 50 C90 30 75 15 55 15 L40 15 L40 25 L55 25 C68 25 78 35 78 50 C78 65 68 75 55 75 L25 75 C22 75 22 70 22 50 C22 30 22 25 25 25 L25 15 Z M30 35 L30 65 L55 65 C60 65 65 60 65 50 C65 40 60 35 55 35 L30 35 Z"
                  fill="url(#authLogoGrad)"
                />
              </svg>
            </div>
            <span className="text-3xl font-bold tracking-tight">
              Danie<span style={{ color: "hsl(0, 84%, 60%)" }}>Watch</span>
            </span>
          </div>

          {/* Auth Card */}
          <div
            className="relative rounded-2xl overflow-hidden"
            style={{
              background: "hsl(0 0% 7% / 0.85)",
              backdropFilter: "blur(24px)",
              WebkitBackdropFilter: "blur(24px)",
              border: "1px solid hsl(0 0% 100% / 0.08)",
              boxShadow: "0 25px 60px hsl(0 0% 0% / 0.5), 0 0 80px hsl(0 84% 55% / 0.06)",
              animation: "slideUp 0.5s ease-out 0.1s both",
            }}
          >
            {/* Top accent line */}
            <div
              className="h-[2px] w-full"
              style={{
                background: "linear-gradient(90deg, transparent, hsl(0 84% 55% / 0.8), hsl(0 84% 55% / 0.4), transparent)",
              }}
            />

            {/* Card glow accents */}
            <div className="absolute -top-20 -right-20 w-40 h-40 rounded-full" style={{ background: "radial-gradient(circle, hsl(0 84% 55% / 0.06) 0%, transparent 70%)" }} />
            <div className="absolute -bottom-20 -left-20 w-40 h-40 rounded-full" style={{ background: "radial-gradient(circle, hsl(0 84% 55% / 0.04) 0%, transparent 70%)" }} />

            <div className="relative z-10 p-7 sm:p-8">

              {/* =========== SELECT MODE =========== */}
              {mode === "select" && (
                <div style={{ animation: "fadeIn 0.4s ease-out" }}>
                  <div className="text-center mb-7">
                    <h2 className="text-2xl font-bold mb-2 text-foreground">Welcome!</h2>
                    <p className="text-muted-foreground text-sm">Choose how you'd like to continue</p>
                  </div>

                  <div className="space-y-3">
                    {/* Google Sign In */}
                    <Button
                      onClick={handleGoogleSignIn}
                      disabled={isLoading}
                      className="w-full h-[52px] bg-white hover:bg-gray-50 text-gray-900 font-medium rounded-xl flex items-center justify-center gap-3 transition-all duration-300 hover:scale-[1.015] hover:shadow-lg border-0"
                    >
                      {isLoading ? (
                        <Loader2 className="w-5 h-5 animate-spin" />
                      ) : (
                        <>
                          <svg className="w-5 h-5" viewBox="0 0 24 24">
                            <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
                            <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
                            <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
                            <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
                          </svg>
                          Continue with Google
                        </>
                      )}
                    </Button>

                    <div className="relative my-5">
                      <div className="absolute inset-0 flex items-center">
                        <div className="w-full border-t" style={{ borderColor: "hsl(0 0% 100% / 0.08)" }} />
                      </div>
                      <div className="relative flex justify-center text-xs uppercase">
                        <span className="px-3 text-muted-foreground" style={{ background: "hsl(0 0% 7% / 0.85)" }}>or</span>
                      </div>
                    </div>

                    {/* Email Option */}
                    <Button
                      onClick={() => switchMode("login")}
                      variant="outline"
                      className="w-full h-[52px] rounded-xl font-medium transition-all duration-300 hover:scale-[1.015] flex items-center justify-center gap-3"
                      style={{
                        background: "hsl(0 0% 100% / 0.04)",
                        borderColor: "hsl(0 0% 100% / 0.1)",
                      }}
                    >
                      <Mail className="w-5 h-5" />
                      Continue with Email
                    </Button>
                  </div>
                </div>
              )}

              {/* =========== CHECK EMAIL (after forgot password) =========== */}
              {mode === "check-email" && (
                <div className="text-center py-4" style={{ animation: "fadeIn 0.4s ease-out" }}>
                  <div
                    className="mx-auto w-20 h-20 rounded-full flex items-center justify-center mb-6"
                    style={{
                      background: "linear-gradient(135deg, hsl(0 84% 55% / 0.15) 0%, hsl(0 84% 55% / 0.05) 100%)",
                      border: "1px solid hsl(0 84% 55% / 0.2)",
                    }}
                  >
                    <MailCheck className="w-9 h-9" style={{ color: "hsl(0, 84%, 60%)" }} />
                  </div>
                  <h2 className="text-2xl font-bold mb-2 text-foreground">Check your email</h2>
                  <p className="text-muted-foreground text-sm leading-relaxed mb-2">
                    We've sent a password reset link to
                  </p>
                  <p className="text-foreground font-medium text-sm mb-6 break-all">{sentEmail}</p>
                  <div
                    className="rounded-xl p-4 mb-6 text-left space-y-2"
                    style={{
                      background: "hsl(0 0% 100% / 0.03)",
                      border: "1px solid hsl(0 0% 100% / 0.06)",
                    }}
                  >
                    <p className="text-xs text-muted-foreground flex items-start gap-2">
                      <CheckCircle2 className="w-3.5 h-3.5 mt-0.5 shrink-0" style={{ color: "hsl(0, 84%, 60%)" }} />
                      Open the link in your email to reset your password
                    </p>
                    <p className="text-xs text-muted-foreground flex items-start gap-2">
                      <CheckCircle2 className="w-3.5 h-3.5 mt-0.5 shrink-0" style={{ color: "hsl(0, 84%, 60%)" }} />
                      If you don't see it, check your spam folder
                    </p>
                    <p className="text-xs text-muted-foreground flex items-start gap-2">
                      <CheckCircle2 className="w-3.5 h-3.5 mt-0.5 shrink-0" style={{ color: "hsl(0, 84%, 60%)" }} />
                      The link expires in 24 hours
                    </p>
                  </div>
                  <button
                    onClick={() => switchMode("login")}
                    className="text-sm font-medium transition-colors flex items-center justify-center gap-2 mx-auto"
                    style={{ color: "hsl(0, 84%, 60%)" }}
                  >
                    <ArrowLeft className="w-4 h-4" />
                    Back to sign in
                  </button>
                </div>
              )}

              {/* =========== LOGIN / SIGNUP / FORGOT / RESET-PASSWORD =========== */}
              {mode !== "select" && mode !== "check-email" && (
                <div style={{ animation: "fadeIn 0.35s ease-out" }}>
                  {/* Mode Tabs (not for forgot or reset-password) */}
                  {mode !== "forgot" && mode !== "reset-password" && (
                    <div
                      className="flex mb-7 rounded-xl p-1"
                      style={{
                        background: "hsl(0 0% 100% / 0.04)",
                        border: "1px solid hsl(0 0% 100% / 0.06)",
                      }}
                    >
                      <button
                        onClick={() => switchMode("login")}
                        className={cn(
                          "flex-1 py-2.5 px-4 rounded-lg text-sm font-medium transition-all duration-300",
                          mode === "login"
                            ? "text-white shadow-lg"
                            : "text-muted-foreground hover:text-foreground"
                        )}
                        style={mode === "login" ? {
                          background: "linear-gradient(135deg, hsl(0 84% 55%), hsl(0 84% 48%))",
                          boxShadow: "0 4px 15px hsl(0 84% 55% / 0.35)",
                        } : {}}
                      >
                        Sign In
                      </button>
                      <button
                        onClick={() => switchMode("signup")}
                        className={cn(
                          "flex-1 py-2.5 px-4 rounded-lg text-sm font-medium transition-all duration-300",
                          mode === "signup"
                            ? "text-white shadow-lg"
                            : "text-muted-foreground hover:text-foreground"
                        )}
                        style={mode === "signup" ? {
                          background: "linear-gradient(135deg, hsl(0 84% 55%), hsl(0 84% 48%))",
                          boxShadow: "0 4px 15px hsl(0 84% 55% / 0.35)",
                        } : {}}
                      >
                        Sign Up
                      </button>
                    </div>
                  )}

                  {/* Header Text */}
                  <div className={cn(
                    "text-center mb-6",
                    (mode === "forgot" || mode === "reset-password") && "mt-1"
                  )}>
                    {mode === "forgot" && (
                      <div
                        className="mx-auto w-14 h-14 rounded-full flex items-center justify-center mb-4"
                        style={{
                          background: "hsl(0 84% 55% / 0.1)",
                          border: "1px solid hsl(0 84% 55% / 0.15)",
                        }}
                      >
                        <Mail className="w-6 h-6" style={{ color: "hsl(0, 84%, 60%)" }} />
                      </div>
                    )}
                    {mode === "reset-password" && (
                      <div
                        className="mx-auto w-14 h-14 rounded-full flex items-center justify-center mb-4"
                        style={{
                          background: "hsl(0 84% 55% / 0.1)",
                          border: "1px solid hsl(0 84% 55% / 0.15)",
                        }}
                      >
                        <ShieldCheck className="w-6 h-6" style={{ color: "hsl(0, 84%, 60%)" }} />
                      </div>
                    )}
                    <h2 className="text-2xl font-bold mb-1.5 text-foreground">
                      {mode === "login" && "Welcome back"}
                      {mode === "signup" && "Create your account"}
                      {mode === "forgot" && "Forgot password?"}
                      {mode === "reset-password" && "Set new password"}
                    </h2>
                    <p className="text-muted-foreground text-sm">
                      {mode === "login" && "Sign in to continue watching"}
                      {mode === "signup" && "Join DanieWatch for free"}
                      {mode === "forgot" && "Enter your email and we'll send you a reset link"}
                      {mode === "reset-password" && "Choose a strong password for your account"}
                    </p>
                  </div>

                  {/* Form */}
                  <form onSubmit={handleEmailAuth} className="space-y-4">
                    {/* Username - Only for signup */}
                    <div className={cn(
                      "transition-all duration-400 overflow-hidden",
                      mode === "signup" ? "max-h-[90px] opacity-100" : "max-h-0 opacity-0"
                    )}>
                      <Label htmlFor="username" className="text-xs font-medium text-muted-foreground uppercase tracking-wider mb-1.5 block">Username</Label>
                      <div className="relative group">
                        <User className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground transition-colors group-focus-within:text-[hsl(0,84%,60%)] z-10" />
                        <Input
                          id="username"
                          type="text"
                          placeholder="Choose a username"
                          value={username}
                          onChange={(e) => setUsername(e.target.value)}
                          className="pl-10 h-11 rounded-lg text-sm focus-visible:ring-1 focus-visible:ring-offset-0 transition-all duration-300"
                          style={{
                            background: "hsl(0 0% 100% / 0.04)",
                            borderColor: "hsl(0 0% 100% / 0.08)",
                          }}
                          disabled={isLoading}
                        />
                      </div>
                    </div>

                    {/* Email (not for reset-password) */}
                    <div className={cn(
                      "transition-all duration-400 overflow-hidden",
                      mode !== "reset-password" ? "max-h-[90px] opacity-100" : "max-h-0 opacity-0"
                    )}>
                      <Label htmlFor="email" className="text-xs font-medium text-muted-foreground uppercase tracking-wider mb-1.5 block">Email</Label>
                      <div className="relative group">
                        <Mail className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground transition-colors group-focus-within:text-[hsl(0,84%,60%)] z-10" />
                        <Input
                          id="email"
                          type="email"
                          placeholder="you@example.com"
                          value={email}
                          onChange={(e) => setEmail(e.target.value)}
                          className="pl-10 h-11 rounded-lg text-sm focus-visible:ring-1 focus-visible:ring-offset-0 transition-all duration-300"
                          style={{
                            background: "hsl(0 0% 100% / 0.04)",
                            borderColor: "hsl(0 0% 100% / 0.08)",
                          }}
                          disabled={isLoading}
                        />
                      </div>
                    </div>

                    {/* Password (login & signup only) */}
                    <div className={cn(
                      "transition-all duration-400 overflow-hidden",
                      mode !== "forgot" && mode !== "reset-password" ? "max-h-[120px] opacity-100" : "max-h-0 opacity-0"
                    )}>
                      <Label htmlFor="password" className="text-xs font-medium text-muted-foreground uppercase tracking-wider mb-1.5 block">Password</Label>
                      <div className="relative group">
                        <Lock className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground transition-colors group-focus-within:text-[hsl(0,84%,60%)] z-10" />
                        <Input
                          id="password"
                          type={showPassword ? "text" : "password"}
                          placeholder="••••••••"
                          value={password}
                          onChange={(e) => setPassword(e.target.value)}
                          className="pl-10 pr-10 h-11 rounded-lg text-sm focus-visible:ring-1 focus-visible:ring-offset-0 transition-all duration-300"
                          style={{
                            background: "hsl(0 0% 100% / 0.04)",
                            borderColor: "hsl(0 0% 100% / 0.08)",
                          }}
                          disabled={isLoading}
                        />
                        <button
                          type="button"
                          onClick={() => setShowPassword(!showPassword)}
                          className="absolute right-3.5 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground transition-colors z-10"
                        >
                          {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                        </button>
                      </div>
                      {/* Password strength for signup */}
                      {mode === "signup" && password && (
                        <div className="mt-2 space-y-1" style={{ animation: "fadeIn 0.3s ease-out" }}>
                          <div className="flex gap-1">
                            {[1, 2, 3, 4].map((i) => (
                              <div
                                key={i}
                                className={cn(
                                  "h-1 flex-1 rounded-full transition-all duration-300",
                                  i <= pwStrength.level ? pwStrength.color : "bg-white/10"
                                )}
                              />
                            ))}
                          </div>
                          <p className="text-[11px] text-muted-foreground">{pwStrength.label}</p>
                        </div>
                      )}
                    </div>

                    {/* New Password fields (reset-password mode only) */}
                    <div className={cn(
                      "space-y-4 transition-all duration-400 overflow-hidden",
                      mode === "reset-password" ? "max-h-[260px] opacity-100" : "max-h-0 opacity-0"
                    )}>
                      <div>
                        <Label htmlFor="new-password" className="text-xs font-medium text-muted-foreground uppercase tracking-wider mb-1.5 block">New Password</Label>
                        <div className="relative group">
                          <KeyRound className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground transition-colors group-focus-within:text-[hsl(0,84%,60%)] z-10" />
                          <Input
                            id="new-password"
                            type={showPassword ? "text" : "password"}
                            placeholder="Enter new password"
                            value={newPassword}
                            onChange={(e) => setNewPassword(e.target.value)}
                            className="pl-10 pr-10 h-11 rounded-lg text-sm focus-visible:ring-1 focus-visible:ring-offset-0 transition-all duration-300"
                            style={{
                              background: "hsl(0 0% 100% / 0.04)",
                              borderColor: "hsl(0 0% 100% / 0.08)",
                            }}
                            disabled={isLoading}
                            minLength={6}
                          />
                          <button
                            type="button"
                            onClick={() => setShowPassword(!showPassword)}
                            className="absolute right-3.5 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground transition-colors z-10"
                          >
                            {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                          </button>
                        </div>
                        {/* Password strength for reset */}
                        {newPassword && (
                          <div className="mt-2 space-y-1" style={{ animation: "fadeIn 0.3s ease-out" }}>
                            <div className="flex gap-1">
                              {[1, 2, 3, 4].map((i) => (
                                <div
                                  key={i}
                                  className={cn(
                                    "h-1 flex-1 rounded-full transition-all duration-300",
                                    i <= pwStrength.level ? pwStrength.color : "bg-white/10"
                                  )}
                                />
                              ))}
                            </div>
                            <p className="text-[11px] text-muted-foreground">{pwStrength.label}</p>
                          </div>
                        )}
                      </div>
                      <div>
                        <Label htmlFor="confirm-password" className="text-xs font-medium text-muted-foreground uppercase tracking-wider mb-1.5 block">Confirm Password</Label>
                        <div className="relative group">
                          <Lock className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground transition-colors group-focus-within:text-[hsl(0,84%,60%)] z-10" />
                          <Input
                            id="confirm-password"
                            type={showPassword ? "text" : "password"}
                            placeholder="Confirm new password"
                            value={confirmPassword}
                            onChange={(e) => setConfirmPassword(e.target.value)}
                            className="pl-10 h-11 rounded-lg text-sm focus-visible:ring-1 focus-visible:ring-offset-0 transition-all duration-300"
                            style={{
                              background: "hsl(0 0% 100% / 0.04)",
                              borderColor: "hsl(0 0% 100% / 0.08)",
                            }}
                            disabled={isLoading}
                            minLength={6}
                          />
                        </div>
                        {newPassword && confirmPassword && newPassword !== confirmPassword && (
                          <p className="text-xs mt-1.5 flex items-center gap-1" style={{ color: "hsl(0 84% 60%)" }}>
                            <span className="inline-block w-1 h-1 rounded-full bg-current" />
                            Passwords do not match
                          </p>
                        )}
                        {newPassword && confirmPassword && newPassword === confirmPassword && (
                          <p className="text-xs text-green-400 mt-1.5 flex items-center gap-1">
                            <CheckCircle2 className="w-3 h-3" />
                            Passwords match
                          </p>
                        )}
                      </div>
                    </div>

                    {/* Forgot Password Link */}
                    {mode === "login" && (
                      <div className="text-right -mt-1">
                        <button
                          type="button"
                          onClick={() => switchMode("forgot")}
                          className="text-sm transition-colors hover:underline"
                          style={{ color: "hsl(0, 84%, 60%)" }}
                        >
                          Forgot password?
                        </button>
                      </div>
                    )}

                    {/* Submit Button */}
                    <Button
                      type="submit"
                      className="w-full h-11 rounded-xl font-medium transition-all duration-300 hover:scale-[1.015] border-0 text-white"
                      style={{
                        background: "linear-gradient(135deg, hsl(0 84% 55%), hsl(0 84% 45%))",
                        boxShadow: "0 4px 20px hsl(0 84% 55% / 0.3)",
                      }}
                      disabled={isLoading || (mode === "reset-password" && (!newPassword || !confirmPassword))}
                    >
                      {isLoading ? (
                        <Loader2 className="w-5 h-5 animate-spin" />
                      ) : (
                        <>
                          {mode === "login" && "Sign In"}
                          {mode === "signup" && "Create Account"}
                          {mode === "forgot" && "Send Reset Link"}
                          {mode === "reset-password" && "Update Password"}
                        </>
                      )}
                    </Button>
                  </form>

                  {/* Footer navigation links */}
                  <div className="mt-5 space-y-2">
                    {/* Back to login for forgot mode */}
                    {mode === "forgot" && (
                      <button
                        onClick={() => switchMode("login")}
                        className="w-full text-sm text-muted-foreground hover:text-foreground transition-colors flex items-center justify-center gap-2"
                      >
                        <ArrowLeft className="w-4 h-4" />
                        Back to sign in
                      </button>
                    )}

                    {/* Back to sign in for reset-password mode */}
                    {mode === "reset-password" && (
                      <button
                        onClick={() => {
                          switchMode("login");
                          navigate("/auth");
                        }}
                        className="w-full text-sm text-muted-foreground hover:text-foreground transition-colors flex items-center justify-center gap-2"
                      >
                        <ArrowLeft className="w-4 h-4" />
                        Back to sign in
                      </button>
                    )}

                    {/* Back to method selection */}
                    {mode !== "forgot" && mode !== "reset-password" && (
                      <button
                        onClick={() => switchMode("select")}
                        className="w-full text-sm text-muted-foreground hover:text-foreground transition-colors flex items-center justify-center gap-2"
                      >
                        <ArrowLeft className="w-4 h-4" />
                        Other sign in options
                      </button>
                    )}
                  </div>
                </div>
              )}
            </div>
          </div>

          {/* Back to home */}
          <button
            onClick={() => navigate("/")}
            className="mt-6 mx-auto flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition-colors"
            style={{ animation: "fadeIn 0.5s ease-out 0.3s both" }}
          >
            <ArrowLeft className="w-4 h-4" />
            Back to home
          </button>
        </div>
      </div>

      {/* Animations */}
      <style>{`
        @keyframes slideDown {
          from { opacity: 0; transform: translateY(-15px); }
          to { opacity: 1; transform: translateY(0); }
        }
        @keyframes slideUp {
          from { opacity: 0; transform: translateY(20px); }
          to { opacity: 1; transform: translateY(0); }
        }
        @keyframes fadeIn {
          from { opacity: 0; }
          to { opacity: 1; }
        }
        @keyframes float {
          0%, 100% { transform: translateY(0); }
          50% { transform: translateY(-12px); }
        }
      `}</style>
    </>
  );
};

export default Auth;