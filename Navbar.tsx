import React from "react";
import { useEffect, useRef, useState } from "react";
import { Link, useNavigate, useLocation } from "react-router-dom";
import { Search, Menu, X, Film, Tv, Home, Sparkles, Bookmark, ArrowLeft, Heart, User, LogOut, FileText, Shield, Globe, KeyRound, Lock } from "lucide-react";
import { cn } from "@/lib/utils";
import { haptic } from "@/lib/haptics";
import { useAuth } from "@/contexts/AuthContext";
import { usePerformanceMode } from "@/contexts/PerformanceModeContext";
import { useAdminStatus } from "@/contexts/AdminStatusContext";
import { useAdminContentVisibility } from "@/contexts/AdminContentVisibilityContext";
import { getSearchScopeForPathname, useSearchOverlay } from "@/contexts/SearchOverlayContext";
import { useEditLinksMode } from "@/contexts/EditLinksModeContext";
import { Switch } from "@/components/ui/switch";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { NotificationBell } from "@/components/NotificationBell";
import { AnimatedBackButton } from "@/components/AnimatedBackButton";
import { useToast } from "@/hooks/use-toast";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

// Module-scope fallbacks (prevents rare TS scope glitches from breaking builds)
// eslint-disable-next-line @typescript-eslint/no-unused-vars
const isScrolled = false;
// eslint-disable-next-line @typescript-eslint/no-unused-vars
const setIsScrolled = (_next: boolean) => { };

export const Navbar = () => {
  const { user, signOut, updatePassword } = useAuth();
  const { isAdmin } = useAdminStatus();
  const { showBlockedPosts, setShowBlockedPosts } = useAdminContentVisibility();
  const { mode, setMode } = usePerformanceMode();
  const { isEditLinksMode, setEditLinksMode } = useEditLinksMode();
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState("");
  const [isSearchOpen, _setIsSearchOpen] = useState(false);
  const [showChangePassword, setShowChangePassword] = useState(false);
  const [changePwNew, setChangePwNew] = useState("");
  const [changePwConfirm, setChangePwConfirm] = useState("");
  const [changePwLoading, setChangePwLoading] = useState(false);
  const [showPwField, setShowPwField] = useState(false);
  const searchRef = useRef<HTMLDivElement>(null);
  const navRef = useRef<HTMLElement | null>(null);
  const navigate = useNavigate();
  const location = useLocation();
  const { open: openSearchOverlay, close: closeSearchOverlay, isOpen: isSearchResultsOpen } = useSearchOverlay();
  const { toast } = useToast();

  // Check if user authenticated via email (not OAuth like Google)
  const isEmailUser = user?.app_metadata?.provider === 'email';

  const clearSearchResults = () => {
    setSearchQuery("");
    closeSearchOverlay();
    setIsSearchOpen(false);
  };

  const setIsSearchOpen = (next: boolean) => {
    _setIsSearchOpen(next);
    try {
      sessionStorage.setItem("navbar_search_open", next ? "1" : "0");
    } catch {
      // ignore
    }
  };

  // Restore search open state after route changes (Navbar is remounted on navigation)
  useEffect(() => {
    try {
      const saved = sessionStorage.getItem("navbar_search_open");
      if (saved === "1") {
        _setIsSearchOpen(true);
      }
    } catch {
      // ignore
    }
  }, []);

  // Close search bar when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      // If a search is active, keep the bar open until the user explicitly clears it.
      if (searchQuery.trim() || isSearchResultsOpen) return;

      // Don't collapse the search bar when interacting anywhere within the navbar.
      if (navRef.current && navRef.current.contains(event.target as Node)) {
        return;
      }
      if (searchRef.current && !searchRef.current.contains(event.target as Node)) {
        setIsSearchOpen(false);
      }
    };

    if (isSearchOpen) {
      document.addEventListener("mousedown", handleClickOutside);
    }

    return () => {
      document.removeEventListener("mousedown", handleClickOutside);
    };
  }, [isSearchOpen, isSearchResultsOpen, searchQuery]);

  // Check if we're on a details page
  const isDetailsPage =
    location.pathname.startsWith("/movie/") || location.pathname.startsWith("/tv/");

  const backgroundLocation = (location.state as any)?.backgroundLocation;
  const isModalDetails = isDetailsPage && Boolean(backgroundLocation);

  // Keep active-page glow always visible (even when modals are open).
  const allowActiveGlow = true;

  const getUrlParam = (key: string) => {
    const sp = new URLSearchParams(location.search);
    return sp.get(key) || "";
  };

  const scrollToTopInstant = () => {
    // Force an immediate jump even if the app/theme enables smooth scrolling.
    const root = document.documentElement;
    const prev = root.style.scrollBehavior;
    root.style.scrollBehavior = "auto";
    window.scrollTo({ top: 0, left: 0 });
    requestAnimationFrame(() => {
      root.style.scrollBehavior = prev;
    });
  };


  // Sync search query from URL when navigating to search page
  useEffect(() => {
    if (location.pathname !== "/search") return;

    const urlQuery = getUrlParam("q");
    setSearchQuery(urlQuery);
    if (urlQuery) {
      setIsSearchOpen(true);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [location.pathname, location.search]);

  // Close menu when route changes
  useEffect(() => {
    setIsMenuOpen(false);
  }, [location.pathname]);

  // Expose header height as a CSS var so global loaders can start below it.
  useEffect(() => {
    const el = navRef.current;
    if (!el) return;

    const update = () => {
      document.documentElement.style.setProperty("--app-header-offset", `${el.offsetHeight}px`);
    };

    update();

    // Some environments may not support ResizeObserver; avoid crashing the app.
    let ro: ResizeObserver | null = null;
    if (typeof ResizeObserver !== "undefined") {
      ro = new ResizeObserver(() => update());
      ro.observe(el);
    }

    window.addEventListener("resize", update);
    return () => {
      ro?.disconnect();
      window.removeEventListener("resize", update);
    };
  }, []);

  // Scroll-reactive tint strength: strongest at top, fades as you scroll.
  useEffect(() => {
    const root = document.documentElement;

    const update = () => {
      const y = Math.max(0, window.scrollY || 0);
      // Fade over first ~520px of scroll.
      const t = Math.min(1, y / 520);
      // Subtle range: 0.18 -> 0.06
      const alpha = 0.18 * (1 - t) + 0.06 * t;
      root.style.setProperty("--navbar-tint-alpha", alpha.toFixed(3));
    };

    update();
    window.addEventListener("scroll", update, { passive: true });
    return () => window.removeEventListener("scroll", update);
  }, []);

  // Prevent body scroll when menu is open
  useEffect(() => {
    if (isMenuOpen) {
      document.body.style.overflow = "hidden";
    } else {
      document.body.style.overflow = "";
    }
    return () => {
      document.body.style.overflow = "";
    };
  }, [isMenuOpen]);

  const handleSearchChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value;
    setSearchQuery(value);

    // Clearing should NEVER navigate away; just close overlay.
    if (!value.trim()) closeSearchOverlay();
  };

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();

    if (!searchQuery.trim()) return;

    haptic("tap");

    // Stay on the same page: open overlay + strict scope.
    openSearchOverlay({
      query: searchQuery.trim(),
      scope: getSearchScopeForPathname(location.pathname),
    });
  };

  const handleClearSearch = () => {
    haptic("tap");
    clearSearchResults();
  };

  const handleBack = () => {
    if (window.history.length > 1) {
      navigate(-1);
    } else {
      navigate('/');
    }
  };

  // Desktop navigation links - no Home
  const navLinks = [
    { to: "/movies", label: "Movies", icon: Film },
    { to: "/tv", label: "TV Shows", icon: Tv },
    { to: "/anime", label: "Anime", icon: Sparkles },
    { to: "/korean", label: "Korean", icon: Heart },
    { to: "/watchlist", label: "Watch List", icon: Bookmark },
  ];

  // Mobile menu links - includes Home at the start
  const mobileNavLinks = [
    { to: "/", label: "Home", icon: Home },
    ...navLinks,
    ...(user && !isAdmin ? [{ to: "/requests", label: "My Requests", icon: FileText }] : []),
    ...(user && isAdmin ? [{ to: "/admin", label: "Admin Panel", icon: Shield }] : []),
  ];

  return (
    <>
      <nav
        ref={navRef}
        className={cn(
          "app-navbar fixed top-0 left-0 right-0 z-50 h-16 backdrop-blur-2xl supports-[backdrop-filter]:bg-background/65 bg-background/80 transition-[background-color] duration-300 ease-out",
        )}
      >
        {/* Bottom glow effect */}
        {/* Dynamic tint overlay (driven by --navbar-tint) */}
        <div className="absolute inset-0 pointer-events-none navbar-tint-layer" />
        <div className="absolute bottom-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-primary/50 to-transparent" />
        <div className="absolute bottom-0 left-1/4 right-1/4 h-8 bg-gradient-to-t from-primary/10 to-transparent blur-xl pointer-events-none" />

        <div className="container mx-auto h-16 px-4 flex items-center justify-between relative">
          {/* Left side: Menu toggle + Logo for mobile */}
          <div className="flex items-center gap-2 shrink-0">
            <button
              onClick={() => setIsMenuOpen(!isMenuOpen)}
              className="md:hidden p-2 rounded-full hover:bg-secondary/50 transition-colors"
              aria-label="Toggle menu"
              data-tutorial="mobile-menu"
            >
              <Menu className="w-5 h-5" />
            </button>

            {/* Logo - Always visible on left */}
            <Link
              to="/"
              className={cn(
                "flex items-center gap-2 group transition-all duration-300",
                isSearchOpen && "md:flex hidden"
              )}
              onClick={() => {
                scrollToTopInstant();
                clearSearchResults();
                haptic("tap");
              }}
            >
              <div className="relative w-8 h-8 md:w-10 md:h-10 flex items-center justify-center transition-all duration-500 group-hover:scale-110">
                <svg viewBox="0 0 100 100" className="w-full h-full drop-shadow-[0_0_10px_hsl(var(--primary)/0.5)] group-hover:drop-shadow-[0_0_15px_hsl(var(--primary)/0.8)] transition-all duration-500">
                  <defs>
                    <linearGradient id="logoGradient" x1="0%" y1="0%" x2="100%" y2="100%">
                      <stop offset="0%" stopColor="hsl(0, 84%, 65%)" />
                      <stop offset="100%" stopColor="hsl(0, 84%, 50%)" />
                    </linearGradient>
                  </defs>
                  <path
                    d="M25 15 C15 15 10 25 10 50 C10 75 15 85 25 85 L55 85 C75 85 90 70 90 50 C90 30 75 15 55 15 L40 15 L40 25 L55 25 C68 25 78 35 78 50 C78 65 68 75 55 75 L25 75 C22 75 22 70 22 50 C22 30 22 25 25 25 L25 15 Z M30 35 L30 65 L55 65 C60 65 65 60 65 50 C65 40 60 35 55 35 L30 35 Z"
                    fill="url(#logoGradient)"
                  />
                </svg>
              </div>
              <span className="text-base md:text-xl font-bold tracking-tight">
                Danie<span className="text-primary">Watch</span>
              </span>
            </Link>
          </div>

          {/* Center: Desktop Navigation */}
          <div className="hidden md:flex items-center gap-8 absolute left-1/2 -translate-x-1/2" data-tutorial="navigation">
            {navLinks.map((link) => {
              const isActive = location.pathname === link.to;
              return (
                <Link
                  key={link.to}
                  to={link.to}
                  onClick={() => {
                    scrollToTopInstant();
                    clearSearchResults();
                    haptic("tap");
                  }}
                  className={cn(
                    "nav-link-glow flex items-center gap-2 transition-all duration-300",
                    isActive && "nav-link-glow-active",
                    isActive ? "text-foreground" : "text-foreground/70 hover:text-foreground"
                  )}
                >
                  <link.icon className="w-4 h-4" />
                  {link.label}
                </Link>
              );
            })}
          </div>

          {/* Right side: Search + User */}
          <div className={cn(
            "flex items-center gap-2 transition-all duration-300",
            isSearchOpen && "md:flex-none flex-1 ml-2"
          )} ref={searchRef}>
            <form
              onSubmit={handleSearch}
              className={cn(
                "flex items-center transition-all duration-300",
                isSearchOpen ? "flex-1 md:flex-none md:w-64" : "w-auto"
              )}
            >
              {isSearchOpen ? (
                <div className="relative w-full">
                  <input
                    type="text"
                    value={searchQuery}
                    onChange={handleSearchChange}
                    placeholder="Search..."
                    className="w-full bg-secondary/50 border border-border rounded-full px-4 py-2 pr-10 text-sm focus:outline-none focus:ring-2 focus:ring-primary/50 placeholder:text-muted-foreground"
                    autoFocus
                  />
                  <button
                    type={searchQuery.trim() ? "button" : "submit"}
                    onClick={searchQuery.trim() ? handleClearSearch : undefined}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
                    aria-label={searchQuery.trim() ? "Clear search" : "Search"}
                  >
                    {searchQuery.trim() ? <X className="w-4 h-4" /> : <Search className="w-4 h-4" />}
                  </button>
                </div>
              ) : (
                <button
                  type="button"
                  onClick={() => {
                    haptic("tap");
                    setIsSearchOpen(true);
                  }}
                  className="p-2 rounded-full hover:bg-secondary/50 transition-colors"
                  aria-label="Search"
                  data-tutorial="search"
                >
                  <Search className="w-5 h-5" />
                </button>
              )}
            </form>

            {/* Notification Bell & User Menu */}
            {user && <NotificationBell />}

            {user ? (
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <button
                    className="p-1 rounded-full hover:bg-secondary/50 transition-colors"
                    onClick={() => {
                      clearSearchResults();
                      haptic("tap");
                    }}
                  >
                    <Avatar className="w-8 h-8">
                      <AvatarFallback className="bg-primary/20 text-primary text-sm">
                        {user.email?.charAt(0).toUpperCase() || 'U'}
                      </AvatarFallback>
                    </Avatar>
                  </button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end" className="w-56">
                  <div className="px-2 py-1.5 text-sm text-muted-foreground truncate">{user.email}</div>
                  <DropdownMenuSeparator />

                  <DropdownMenuLabel className="text-xs">Rendering</DropdownMenuLabel>
                  <DropdownMenuRadioGroup
                    value={mode}
                    onValueChange={(v) => {
                      haptic("tap");
                      setMode(v as any);
                    }}
                  >
                    <DropdownMenuRadioItem value="quality">Quality</DropdownMenuRadioItem>
                    <DropdownMenuRadioItem value="performance">Performance</DropdownMenuRadioItem>
                  </DropdownMenuRadioGroup>
                  <DropdownMenuSeparator />

                  <DropdownMenuItem asChild>
                    <Link
                      to="/watchlist"
                      className="cursor-pointer"
                      onClick={() => {
                        scrollToTopInstant();
                        clearSearchResults();
                        haptic("tap");
                      }}
                    >
                      <Bookmark className="w-4 h-4 mr-2" />
                      My Watchlist
                    </Link>
                  </DropdownMenuItem>

                  {!isAdmin && (
                    <DropdownMenuItem asChild>
                      <Link
                        to="/requests"
                        className="cursor-pointer"
                        onClick={() => {
                          scrollToTopInstant();
                          clearSearchResults();
                          haptic("tap");
                        }}
                      >
                        <FileText className="w-4 h-4 mr-2" />
                        My Requests
                      </Link>
                    </DropdownMenuItem>
                  )}

                  {isAdmin && (
                    <DropdownMenuItem asChild>
                      <Link
                        to="/admin"
                        className="cursor-pointer"
                        onClick={() => {
                          scrollToTopInstant();
                          clearSearchResults();
                          haptic("tap");
                        }}
                      >
                        <Shield className="w-4 h-4 mr-2" />
                        Admin Panel
                      </Link>
                    </DropdownMenuItem>
                  )}

                  {isAdmin && (
                    <>
                      <DropdownMenuSeparator />
                      <div className="px-2 py-1.5 text-xs font-semibold text-muted-foreground">Admin filters</div>

                      <DropdownMenuItem
                        onSelect={(e) => e.preventDefault()}
                        className="cursor-default flex items-center justify-between gap-3"
                      >
                        <span className="text-sm">Edit Links mode</span>
                        <Switch
                          checked={isEditLinksMode}
                          onCheckedChange={(v) => setEditLinksMode(Boolean(v))}
                          aria-label={isEditLinksMode ? "Disable Edit Links mode" : "Enable Edit Links mode"}
                        />
                      </DropdownMenuItem>

                      <DropdownMenuItem
                        onSelect={(e) => e.preventDefault()}
                        className="cursor-default flex items-center justify-between gap-3"
                      >
                        <span className="text-sm">Show blocked posts</span>
                        <Switch
                          checked={showBlockedPosts}
                          onCheckedChange={(v) => setShowBlockedPosts(Boolean(v))}
                          aria-label={showBlockedPosts ? "Show blocked posts" : "Hide blocked posts"}
                        />
                      </DropdownMenuItem>
                    </>
                  )}

                  <DropdownMenuSeparator />

                  {/* Change Password - only for email users */}
                  {isEmailUser && (
                    <DropdownMenuItem
                      onClick={() => {
                        haptic("tap");
                        setShowChangePassword(true);
                      }}
                      className="cursor-pointer"
                    >
                      <KeyRound className="w-4 h-4 mr-2" />
                      Change Password
                    </DropdownMenuItem>
                  )}

                  <DropdownMenuItem
                    onClick={() => {
                      haptic("tap");
                      signOut();
                    }}
                    className="cursor-pointer text-destructive"
                  >
                    <LogOut className="w-4 h-4 mr-2" />
                    Sign Out
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            ) : (
              <Link
                to="/auth"
                onClick={() => {
                  scrollToTopInstant();
                  clearSearchResults();
                  haptic("tap");
                }}
                className="p-2 rounded-full hover:bg-secondary/50 transition-colors"
                aria-label="Sign in"
              >
                <User className="w-5 h-5" />
              </Link>
            )}
          </div>
        </div>

      </nav>

      {/* Sticky Back button on details pages (full-page only; modal has its own back button) */}
      {isDetailsPage && !isModalDetails && (
        <div className="hidden md:block fixed left-4 top-20 z-[60]">
          <AnimatedBackButton label="Back" size="navbar" />
        </div>
      )}

      {/* Mobile Menu Overlay */}
      <div
        className={cn(
          "md:hidden fixed inset-0 z-[100] transition-opacity duration-300",
          isMenuOpen ? "opacity-100 pointer-events-auto" : "opacity-0 pointer-events-none"
        )}
      >
        {/* Backdrop */}
        <div
          className="absolute inset-0 bg-background/80 backdrop-blur-md"
          onClick={() => setIsMenuOpen(false)}
        />

        {/* Menu Panel */}
        <div
          className={cn(
            "absolute top-0 left-0 h-full w-72 bg-card/95 backdrop-blur-xl border-r border-border shadow-2xl transform transition-transform duration-300 ease-out will-change-transform",
            isMenuOpen ? "translate-x-0" : "-translate-x-full"
          )}
        >
          {/* Menu Header */}
          <div className="flex items-center justify-between p-4 border-b border-border">
            <Link
              to="/"
              onClick={() => {
                scrollToTopInstant();
                clearSearchResults();
                haptic("tap");
                setIsMenuOpen(false);
              }}
              className="flex items-center gap-2"
            >
              <div className="w-8 h-8">
                <svg viewBox="0 0 100 100" className="w-full h-full drop-shadow-[0_0_10px_hsl(var(--primary)/0.5)]">
                  <defs>
                    <linearGradient id="logoGradientMenu" x1="0%" y1="0%" x2="100%" y2="100%">
                      <stop offset="0%" stopColor="hsl(0, 84%, 65%)" />
                      <stop offset="100%" stopColor="hsl(0, 84%, 50%)" />
                    </linearGradient>
                  </defs>
                  <path
                    d="M25 15 C15 15 10 25 10 50 C10 75 15 85 25 85 L55 85 C75 85 90 70 90 50 C90 30 75 15 55 15 L40 15 L40 25 L55 25 C68 25 78 35 78 50 C78 65 68 75 55 75 L25 75 C22 75 22 70 22 50 C22 30 22 25 25 25 L25 15 Z M30 35 L30 65 L55 65 C60 65 65 60 65 50 C65 40 60 35 55 35 L30 35 Z"
                    fill="url(#logoGradientMenu)"
                  />
                </svg>
              </div>
              <span className="text-lg font-bold">
                Danie<span className="text-primary">Watch</span>
              </span>
            </Link>
            <button
              onClick={() => setIsMenuOpen(false)}
              className="p-2 rounded-full hover:bg-secondary/50 transition-colors"
              aria-label="Close menu"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          <nav className="p-4">
            <ul className="space-y-1">
              {mobileNavLinks.map((link, index) => (
                <li
                  key={link.to}
                  style={{
                    animationDelay: `${index * 50}ms`,
                    opacity: isMenuOpen ? 1 : 0,
                    transform: isMenuOpen ? 'translateX(0)' : 'translateX(-20px)',
                    transition: `opacity 0.3s ease ${index * 50}ms, transform 0.3s ease ${index * 50}ms`
                  }}
                >
                  <Link
                    to={link.to}
                    onClick={() => {
                      scrollToTopInstant();
                      clearSearchResults();
                      haptic("tap");
                      setIsMenuOpen(false);
                    }}
                    className={cn(
                      "nav-link-glow flex items-center gap-4 px-4 py-3.5 rounded-xl transition-all duration-200",
                      location.pathname === link.to
                        ? "nav-link-glow-active bg-primary/15 text-primary"
                        : "text-foreground/80 hover:bg-secondary/50 hover:text-foreground"
                    )}
                  >
                    <link.icon className={cn(
                      "w-5 h-5",
                      location.pathname === link.to && "text-primary"
                    )} />
                    <span className="font-medium">{link.label}</span>
                    {location.pathname === link.to && (
                      <div className="ml-auto w-1.5 h-1.5 rounded-full bg-primary" />
                    )}
                  </Link>
                </li>
              ))}
            </ul>
          </nav>

          {/* Menu Footer */}
          <div className="absolute bottom-0 left-0 right-0 p-4 border-t border-border">
            <p className="text-xs text-muted-foreground text-center">
              © 2024 DanieWatch
            </p>
          </div>
        </div>
      </div>

      {/* Change Password Dialog */}
      <Dialog open={showChangePassword} onOpenChange={(open) => {
        setShowChangePassword(open);
        if (!open) {
          setChangePwNew("");
          setChangePwConfirm("");
          setShowPwField(false);
        }
      }}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Change Password</DialogTitle>
            <DialogDescription>
              Enter your new password below. Minimum 6 characters.
            </DialogDescription>
          </DialogHeader>
          <form
            onSubmit={async (e) => {
              e.preventDefault();
              if (changePwNew.length < 6) {
                toast({
                  title: "Error",
                  description: "Password must be at least 6 characters",
                  variant: "destructive",
                });
                return;
              }
              if (changePwNew !== changePwConfirm) {
                toast({
                  title: "Error",
                  description: "Passwords do not match",
                  variant: "destructive",
                });
                return;
              }
              setChangePwLoading(true);
              try {
                const { error } = await updatePassword(changePwNew);
                if (error) {
                  toast({
                    title: "Error",
                    description: error.message || "Failed to update password",
                    variant: "destructive",
                  });
                } else {
                  toast({
                    title: "Password Updated! 🔑",
                    description: "Your password has been changed successfully.",
                  });
                  setShowChangePassword(false);
                  setChangePwNew("");
                  setChangePwConfirm("");
                }
              } catch {
                toast({
                  title: "Error",
                  description: "Something went wrong. Please try again.",
                  variant: "destructive",
                });
              } finally {
                setChangePwLoading(false);
              }
            }}
            className="space-y-4 mt-2"
          >
            <div className="space-y-2">
              <Label htmlFor="nav-new-password">New Password</Label>
              <div className="relative">
                <KeyRound className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                <Input
                  id="nav-new-password"
                  type={showPwField ? "text" : "password"}
                  placeholder="Enter new password"
                  value={changePwNew}
                  onChange={(e) => setChangePwNew(e.target.value)}
                  className="pl-10"
                  disabled={changePwLoading}
                  minLength={6}
                  autoFocus
                />
              </div>
            </div>
            <div className="space-y-2">
              <Label htmlFor="nav-confirm-password">Confirm Password</Label>
              <div className="relative">
                <Lock className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
                <Input
                  id="nav-confirm-password"
                  type={showPwField ? "text" : "password"}
                  placeholder="Confirm new password"
                  value={changePwConfirm}
                  onChange={(e) => setChangePwConfirm(e.target.value)}
                  className="pl-10"
                  disabled={changePwLoading}
                  minLength={6}
                />
              </div>
              {changePwNew && changePwConfirm && changePwNew !== changePwConfirm && (
                <p className="text-xs text-destructive">Passwords do not match</p>
              )}
            </div>
            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                id="show-pw-toggle"
                checked={showPwField}
                onChange={(e) => setShowPwField(e.target.checked)}
                className="rounded border-border"
              />
              <Label htmlFor="show-pw-toggle" className="text-sm text-muted-foreground cursor-pointer">
                Show passwords
              </Label>
            </div>
            <div className="flex gap-3 pt-2">
              <Button
                type="button"
                variant="outline"
                onClick={() => setShowChangePassword(false)}
                className="flex-1"
                disabled={changePwLoading}
              >
                Cancel
              </Button>
              <Button
                type="submit"
                className="flex-1"
                disabled={changePwLoading || !changePwNew || !changePwConfirm}
              >
                {changePwLoading ? "Updating..." : "Update Password"}
              </Button>
            </div>
          </form>
        </DialogContent>
      </Dialog>
    </>
  );
};
